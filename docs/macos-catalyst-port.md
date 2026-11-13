# Swiftgram for macOS (Mac Catalyst) — porting status

## Goal

Produce a real **arm64 Mac Catalyst** `Swiftgram.app` from the existing
Swiftgram iPad application sources, using a GitHub Actions macOS/Xcode runner,
and retain actual account/chat functionality. An extracted or renamed iOS IPA,
an empty shell, and a separate web client do **not** meet the goal.

Development takes place on `feature/mac-catalyst`; the upstream iOS target
must remain buildable. This file describes the **current status**, not a
working Mac app.

## Verified starting-point constraints

- The real app in `Telegram/BUILD` is `ios_application(name = "Swiftgram")`,
  with `families = ["iphone", "ipad"]`, not a Mac Catalyst target.
- `Telegram_xcodeproj` only generates `device` and `simulator` environments.
- The bundled `rules_xcodeproj` generator does not support `catalyst` as a
  `top_level_target` environment. See upstream documentation:
  https://github.com/MobileNativeFoundation/rules_xcodeproj/blob/main/docs/bazel.md
- `build-system/Make/Make.py` supports iOS device/simulator configurations
  only. The existing release workflow emits `Telegram.ipa`, not `.app`.
- Several dependency libraries, media/VoIP native modules, entitlements, and
  iOS app extensions require independent Mac Catalyst compatibility checks.
- The repository's `versions.json` pins Xcode 27.1 / Bazel 9.2.0. A macOS
  host version in that file is **not** a macOS app target.

## Stage 0: real source / SDK compatibility probe

The initial entry-point CI workflow has been retired to avoid misleading green
checks that don't produce a full app. The script `tools/mac-catalyst-probe.sh` type-checks
`Telegram/Telegram-iOS/Application.swift` and checks the Objective-C
`Telegram/Telegram-iOS/main.m` entry point against the **macabi**
(`arm64-apple-ios15.0-macabi`) ABI, without substituting a fake application.
This only checks the application bootstrap, not its transitive dependencies.
A green probe must never be reported as "Swiftgram for macOS built".

Run the source probe locally with Xcode installed:

```sh
bash tools/mac-catalyst-probe.sh
```

## Steps required for a real app

1. Establish a build graph that compiles the existing Swiftgram UIKit app and
   **all transitive Swift/ObjC/C++/Rust dependencies for macabi**. Either
   implement Catalyst support in the existing Bazel/rules_xcodeproj toolchain,
   or generate a separate, reproducible native Xcode Catalyst build graph.
   Do not mix iOS device/simulator binaries into the Catalyst app.
2. Exclude iOS-only extensions and watch targets on Catalyst; replace
   iOS-specific PushKit, CallKit, share, notification and other integration
   points as needed while keeping Telegram messaging functionality intact.
3. Configure a Mac Catalyst app bundle, bundle identifiers and a minimal,
   platform-appropriate sandbox/signing setup. Remove iOS-only Info.plist keys
   from the **Mac output** instead of modifying iOS behavior globally.
4. Build and link a complete arm64 Catalyst `.app` on the `xcode-27` runner.
   Supply **your own** Telegram API ID/hash for any usable client build.
   Keep credentials in GitHub Secrets, never in source or Actions artifacts.
5. Validate the output. The ZIP must contain `Swiftgram.app/Contents/MacOS/*`,
   the executable must have a macOS/Catalyst build platform (not iOS), and
   `codesign --verify` plus an actual launch/login/chat smoke test on an
   Apple Silicon Mac must pass.

### Acceptance checks for a full build (not yet implemented)

The reusable verifier is `tools/verify-mac-catalyst-app.sh`. Run it against
an actual full build (not against the current source-only probe):

```sh
bash tools/verify-mac-catalyst-app.sh Swiftgram.app
```

```sh
test -x Swiftgram.app/Contents/MacOS/Swiftgram
xcrun vtool -show-build Swiftgram.app/Contents/MacOS/Swiftgram
plutil -p Swiftgram.app/Contents/Info.plist
codesign --verify --deep --strict Swiftgram.app
```

The `vtool` output must identify **Mac Catalyst** rather than plain iOS,
and the app must actually open the existing Swiftgram UI. The untrusted
unsigned/unnotarized development build may require local Gatekeeper handling;
a public distribution requires appropriate Apple signing and notarization.

## Stage 1: full application build attempt

`.github/workflows/mac-catalyst-build.yml` (the only active macOS build
workflow) checks out the full repository, generates the actual Swiftgram
Xcode project, attempts the full Mac Catalyst build and uploads diagnostic
logs on failure. It does not publish an app unless the final executable
passes Mac Catalyst platform and signing checks.

An actual, usable client additionally needs a private Telegram application
API ID/hash as `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` secrets.
With no secrets, the workflow uses placeholder API values **only for compile
testing**, which cannot authenticate as a proper client.

The full build is a work in progress; passing the earlier source-entry probe
does **not** mean a runnable Swiftgram macOS app has been produced.

## Current deliverable

Active full-application build workflow, generated artifacts gated on real
macabi binary validation, and a written migration plan. **No verified,
fully functional Swiftgram macOS .app has been confirmed yet.**
