#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios/App"
BUILD_DIR="$ROOT_DIR/ios-build"
ARCHIVE_PATH="$BUILD_DIR/App.xcarchive"
PAYLOAD_DIR="$BUILD_DIR/Payload"
IPA_PATH="$BUILD_DIR/Pingy-unsigned.ipa"

echo "==> Building web assets"
cd "$ROOT_DIR"
npm run build
npx cap sync ios

echo "==> Archiving iOS app (unsigned)"
mkdir -p "$BUILD_DIR"
cd "$IOS_DIR"
xcodebuild \
  -project App.xcodeproj \
  -scheme App \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  clean archive

echo "==> Packaging unsigned IPA"
rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/App.app" "$PAYLOAD_DIR/"
cd "$BUILD_DIR"
rm -f "$IPA_PATH"
zip -qr "$IPA_PATH" Payload

echo "Done: $IPA_PATH"
echo "You can sign/install this unsigned IPA using Sideloadly or AltStore."
