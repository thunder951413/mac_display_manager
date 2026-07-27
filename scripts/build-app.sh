#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
cd "$ROOT_DIR"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swift build -c release

APP_DIR="$ROOT_DIR/dist/LumaFlow.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/release/LumaFlow" "$APP_DIR/Contents/MacOS/LumaFlow"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

ICONSET="$ROOT_DIR/.build/LumaFlow.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for SPEC in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"; do
    SIZE=${SPEC%% *}
    NAME=${SPEC#* }
    sips -z "$SIZE" "$SIZE" "$ROOT_DIR/Resources/AppIcon.png" \
      --out "$ICONSET/$NAME" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

SIGNING_IDENTITY=${LUMAFLOW_SIGNING_IDENTITY:-$(
  security find-identity -v -p codesigning 2>/dev/null |
    awk -F'"' '/Developer ID Application|Apple Development/ { print $2; exit }'
)}
if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --deep --options runtime --timestamp=none \
    --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
  echo "warning: no signing identity found; using ad-hoc signature" >&2
  codesign --force --deep --sign - "$APP_DIR"
fi
echo "$APP_DIR"
