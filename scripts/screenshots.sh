#!/bin/bash
# App Store screenshots (6.9", 1320x2868) of the real app, signed in as the
# App Review sample account. Needs a DEBUG simulator build in build/sim and
# APP_REVIEW_EMAIL / APP_REVIEW_PASSWORD in .env.   scripts/screenshots.sh <out-dir> <sim-udid>
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; U=${2:?simulator udid}
mkdir -p "$OUT"
BUNDLE=$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER: //p' project.yml | head -1)
APP=$(ls -d build/sim/Build/Products/Debug-iphonesimulator/*.app | head -1)
PW=$(grep '^APP_REVIEW_PASSWORD=' "${ENV_FILE:-.env}" | cut -d= -f2)
xcrun simctl boot "$U" 2>/dev/null || true
xcrun simctl bootstatus "$U" -b >/dev/null
xcrun simctl ui "$U" appearance light
xcrun simctl status_bar "$U" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$U" "$APP"
shot() {  # name, then KEY=VALUE env pairs
  local name=$1; shift
  xcrun simctl terminate "$U" "$BUNDLE" 2>/dev/null || true
  env "$@" xcrun simctl launch "$U" "$BUNDLE" >/dev/null
  sleep "${WAIT:-10}"
  xcrun simctl io "$U" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "$name"
}
EMAIL=$(grep '^APP_REVIEW_EMAIL=' "${ENV_FILE:-.env}" | cut -d= -f2)
SIGN="SIMCTL_CHILD_UITEST_SIGNIN=$EMAIL|$PW"
shot 01-classes "$SIGN" SIMCTL_CHILD_START_TAB=0
shot 02-trainer-class "$SIGN" SIMCTL_CHILD_OPEN_RUN_ID=900005
shot 03-sign "$SIGN" SIMCTL_CHILD_OPEN_RUN_ID=900005 SIMCTL_CHILD_OPEN_SIGN=1
shot 04-class-detail "$SIGN" SIMCTL_CHILD_OPEN_RUN_ID=900001
shot 05-feedback "$SIGN" SIMCTL_CHILD_OPEN_RUN_ID=900001 SIMCTL_CHILD_OPEN_SURVEY=1
shot 06-calendar "$SIGN" SIMCTL_CHILD_START_TAB=1
shot 07-profile "$SIGN" SIMCTL_CHILD_START_TAB=4 SIMCTL_CHILD_OPEN_PROFILE=1
shot 08-certificates "$SIGN" SIMCTL_CHILD_START_TAB=2
shot 09-support "$SIGN" SIMCTL_CHILD_START_TAB=3
# Signed out: clear the saved session first.
xcrun simctl terminate "$U" "$BUNDLE" 2>/dev/null || true
xcrun simctl keychain "$U" reset
shot 10-sign-in SIMCTL_CHILD_START_TAB=0
