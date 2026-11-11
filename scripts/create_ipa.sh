#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/create_ipa.sh [--bundle-id IDENTIFIER] [--output PATH]

Builds an ad-hoc signed iOS IPA containing the iPhone companion app and its
embedded Apple Watch app. Requires macOS, Xcode, and xcodebuild. No signing
certificate, provisioning profile, or Apple account is used. Feather (and
Sideloadly) can re-sign the IPA with your own certificate.

The watch bundle id is <bundle-id>.watchkitapp and WKCompanionAppBundleIdentifier
is <bundle-id>. Feather rewrites both by replacing the original bundle id, so
keep that prefix relationship. The ad-hoc signature carries
group.<bundle-id> so a re-signer that preserves entitlements keeps the app group
the watch app looks up at runtime.

Options:
  --bundle-id IDENTIFIER  iOS app bundle ID (watch ID becomes IDENTIFIER.watchkitapp)
  --output PATH           IPA output path (default: build/ipa/HermesEnabler.ipa)
  -h, --help              Show this help
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle_id="com.example.HermesEnabler"
output_path="$repo_root/build/ipa/HermesEnabler.ipa"

while (($#)); do
    case "$1" in
        --bundle-id)
            [[ $# -ge 2 ]] || { echo "Missing value for --bundle-id" >&2; exit 2; }
            bundle_id="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || { echo "Missing value for --output" >&2; exit 2; }
            output_path="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script needs macOS and Xcode to compile iOS and watchOS apps." >&2
    echo "It does not need a signing certificate, provisioning profile, or Apple account." >&2
    exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild was not found. Install Xcode and select it with xcode-select." >&2
    exit 1
fi

if [[ ! "$bundle_id" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
    echo "Invalid bundle identifier: $bundle_id" >&2
    exit 2
fi

case "$output_path" in
    /*) ;;
    *) output_path="$repo_root/$output_path" ;;
esac

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hermes-unsigned-ipa.XXXXXX")"
cleanup() {
    rm -rf "$temp_dir"
}
trap cleanup EXIT

derived_data="$temp_dir/DerivedData"
app_path="$derived_data/Build/Products/Release-iphoneos/HermesCompanion.app"
staging_path="$temp_dir/staging"

echo "Building iPhone app and embedded Watch app without a certificate..."
xcodebuild \
    -project "$repo_root/HermesEnabler2.xcodeproj" \
    -scheme HermesCompanion \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived_data" \
    COMPANION_BUNDLE_IDENTIFIER="$bundle_id" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    build

if [[ ! -d "$app_path" ]]; then
    echo "Build succeeded but the iPhone app was not found at: $app_path" >&2
    exit 1
fi

watch_app="$(find "$app_path/Watch" -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null || true)"
if [[ -z "$watch_app" ]]; then
    echo "The built iPhone app does not contain an embedded Watch app." >&2
    echo "Expected a Watch/*.app bundle inside HermesCompanion.app." >&2
    exit 1
fi

plist_value() {
    plutil -extract "$2" raw -o - "$1"
}

companion_id="$(plist_value "$app_path/Info.plist" CFBundleIdentifier)"
watch_id="$(plist_value "$watch_app/Info.plist" CFBundleIdentifier)"
watch_companion="$(plist_value "$watch_app/Info.plist" WKCompanionAppBundleIdentifier)"
watch_exec="$(plist_value "$watch_app/Info.plist" CFBundleExecutable)"
expected_watch_id="${bundle_id}.watchkitapp"

if [[ "$companion_id" != "$bundle_id" || "$watch_id" != "$expected_watch_id" || "$watch_companion" != "$bundle_id" ]]; then
    echo "Watch/iPhone bundle relationship is not Feather-safe." >&2
    echo "  iPhone CFBundleIdentifier: $companion_id" >&2
    echo "  Watch CFBundleIdentifier: $watch_id" >&2
    echo "  WKCompanionAppBundleIdentifier: $watch_companion" >&2
    echo "Expected $bundle_id and $expected_watch_id with WKCompanionAppBundleIdentifier $bundle_id." >&2
    exit 1
fi

if [[ ! -f "$watch_app/Info.plist" ]]; then
    echo "Watch app is missing Info.plist. Feather deletes Watch apps without one." >&2
    exit 1
fi

# watchOS 26+ devices are arm64. The arm64_32 slice is for watches that cannot
# run this deployment target, and Feather's zsign has failed to re-sign some
# fat watch binaries. Keep the arm64 slice only.
watch_bin="$watch_app/$watch_exec"
if lipo -info "$watch_bin" 2>/dev/null | grep -q 'arm64_32'; then
    echo "Thinning Watch executable to arm64..."
    lipo "$watch_bin" -thin arm64 -output "$watch_bin.arm64"
    mv "$watch_bin.arm64" "$watch_bin"
fi

group_id="group.${bundle_id}"
entitlements="$temp_dir/adhoc.entitlements"
cat >"$entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.security.application-groups</key>
    <array><string>${group_id}</string></array>
</dict></plist>
EOF

sign_bundle() {
    local target="$1"
    if codesign --force --sign - --timestamp=none --generate-entitlement-der \
        --entitlements "$entitlements" "$target"; then
        return 0
    fi
    echo "Retrying ad-hoc signature without a DER entitlement slot..." >&2
    codesign --force --sign - --timestamp=none --entitlements "$entitlements" "$target"
}

echo "Ad-hoc signing the Watch app, then the iPhone app..."
sign_bundle "$watch_app"
sign_bundle "$app_path"

if find "$app_path" -name embedded.mobileprovision -print -quit | grep -q .; then
    echo "A provisioning profile was embedded. This IPA must stay free of profiles so Feather can supply yours." >&2
    exit 1
fi

codesign --verify --strict "$watch_app"
codesign --verify --strict "$app_path"
codesign -d --entitlements :- "$watch_app" 2>/dev/null | grep -F -q "$group_id"
codesign -d --entitlements :- "$app_path" 2>/dev/null | grep -F -q "$group_id"

mkdir -p "$staging_path/Payload" "$(dirname "$output_path")"
ditto "$app_path" "$staging_path/Payload/HermesCompanion.app"
# Payload/ must be the archive root. Feather imports that layout and looks for
# Watch/*.app with an Info.plist under the iPhone app.
ditto -c -k --sequesterRsrc --keepParent "$staging_path/Payload" "$output_path"

if ! unzip -l "$output_path" | grep -q "Payload/HermesCompanion.app/Watch/.*Info.plist"; then
    echo "IPA is missing Payload/.../Watch/*.app/Info.plist." >&2
    unzip -l "$output_path" >&2 || true
    exit 1
fi

echo "Created ad-hoc IPA: $output_path"
echo "Embedded Watch app: Payload/HermesCompanion.app/Watch/$(basename "$watch_app")"
echo "Bundle IDs: $bundle_id and $expected_watch_id"
echo "App group in the ad-hoc signature: $group_id"
echo "Re-sign with Feather or Sideloadly before installing. No Apple certificate was used."
