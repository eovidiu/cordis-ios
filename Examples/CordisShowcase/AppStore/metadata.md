# Cordis Showcase: App Store Connect metadata

Copy these fields into App Store Connect. The length limits are Apple's. `AppStore/check.sh` checks the limits.

## App information

| Field | Value |
| --- | --- |
| Name | Cordis Showcase |
| Subtitle | Plugin systems, explained |
| Bundle ID | com.eovidiu.cordis.showcase |
| SKU | cordis-showcase-ios |
| Primary category | Developer Tools |
| Secondary category | Education |
| Content rights | Contains no third-party content requiring rights. Credits and the MIT notice for cordis are in the app's About screen. |
| Age rating | 4+ (answer "None" to every questionnaire item; no web browsing in-app: links open Safari) |
| Price | Free |
| Availability | All territories |

## URLs

| Field | Value |
| --- | --- |
| Support URL | https://github.com/eovidiu/cordis-ios/issues |
| Marketing URL | https://eovidiu.github.io/cordis-ios/#/showcase |
| Privacy Policy URL | https://eovidiu.github.io/cordis-ios/#/privacy |

## Version 1.0

### Promotional text

<!-- field: promotional (max 170) -->
Watch a plugin system think. Switch services off and on, break and fix plugins, and see every load, unload and reload happen live in a Swift port of cordis.
<!-- end -->

### Description

<!-- field: description (max 4000) -->
Cordis Showcase is an interactive tour of cordis-ios, a Swift port of the cordis plugin framework.

Everything in the app is built from plugins. Each card on the dashboard is put there by a plugin, and it disappears on its own when that plugin stops. Plugins declare the services they need: when a service goes away, everything that depends on it unloads, and when it comes back, they load again. Nothing has to be cleaned up by hand.

A ten-step guided tour lets you see this happen:
• Withdraw a service and watch its consumers wait
• Change a plugin's configuration and see it reload
• Send an invalid configuration and see it rejected
• Add a missing service and watch a waiting plugin load
• Recover a plugin that failed to start
• Run two versions of one service side by side in isolated realms
• Disable a whole group of plugins at once
• Restart a service that holds state
• Reset everything to the defaults in one reconciliation

Beyond the tour you can explore freely:
• Plugins: every plugin with its live state, an on/off switch, a JSON config editor and the list of effects it has installed
• Services: which plugin provides each service, and who uses it
• Timeline: the framework's internal events and logs as they happen

Credits
cordis is created by Shigma and the cordiverse contributors (github.com/cordiverse/cordis). Its design is described in the paper "A Programming Paradigm for Spatiotemporal Composability" by Yifan Shi, Wei Zhang and Tianyi Cui (arXiv:2608.25512). The Swift port and this app are open source at github.com/eovidiu/cordis-ios. cordis-ios is an independent port and is not affiliated with or endorsed by the cordis authors.

The app collects no data and makes no network requests.
<!-- end -->

### Keywords

<!-- field: keywords (max 100) -->
plugin,swift,framework,dependency injection,services,architecture,developer,reactive,effects,cordis
<!-- end -->

### What's New

<!-- field: whatsnew (max 4000) -->
First release.
<!-- end -->

### Copyright

<!-- field: copyright (max 200) -->
2026 Ovidiu Eftimie
<!-- end -->

## App Review information

| Field | Value |
| --- | --- |
| Sign-in required | No |
| Contact | Ovidiu Eftimie, eovidiu@gmail.com (add a phone number in App Store Connect) |

<!-- field: reviewnotes (max 4000) -->
Cordis Showcase demonstrates an open-source plugin framework (github.com/eovidiu/cordis-ios). No account, no network access and no in-app purchases.

To review: open the Tour tab and tap "Run step" on each step in order. Each step changes the running plugins, and the Dashboard, Plugins, Services and Timeline tabs show the result. The "About" button (top right of the Tour tab) shows credits to the original cordis authors, the research paper and links to the source code. Step 4 shows an error alert on purpose: it demonstrates a configuration being rejected.
<!-- end -->

## App Privacy (nutrition label)

Answer **"No, we do not collect data from this app"**. The app makes no network requests. Its only data is the plugin list it stores on the device (Application Support), which never leaves the device. `PrivacyInfo.xcprivacy` declares no collected data and the UserDefaults reason `CA92.1`.

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is in the Info.plist, so App Store Connect does not ask about encryption for each build.

## Screenshots

6.9-inch iPhone (1320 × 2868) screenshots are in `AppStore/screenshots/`, in upload order. Apple scales them down for smaller iPhones. The app is iPhone-only, so no iPad screenshots are needed.
