#!/usr/bin/env bash
# Builds and runs the CordisShowcase app.
#
#   ./run.sh sim [app args…]        build, install and launch on a simulator
#   ./run.sh device [app args…]     build, install and launch on a connected iPhone
#   ./run.sh test                   run the ShowcaseKit tests (macOS, swift test)
#   ./run.sh uitest                 run the XCUITest suite on a simulator
#
# Environment:
#   SIMULATOR   simulator name or UDID        (default: first available iPhone)
#   DEVICE      device name or identifier     (default: first connected iPhone)
#   TEAM_ID     Apple development team for device signing (required for `device`)
#
# App arguments: `-resetEntries YES` starts from the default entries,
# `-tourSteps N` runs the first N tour steps, `-tab dashboard|plugins|…`
# selects the initial tab.
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
  *)
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
