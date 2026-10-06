#!/usr/bin/env bash
# Harness stages for cordis-ios. Usage: init.sh <smoke_test|focused_test <F00N>|full_test>
set -euo pipefail
cd "$(dirname "$0")/.."

SHOWCASE=Examples/CordisShowcase/ShowcaseKit

filter_for() {
  case "$1" in
    F001) echo 'Effect|Fiber' ;;
    F002) echo 'Reflect|Isolate|Service|Plugin' ;;
    F003) echo 'Events' ;;
    F004) echo 'Logger' ;;
    F005) echo 'Macro' ;;
    F006) echo 'Loader' ;;
    F007) echo 'Demo' ;;
    F008|F009) echo '' ;;
    *) echo "unknown feature: $1" >&2; exit 2 ;;
  esac
}

case "${1:-}" in
  smoke_test)
    swift build --build-tests
    swift build --build-tests --package-path "$SHOWCASE" ;;
  focused_test)
    feature="${2:-}"
    filter="$(filter_for "$feature")"
    case "$feature" in
      F008)
        swift test --package-path "$SHOWCASE"
        # compile the SwiftUI app too; XCUITests stay behind run.sh uitest
        (cd Examples/CordisShowcase && xcodegen generate --quiet && xcodebuild \
          -project CordisShowcase.xcodeproj -scheme CordisShowcase \
          -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
          -skipMacroValidation -quiet build) ;;
      F009) docs/check.sh ;;
      *) swift test --filter "$filter" ;;
    esac ;;
  full_test)
    swift test
    swift test --package-path "$SHOWCASE"
    if [ -x docs/check.sh ]; then docs/check.sh; fi ;;
  *) echo "unknown stage: ${1:-}" >&2; exit 2 ;;
esac
