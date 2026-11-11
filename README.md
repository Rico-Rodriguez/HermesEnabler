# HermesEnabler 2

[English](README.md) · [한국어](README.ko.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md)

![](image.png)

> Supported only on watchOS 27.0 through 27.3 beta 1.

## Installation

### Install the IPA with Feather

1. Download `HermesEnabler.ipa` from [Releases](https://github.com/Rico-Rodriguez/HermesEnabler/releases).
2. Import it into [Feather](https://github.com/khcrysalis/Feather) and sign it. Use these settings:
   - **Identifier:** set this to a bundle id your provisioning profile allows. Leave the Watch app id alone. Feather rewrites it to `<identifier>.watchkitapp` and sets `WKCompanionAppBundleIdentifier` to `<identifier>`.
   - **PPQ Protection:** off, unless the profile is a wildcard that still matches after Feather appends its random suffix.
   - **App ID:** must cover both the iPhone id and `<identifier>.watchkitapp`. A wildcard (`TEAMID.*` or `TEAMID.com.you.*`) does. An explicit profile for only the iPhone id makes the watch install fail with “integrity could not be verified”, because Feather stamps that one `application-identifier` onto the watch executable.
   - **Remove Provisioning:** off. Do not delete the `Watch` folder. The Watch app includes `Info.plist`; Feather only removes a Watch bundle that is missing that file.
   - **App Group:** if the profile has one, prefer `group.<iPhone bundle id>`. The watch app also accepts `group.<watch bundle id>`, a renamed group, and a `group.*` wildcard expanded from the bundle id it is actually signed with. On watchOS 27.2 the feature needs an app group. Wildcard profiles often cannot include App Groups; a profile that does not grant one can still install, but Backup MG may fail on 27.2.
   - **Devices:** a development or ad-hoc profile must include the Apple Watch UDID as well as the iPhone. Enterprise profiles do not list UDIDs.
3. Install the signed app on the iPhone.
4. On the iPhone, open the **Watch** app and install **HermesEnabler2** from **My Watch → Apps**.
5. Open **HermesEnabler2** on the Apple Watch and follow the steps in the app.

### Install the IPA with Sideloadly

1. Download the IPA from [Releases](https://github.com/Rico-Rodriguez/HermesEnabler/releases).
2. Install it with [Sideloadly](https://sideloadly.io). When Sideloadly changes the bundle id, keep the watch id as `<that id>.watchkitapp`.
3. On your iPhone, open the **Watch** app and install **HermesEnabler2** from **My Watch → Apps**.
4. Open **HermesEnabler2** on your Apple Watch and follow the steps in the app.

### Build with Xcode

1. Open `HermesEnabler2.xcodeproj` in Xcode.
2. Select your Apple Watch as the run destination and click **Run**.
3. Open **HermesEnabler2** on your Apple Watch and follow the steps in the app.

## Credits

This project incorporates code from [Gester](https://github.com/sasobhabha/Gester).

Use at your own risk.
