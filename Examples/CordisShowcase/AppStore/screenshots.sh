#!/usr/bin/env bash
# Captures the App Store screenshots on a 6.9-inch iPhone simulator
# (1320 x 2868). Run `../run.sh sim` with the same SIMULATOR first so the
# current build is installed.
#
#   SIMULATOR=<udid> AppStore/screenshots.sh
set -euo pipefail
cd "$(dirname "$0")"

sim="${SIMULATOR:?set SIMULATOR to the UDID of an iPhone 17 Pro Max (6.9-inch) simulator}"
bundle=com.eovidiu.cordis.showcase
# simctl cannot write onto some external volumes (TCC); capture to a temp dir
tmp="$(mktemp -d)"
mkdir -p screenshots
rm -f screenshots/*.png

xcrun simctl status_bar "$sim" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi

# name | launch arguments
shots=(
  "01-tour|-tab tour"
  "02-dashboard|-tab dashboard"
  "03-plugins|-tab plugins -tourSteps 1"
  "04-services|-tab services"
  "05-timeline|-tab timeline -tourSteps 1"
  "06-about|-tab tour -showAbout YES"
)
for shot in "${shots[@]}"; do
  name="${shot%%|*}"
  # shellcheck disable=SC2086 # launch arguments are word-split on purpose
  xcrun simctl launch --terminate-running-process "$sim" "$bundle" -resetEntries YES ${shot#*|} >/dev/null
  sleep 5
  xcrun simctl io "$sim" screenshot "$tmp/$name.png" >/dev/null 2>&1
  # App Store Connect rejects screenshots with an alpha channel
  sips -s format jpeg -s formatOptions 100 "$tmp/$name.png" --out "$tmp/$name.jpg" >/dev/null
  sips -s format png "$tmp/$name.jpg" --out "screenshots/$name.png" >/dev/null
  echo "screenshots/$name.png"
done
rm -rf "$tmp"
