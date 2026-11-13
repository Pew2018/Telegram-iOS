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

test -f "$ROOT/Telegram/Telegram-iOS/Application.swift"
test -f "$ROOT/Telegram/Telegram-iOS/main.m"
grep -q 'name = "Swiftgram"' "$ROOT/Telegram/BUILD"

echo "Checking UIKit-based Swiftgram application class for $TARGET"
xcrun --sdk macosx swiftc \
  -target "$TARGET" \
  -sdk "$SDK" \
  -typecheck \
  "$ROOT/Telegram/Telegram-iOS/Application.swift"

echo "Checking Swiftgram UIApplicationMain entry point for $TARGET"
xcrun --sdk macosx clang \
  -target "$TARGET" \
  -isysroot "$SDK" \
  -fobjc-arc \
  -fsyntax-only \
  "$ROOT/Telegram/Telegram-iOS/main.m"

echo "Mac Catalyst source-entry compatibility probe passed."
echo "Not a full binary/link/app bundle build."
