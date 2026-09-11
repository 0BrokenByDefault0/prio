#!/usr/bin/env bash
#
# Build Palm as an UNSIGNED .ipa. Requires macOS with Xcode 15+ and xcodegen.
#   brew install xcodegen && ./scripts/build_palm_ipa.sh
# Output: build/Palm-unsigned.ipa

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT/Palm"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/Palm.xcarchive"

command -v xcodebuild >/dev/null || { echo "error: xcodebuild not found (macOS + Xcode required)"; exit 1; }

if [ ! -d "$PROJECT_DIR/Palm.xcodeproj" ]; then
  command -v xcodegen >/dev/null || { echo "error: xcodegen not found — brew install xcodegen"; exit 1; }
  ( cd "$PROJECT_DIR" && xcodegen generate )
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild archive \
  -project "$PROJECT_DIR/Palm.xcodeproj" \
  -scheme Palm \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS=""

# `xcodebuild -exportArchive` refuses an unsigned archive, so assemble the
# Payload directory by hand. An .ipa is only ever a zip with this shape.
STAGE="$BUILD_DIR/stage"
mkdir -p "$STAGE/Payload"
cp -R "$ARCHIVE/Products/Applications/Palm.app" "$STAGE/Payload/"
rm -rf "$STAGE/Payload/Palm.app/_CodeSignature"

( cd "$STAGE" && zip -qry "$BUILD_DIR/Palm-unsigned.ipa" Payload )
rm -rf "$STAGE"

echo
echo "built: $BUILD_DIR/Palm-unsigned.ipa"
ls -lh "$BUILD_DIR/Palm-unsigned.ipa"
