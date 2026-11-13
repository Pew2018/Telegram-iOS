#!/usr/bin/env bash
# Attempt a real build of the existing Swiftgram app for Mac Catalyst.
# This does NOT create or substitute a placeholder application.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${RUNNER_TEMP:-/tmp}/swiftgram-catalyst"
mkdir -p "$OUT"
CONFIG="$OUT/build-configuration.json"
PROJECT="$ROOT/Telegram/Swiftgram.xcodeproj"
BUILD_LOG="$OUT/xcodebuild.log"
GEN_LOG="$OUT/generate-project.log"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Expected an Apple Silicon runner" >&2
  exit 1
fi

# Compile-only can use placeholder API values. For a usable Telegram client,
# actual API credentials must be provided via GitHub Actions secrets.
python3 - "$CONFIG" <<'PY'
import json, os, sys
api_id = os.environ.get("TELEGRAM_API_ID", "").strip()
api_hash = os.environ.get("TELEGRAM_API_HASH", "").strip()
has_real_credentials = bool(api_id and api_hash)
if has_real_credentials and (not api_id.isdecimal() or len(api_hash) != 32 or any(c not in '0123456789abcdefABCDEF' for c in api_hash)):
    raise SystemExit("Invalid TELEGRAM_API_ID or TELEGRAM_API_HASH secret")
configuration = {
    "bundle_id": "app.pew2018.swiftgram.catalyst",
    "api_id": api_id if has_real_credentials else "100000",
    "api_hash": api_hash if has_real_credentials else "00000000000000000000000000000000",
    "team_id": "XXXXXXXXXX",
    "is_internal_build": "true",
    "is_appstore_build": "false",
    "appstore_id": "0",
    "app_specific_url_scheme": "tg",
    "premium_iap_product_id": "",
    "enable_siri": False,
    "enable_icloud": False,
    "sg_config": "",
}
with open(sys.argv[1], "w") as f:
    json.dump(configuration, f)
print("BUILD_CREDENTIAL_STATUS=" + ("provided" if has_real_credentials else "missing (build-only)"))
PY

echo "::group::Generate real Swiftgram Bazel/Xcode project"
set +e
python3 -u build-system/Make/Make.py \
    --cacheDir="$OUT/bazel-cache" \
    generateProject \
    --configurationPath="$CONFIG" \
    --xcodeManagedCodesigning \
    --disableExtensions \
    --disableProvisioningProfiles \
    --projectIncludeRelease \
    > >(tee "$GEN_LOG") 2>&1
status=$?
set -e
echo "::endgroup::"
if [[ $status -ne 0 ]]; then
  echo "::error::Swiftgram Xcode project generation failed (exit=$status). See log artifact."
  exit "$status"
fi
if [[ ! -f "$PROJECT/project.pbxproj" ]]; then
  echo "::error::Missing generated Swiftgram Xcode project at $PROJECT"
  find "$ROOT/Telegram" -maxdepth 3 -name project.pbxproj -print || true
  exit 1
fi

echo "::group::Inspect real generated Swiftgram project"
xcodebuild -list -project "$PROJECT"
echo "::endgroup::"

echo "::group::Try full Swiftgram Mac Catalyst build"
set +e
xcodebuild \
  -project "$PROJECT" \
  -scheme Swiftgram \
  -configuration Debug \
  -destination "generic/platform=macOS,variant=Mac Catalyst" \
  -derivedDataPath "$OUT/DerivedData" \
  -resultBundlePath "$OUT/SwiftgramBuild.xcresult" \
  SUPPORTS_MACCATALYST=YES \
  SUPPORTED_PLATFORMS="iphoneos iphonesimulator macosx" \
  CODE_SIGNING_ALLOWED=NO \
  build \
  > >(tee "$BUILD_LOG") 2>&1
status=$?
set -e
echo "::endgroup::"
if [[ $status -ne 0 ]]; then
  echo "::error::Full Swiftgram Mac Catalyst build failed (exit=$status). See xcodebuild.log artifact."
  exit "$status"
fi

echo "::group::Find and authenticate real output (no fake/renamed IPA)"
apps=()
while IFS= read -r app; do apps+=("$app"); done < <(find "$OUT/DerivedData/Build/Products" -name Swiftgram.app -type d -print)
if [[ ${#apps[@]} -eq 0 ]]; then
  echo "::error::Xcode completed without generating Swiftgram.app"
  exit 1
fi
found=0
for app in "${apps[@]}"; do
  if [[ -f "$app/Contents/Info.plist" ]] && [[ -d "$app/Contents/MacOS" ]]; then
    found=1
    codesign --force --deep --sign - "$app"
    bash tools/verify-mac-catalyst-app.sh "$app"
    rm -rf "$ROOT/build/mac-catalyst"
    mkdir -p "$ROOT/build/mac-catalyst"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$ROOT/build/mac-catalyst/Swiftgram-Mac-Catalyst-arm64.zip"
    echo "REAL_SWIFTGRAM_APP_ARCHIVE=$ROOT/build/mac-catalyst/Swiftgram-Mac-Catalyst-arm64.zip"
    break
  fi
done
if [[ $found -eq 0 ]]; then
  echo "::error::Only iOS-style .app layout found; this is not a real macOS app."
  exit 1
fi
echo "::endgroup::"
