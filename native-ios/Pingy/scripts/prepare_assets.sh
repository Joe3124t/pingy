#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ICON="$ROOT_DIR/Resources/pingy-icon-source.png"
APPICON_DIR="$ROOT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
LAUNCH_DIR="$ROOT_DIR/Resources/Assets.xcassets/LaunchLogo.imageset"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Source icon not found: $SOURCE_ICON"
  exit 1
fi

mkdir -p "$APPICON_DIR" "$LAUNCH_DIR"

generate_size() {
  local size="$1"
  local output="$2"
  sips -z "$size" "$size" "$SOURCE_ICON" --out "$output" >/dev/null
}

generate_size 20 "$APPICON_DIR/Icon-20.png"
generate_size 29 "$APPICON_DIR/Icon-29.png"
generate_size 40 "$APPICON_DIR/Icon-40.png"
generate_size 58 "$APPICON_DIR/Icon-58.png"
generate_size 60 "$APPICON_DIR/Icon-60.png"
generate_size 76 "$APPICON_DIR/Icon-76.png"
generate_size 80 "$APPICON_DIR/Icon-80.png"
generate_size 87 "$APPICON_DIR/Icon-87.png"
generate_size 120 "$APPICON_DIR/Icon-120.png"
generate_size 152 "$APPICON_DIR/Icon-152.png"
generate_size 167 "$APPICON_DIR/Icon-167.png"
generate_size 180 "$APPICON_DIR/Icon-180.png"
generate_size 1024 "$APPICON_DIR/Icon-1024.png"

cat >"$APPICON_DIR/Contents.json" <<'JSON'
{
  "images" : [
    { "size" : "20x20", "idiom" : "iphone", "filename" : "Icon-40.png", "scale" : "2x" },
    { "size" : "20x20", "idiom" : "iphone", "filename" : "Icon-60.png", "scale" : "3x" },
    { "size" : "29x29", "idiom" : "iphone", "filename" : "Icon-58.png", "scale" : "2x" },
    { "size" : "29x29", "idiom" : "iphone", "filename" : "Icon-87.png", "scale" : "3x" },
    { "size" : "40x40", "idiom" : "iphone", "filename" : "Icon-80.png", "scale" : "2x" },
    { "size" : "40x40", "idiom" : "iphone", "filename" : "Icon-120.png", "scale" : "3x" },
    { "size" : "60x60", "idiom" : "iphone", "filename" : "Icon-120.png", "scale" : "2x" },
    { "size" : "60x60", "idiom" : "iphone", "filename" : "Icon-180.png", "scale" : "3x" },
    { "size" : "20x20", "idiom" : "ipad", "filename" : "Icon-20.png", "scale" : "1x" },
    { "size" : "20x20", "idiom" : "ipad", "filename" : "Icon-40.png", "scale" : "2x" },
    { "size" : "29x29", "idiom" : "ipad", "filename" : "Icon-29.png", "scale" : "1x" },
    { "size" : "29x29", "idiom" : "ipad", "filename" : "Icon-58.png", "scale" : "2x" },
    { "size" : "40x40", "idiom" : "ipad", "filename" : "Icon-40.png", "scale" : "1x" },
    { "size" : "40x40", "idiom" : "ipad", "filename" : "Icon-80.png", "scale" : "2x" },
    { "size" : "76x76", "idiom" : "ipad", "filename" : "Icon-76.png", "scale" : "1x" },
    { "size" : "76x76", "idiom" : "ipad", "filename" : "Icon-152.png", "scale" : "2x" },
    { "size" : "83.5x83.5", "idiom" : "ipad", "filename" : "Icon-167.png", "scale" : "2x" },
    { "size" : "1024x1024", "idiom" : "ios-marketing", "filename" : "Icon-1024.png", "scale" : "1x" }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
JSON

generate_size 512 "$LAUNCH_DIR/launch-logo.png"
cat >"$LAUNCH_DIR/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "universal", "filename" : "launch-logo.png", "scale" : "1x" },
    { "idiom" : "universal", "filename" : "launch-logo.png", "scale" : "2x" },
    { "idiom" : "universal", "filename" : "launch-logo.png", "scale" : "3x" }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
JSON

echo "Assets prepared successfully."
