#!/usr/bin/env bash
# Smoke-check real Swiftgram application entry points for Mac Catalyst.
# This intentionally does NOT claim to build or package Swiftgram.app.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Mac Catalyst compilation requires a macOS Xcode runner" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-ios15.0-macabi"
# UIKit is shipped in the Catalyst iOSSupport overlay, not the ordinary
# macOS framework search path used by a bare swiftc/clang invocation.
CATALYST_FRAMEWORKS="$SDK/System/iOSSupport/System/Library/Frameworks"
if [[ ! -d "$CATALYST_FRAMEWORKS/UIKit.framework" ]]; then
  echo "UIKit.framework missing from Mac Catalyst SDK overlay: $CATALYST_FRAMEWORKS" >&2
  find "$SDK" -maxdepth 9 -name UIKit.framework -print >&2 || true
  exit 1
fi

test -f "$ROOT/Telegram/Telegram-iOS/Application.swift"
test -f "$ROOT/Telegram/Telegram-iOS/main.m"
grep -q 'name = "Swiftgram"' "$ROOT/Telegram/BUILD"

echo "Checking UIKit-based Swiftgram application class for $TARGET"
xcrun --sdk macosx swiftc \
  -target "$TARGET" \
  -sdk "$SDK" \
  -F "$CATALYST_FRAMEWORKS" \
  -typecheck \
  "$ROOT/Telegram/Telegram-iOS/Application.swift"

echo "Checking Swiftgram UIApplicationMain entry point for $TARGET"
xcrun --sdk macosx clang \
  -target "$TARGET" \
  -isysroot "$SDK" \
  -F "$CATALYST_FRAMEWORKS" \
  -fobjc-arc \
  -fsyntax-only \
  "$ROOT/Telegram/Telegram-iOS/main.m"

echo "Mac Catalyst source-entry compatibility probe passed."
echo "Not a full binary/link/app bundle build."
