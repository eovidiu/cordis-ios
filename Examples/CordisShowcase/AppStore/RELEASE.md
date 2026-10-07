# Releasing Cordis Showcase to the App Store

Status of the prepared items for version 1.0 (build 1). Steps marked **you** need the Apple Developer account holder.

## Prepared and verified in the repository

| Item | Where | Verified by |
| --- | --- | --- |
| Display name "Cordis Showcase", bundle ID `com.eovidiu.cordis.showcase`, version 1.0 (1) | `project.yml` | Info.plist of the Release archive |
| iPhone only (`UIDeviceFamily = [1]`), iOS 17.0+ | `project.yml` | Info.plist of the Release archive |
| `ITSAppUsesNonExemptEncryption = NO`, category Developer Tools | `project.yml` | Info.plist of the Release archive |
| Privacy manifest: no tracking, no collected data, UserDefaults reason `CA92.1` | `App/PrivacyInfo.xcprivacy` | `plutil -p` on the archived app |
| 1024 × 1024 app icon, no alpha | `App/Assets.xcassets/AppIcon.appiconset` | `CFBundleIconName = AppIcon` in the archive |
| About screen: credits to Shigma and the cordiverse contributors, the paper citation, links to cordiverse/cordis, arXiv and eovidiu/cordis-ios, MIT notices | `App/AboutView.swift` | UI test `testAboutCreditsTheCordisTeamCitesThePaperAndLinksTheSwiftPort` |
| Store text, URLs, age rating, review notes, privacy answers | `metadata.md` | `check.sh` (App Store field limits) |
| Six 6.9-inch screenshots, 1320 × 2868, no alpha | `screenshots/` (`screenshots.sh`) | `check.sh` |
| Privacy policy | https://eovidiu.github.io/cordis-ios/#/privacy | `docs/check.sh`, live site |
| Signed Release archive | `../run.sh archive` | archive succeeded, signed with team HV325Z3W39 |

## Remaining steps

1. **You: allow App Store signing.** Sign in to Xcode under *Settings → Accounts* with the Apple ID of team HV325Z3W39. Alternatively, create an App Store Connect API key (*Users and Access → Integrations*, role App Manager) and export `ASC_KEY_PATH`, `ASC_KEY_ID` and `ASC_ISSUER_ID`. Without one of these, the export stops with "No Accounts" because it cannot create the distribution certificate and App Store profile.
2. **You: create the app record.** In App Store Connect, go to *Apps → + → New App*: platform iOS, name **Cordis Showcase**, language English (U.S.), bundle ID `com.eovidiu.cordis.showcase`, SKU `cordis-showcase-ios`. If the name is taken, App Store Connect says so here; choose an alternative such as "Cordis Showcase: Plugins". The name on the home screen stays "Cordis Showcase".
3. Export and upload the build:
   ```sh
   TEAM_ID=HV325Z3W39 Examples/CordisShowcase/run.sh archive upload
   ```
   To keep a local `.ipa` without uploading, run `run.sh archive`; it is written to `build/release/export/`.
4. **You: fill in the version page** from `metadata.md`: promotional text, description, keywords, support and marketing URLs, the copyright line, and the screenshots from `screenshots/` in file-name order.
5. **You: answer App Privacy** with "Data Not Collected", the age-rating questionnaire (4+), and pricing (Free, all territories).
6. **You: select the uploaded build**, paste the review notes from `metadata.md`, add a contact phone number, and submit for review.

## For later versions

- Raise `MARKETING_VERSION` and/or `CURRENT_PROJECT_VERSION` in `project.yml`. Every upload needs a new build number.
- Run `../run.sh test`, `../run.sh uitest`, `screenshots.sh` (if the UI changed) and `check.sh` before archiving.
- If the contributor list changes, update `AboutView.contributors`. The "All cordis contributors" link always shows the current list.
