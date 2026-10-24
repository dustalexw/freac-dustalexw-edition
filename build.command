#!/bin/bash
# Builds "freac (dustalexw edition).app" into ./build and opens it.
# Double-click in Finder, or run ./build.command in Terminal.
#   ./build.command            native architecture
#   ./build.command universal  arm64 + x86_64 (needs full Xcode)
#   ./build.command install    build, then copy to /Applications
# Set FREAC_NO_LAUNCH=1 to skip opening the app afterwards.
cd "$(dirname "$0")" || exit 1

APP_NAME="freac (dustalexw edition)"
EXEC="FreacEdition"
BUNDLE_ID="com.dustalexw.freac-edition"
VERSION="$(tr -d ' \n' < VERSION)"
LOG="build.log"
exec > >(tee "$LOG") 2>&1
echo "=== $APP_NAME $VERSION — $(date)"

ARCH_FLAGS=()
[[ "${1:-}" == "universal" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

echo "▸ Compiling (release)…"
if ! swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}; then
  echo "✗ BUILD FAILED — details above."
  exit 1
fi
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/${APP_NAME}.app"
echo "▸ Bundling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXEC" "$APP/Contents/MacOS/$EXEC"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleExecutable</key><string>${EXEC}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signing"
codesign --force --deep --sign - "$APP"

if [[ "${1:-}" == "install" ]]; then
  echo "▸ Installing to /Applications"
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$APP" /Applications/
  APP="/Applications/${APP_NAME}.app"
fi

echo "✓ BUILT: $APP"
if [[ "${FREAC_NO_LAUNCH:-0}" != "1" ]]; then open "$APP"; fi
