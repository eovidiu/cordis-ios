#!/usr/bin/env bash
# Builds and runs the CordisShowcase app.
#
#   ./run.sh sim [app args…]        build, install and launch on a simulator
#   ./run.sh device [app args…]     build, install and launch on a connected iPhone
#   ./run.sh test                   run the ShowcaseKit tests (macOS, swift test)
#   ./run.sh uitest                 run the XCUITest suite on a simulator
#   ./run.sh archive                Release archive + App Store Connect export (build/release/)
#   ./run.sh archive upload         same, then upload the build to App Store Connect
#
# Environment:
#   SIMULATOR   simulator name or UDID        (default: first available iPhone)
#   DEVICE      device name or identifier     (default: first connected iPhone)
#   TEAM_ID     Apple development team for signing (required for `device` and `archive`)
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID
#               App Store Connect API key for `archive` when no Apple ID is
#               signed in to Xcode (Settings > Accounts)
#
# App arguments: `-resetEntries YES` starts from the default entries,
# `-tourSteps N` runs the first N tour steps, `-tab dashboard|plugins|…`
# selects the initial tab, `-showAbout YES` opens the credits.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID=com.eovidiu.cordis.showcase
DERIVED=build/DerivedData

generate() {
  command -v xcodegen >/dev/null || { echo "xcodegen is required: brew install xcodegen" >&2; exit 1; }
  xcodegen generate --quiet
}

# UDID of simulator $1 (name or UDID); without $1, the first iPhone on the
# newest iOS runtime.
simulator_udid() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
wanted = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for device in devices[runtime]:
        if (wanted and wanted in (device["udid"], device["name"])) or (not wanted and device["name"].startswith("iPhone")):
            print(device["udid"]); sys.exit(0)
sys.exit("no simulator matches " + repr(wanted or "iPhone"))' "${1:-}"
}

# Hardware UDID of paired iPhone $1 (name, UDID or CoreDevice identifier);
# without $1, the first paired iPhone.
device_udid() {
  local json
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null
  python3 - "$json" "${1:-}" <<'PY'
import json, sys
path, wanted = sys.argv[1], sys.argv[2]
for device in json.load(open(path))["result"]["devices"]:
    hardware = device.get("hardwareProperties", {})
    names = (hardware.get("udid"), device.get("identifier"), device.get("deviceProperties", {}).get("name"))
    paired = device.get("connectionProperties", {}).get("pairingState") == "paired"
    if paired and hardware.get("deviceType") == "iPhone" and (not wanted or wanted in names):
        print(hardware["udid"]); sys.exit(0)
sys.exit("no paired iPhone matches " + repr(wanted or "any"))
PY
  rm -f "$json"
}

case "${1:-}" in
  sim)
    shift
    generate
    sim="$(simulator_udid "${SIMULATOR:-}")"
    xcrun simctl boot "$sim" 2>/dev/null || true
    open -a Simulator
    xcodebuild -project CordisShowcase.xcodeproj -scheme CordisShowcase \
      -destination "platform=iOS Simulator,id=$sim" \
      -derivedDataPath "$DERIVED" -skipMacroValidation -quiet build
    xcrun simctl install "$sim" "$DERIVED/Build/Products/Debug-iphonesimulator/CordisShowcase.app"
    xcrun simctl launch --terminate-running-process "$sim" "$BUNDLE_ID" "$@"
    ;;
  device)
    shift
    : "${TEAM_ID:?set TEAM_ID to your Apple development team id}"
    generate
    device="$(device_udid "${DEVICE:-}")"
    xcodebuild -project CordisShowcase.xcodeproj -scheme CordisShowcase \
      -destination "platform=iOS,id=$device" -derivedDataPath "$DERIVED" \
      -skipMacroValidation -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" -quiet build
    xcrun devicectl device install app --device "$device" "$DERIVED/Build/Products/Debug-iphoneos/CordisShowcase.app"
    # `--` keeps devicectl from parsing the app's `-flag value` arguments.
    xcrun devicectl device process launch --terminate-existing --device "$device" "$BUNDLE_ID" -- "$@"
    ;;
  test)
    swift test --package-path ShowcaseKit
    ;;
  uitest)
    generate
    sim="$(simulator_udid "${SIMULATOR:-}")"
    xcodebuild -project CordisShowcase.xcodeproj -scheme CordisShowcase \
      -destination "platform=iOS Simulator,id=$sim" \
      -derivedDataPath "$DERIVED" -skipMacroValidation -quiet test
    ;;
  archive)
    : "${TEAM_ID:?set TEAM_ID to your Apple development team id}"
    destination=export
    [ "${2:-}" = upload ] && destination=upload
    generate
    rm -rf build/release
    mkdir -p build/release
    xcodebuild -project CordisShowcase.xcodeproj -scheme CordisShowcase -configuration Release \
      -destination 'generic/platform=iOS' -archivePath build/release/CordisShowcase.xcarchive \
      -skipMacroValidation -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" -quiet archive
    cat > build/release/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
    # Exporting for App Store Connect creates a distribution certificate and
    # profile, which needs an Apple ID in Xcode > Settings > Accounts or an
    # App Store Connect API key (ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID).
    auth=()
    if [ -n "${ASC_KEY_PATH:-}" ]; then
      auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "${ASC_KEY_ID:?}" \
        -authenticationKeyIssuerID "${ASC_ISSUER_ID:?}")
    fi
    xcodebuild -exportArchive -archivePath build/release/CordisShowcase.xcarchive \
      -exportPath build/release/export -exportOptionsPlist build/release/ExportOptions.plist \
      -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}
    ls build/release/export
    ;;
  *)
    sed -n '2,21p' "$(basename "$0")" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
