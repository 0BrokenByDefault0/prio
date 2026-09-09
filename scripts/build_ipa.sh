#!/usr/bin/env bash
#
# Build Sigil as an UNSIGNED .ipa.
#
# Requires macOS with Xcode 15+ (iOS 17 SDK) and xcodegen:
#     brew install xcodegen
#
# Then, from the repo root:
#     ./scripts/build_ipa.sh
#
# Output: build/Sigil-unsigned.ipa
#
# An unsigned .ipa will NOT install on a stock iPhone. Install it with a
# signing tool that applies your own certificate — Sideloadly, AltStore, or
# `ideviceinstaller` after re-signing — or on a jailbroken device.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT/Sigil"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/Sigil.xcarchive"

command -v xcodebuild >/dev/null || { echo "error: xcodebuild not found (macOS + Xcode required)"; exit 1; }

if [ ! -d "$PROJECT_DIR/Sigil.xcodeproj" ]; then
  command -v xcodegen >/dev/null || { echo "error: xcodegen not found — run: brew install xcodegen"; exit 1; }
  ( cd "$PROJECT_DIR" && xcodegen generate )
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild archive \
  -project "$PROJECT_DIR/Sigil.xcodeproj" \
  -scheme Sigil \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS=""

# An .ipa is just a zip with the app inside Payload/. Because the archive is
# unsigned, `xcodebuild -exportArchive` would refuse it — so we assemble it.
STAGE="$BUILD_DIR/stage"
mkdir -p "$STAGE/Payload"
cp -R "$ARCHIVE/Products/Applications/Sigil.app" "$STAGE/Payload/"

# Strip anything the App Store would have added and we don't want in an
# unsigned artefact.
rm -rf "$STAGE/Payload/Sigil.app/_CodeSignature"

( cd "$STAGE" && zip -qry "$BUILD_DIR/Sigil-unsigned.ipa" Payload )
rm -rf "$STAGE"

echo
echo "built: $BUILD_DIR/Sigil-unsigned.ipa"
ls -lh "$BUILD_DIR/Sigil-unsigned.ipa"
