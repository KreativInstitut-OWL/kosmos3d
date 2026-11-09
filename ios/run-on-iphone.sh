#!/usr/bin/env bash
# Builds KOSMOS 3D and installs it on a connected iPhone (macOS only).
#   bash ios/run-on-iphone.sh          free Apple ID
#   bash ios/run-on-iphone.sh --paid   paid developer account (keeps Hotspot)
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo; echo "STOP: $1"; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "this script only runs on a Mac."
command -v flutter >/dev/null || fail "Flutter is missing: https://docs.flutter.dev/get-started/install/macos"
command -v xcodebuild >/dev/null || fail "Xcode is missing: install it from the App Store and open it once."
command -v pod >/dev/null || fail "CocoaPods is missing. Run: brew install cocoapods"

echo "== Fetching packages"
flutter pub get
(cd ios && pod install)

if ! grep -q 'DEVELOPMENT_TEAM = [A-Z0-9]' ios/Runner.xcodeproj/project.pbxproj; then
  open ios/Runner.xcworkspace
  fail "no signing team yet. In Xcode: Runner > Signing & Capabilities > Team > your Apple ID. Then run this script again."
fi

device=$(flutter devices --machine | python3 -c '
import json, sys
phones = [d for d in json.load(sys.stdin)
          if d["targetPlatform"] == "ios" and not d.get("emulator")]
print(phones[0]["id"] if phones else "")
')
[ -n "$device" ] || fail "no iPhone found. Plug it in, unlock it, tap Trust, and turn on Settings > Privacy & Security > Developer Mode."

entitlements=ios/Runner/Runner.entitlements
if [ "${1:-}" != "--paid" ]; then
  # Free Apple IDs cannot sign the Hotspot capability; restored on exit.
  cp "$entitlements" "$entitlements.orig"
  trap 'mv "$entitlements.orig" "$entitlements"' EXIT
  cat > "$entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST
fi

defines=()
if [ -f config/dev.local.json ]; then
  defines=(--dart-define-from-file=config/dev.local.json)
else
  echo "Note: config/dev.local.json not found, building without cloud credentials."
fi

echo "== Building and installing"
flutter run --release -d "$device" ${defines[@]+"${defines[@]}"}
