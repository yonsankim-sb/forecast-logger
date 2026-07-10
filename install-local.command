#!/bin/bash
# Build Forecast Logger from source and install it to /Applications on THIS Mac.
#
# Because the app is built locally (never downloaded), it has no
# com.apple.quarantine flag, so it launches normally — no `xattr`, no Gatekeeper
# prompt, no Install.command dance. That's only needed by teammates who RECEIVE
# the DMG. Run this whenever you want the latest build installed.
#
# Data (token in Keychain, logged hours) survives reinstalls because the bundle
# id stays com.forecastlogger.ForecastLogger.
set -euo pipefail
cd "$(dirname "$0")"

# Persistent DerivedData outside the repo → fast incremental builds, no git noise.
DD="$HOME/Library/Developer/Xcode/DerivedData/ForecastLogger-local"
APP_NAME="Forecast Logger.app"

echo "▸ Building $APP_NAME (Release)…"
xcodebuild build \
  -project MacTimeTracker.xcodeproj \
  -scheme MacTimeTracker \
  -configuration Release \
  -derivedDataPath "$DD" \
  -quiet

APP="$DD/Build/Products/Release/$APP_NAME"
[ -d "$APP" ] || { echo "✗ Build product not found at $APP"; exit 1; }

echo "▸ Installing to /Applications…"
pkill -f "Forecast Logger" 2>/dev/null || true
sleep 1
rm -rf "/Applications/$APP_NAME"
cp -R "$APP" "/Applications/"

echo "▸ Launching…"
open "/Applications/$APP_NAME"
echo "✓ Done — running from /Applications (no de-quarantine needed)."
