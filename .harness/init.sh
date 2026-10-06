#!/usr/bin/env bash
# Harness stages for cordis-ios. Usage: init.sh <smoke_test|focused_test <F00N>|full_test>
set -euo pipefail
cd "$(dirname "$0")/.."

filter_for() {
  case "$1" in
    F001) echo 'Effect|Fiber' ;;
    F002) echo 'Reflect|Isolate|Service|Plugin' ;;
    F003) echo 'Events' ;;
    F004) echo 'Logger' ;;
    F005) echo 'Macro' ;;
    F006) echo 'Loader' ;;
    F007) echo 'Demo' ;;
    *) echo "unknown feature: $1" >&2; exit 2 ;;
  esac
}

case "${1:-}" in
  smoke_test) swift build --build-tests ;;
  focused_test)
    filter="$(filter_for "${2:-}")"
    swift test --filter "$filter" ;;
  full_test) swift test ;;
  *) echo "unknown stage: ${1:-}" >&2; exit 2 ;;
esac
