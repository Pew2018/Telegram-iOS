#!/usr/bin/env bash
# Verify a produced Swiftgram.app is genuinely a Mac Catalyst app bundle.
# Usage: bash tools/verify-mac-catalyst-app.sh path/to/Swiftgram.app
set -euo pipefail

app="${1:?Usage: bash tools/verify-mac-catalyst-app.sh /path/to/Swiftgram.app}"
plist="$app/Contents/Info.plist"
if [[ ! -f "$plist" ]]; then
  echo "ERROR: not a macOS .app bundle (missing Contents/Info.plist): $app" >&2
  exit 1
fi

exe_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
exe="$app/Contents/MacOS/$exe_name"
if [[ ! -x "$exe" ]]; then
  echo "ERROR: missing executable: $exe" >&2
  exit 1
fi

# Mach-O LC_BUILD_VERSION identifies Mac Catalyst separately from ordinary
# macOS and iOS. An .ipa extracted or renamed to .app must not pass.
build_info="$(xcrun vtool -show-build "$exe")"
printf '%s\n' "$build_info"
if ! printf '%s\n' "$build_info" | grep -Eiq 'platform[[:space:]]+(MACCATALYST|6)([[:space:]]|$)'; then
  echo "ERROR: executable is not built for Mac Catalyst (macabi)" >&2
  exit 1
fi

requires_ios="$(/usr/libexec/PlistBuddy -c 'Print :LSRequiresIPhoneOS' "$plist" 2>/dev/null || true)"
if [[ "$requires_ios" == "true" ]]; then
  echo "ERROR: iOS-only LSRequiresIPhoneOS flag is present" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app"
echo "OK: valid signed macOS .app bundle with a Mac Catalyst executable."
