#!/bin/bash
# =============================================================================
# build.sh — Builds the "Remove Google.app" macOS application
#
# Usage:
#   bash build.sh                              # Build the app
#   bash build.sh --sign "Developer ID..."     # Build and sign
# =============================================================================

set -euo pipefail

APP_NAME="Remove Google"
BUNDLE_ID="com.isolson.remove-google"
VERSION="1.0"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

SIGNING_IDENTITY=""
if [ "${1:-}" = "--sign" ] && [ -n "${2:-}" ]; then
    SIGNING_IDENTITY="$2"
fi

echo "Building $APP_NAME.app..."

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Compile Swift
echo "  Compiling Swift..."
xcrun swiftc app/RemoveGoogle.swift \
    -framework Cocoa \
    -framework SwiftUI \
    -o "$BUILD_DIR/$APP_NAME"

# Generate app icon
echo "  Generating icon..."
xcrun swiftc app/generate-icon.swift \
    -framework AppKit \
    -o "$BUILD_DIR/generate-icon"
"$BUILD_DIR/generate-icon" "$BUILD_DIR/icon_1024.png"

mkdir -p "$BUILD_DIR/AppIcon.iconset"
for sz in 16 32 128 256 512; do
    sips -z $sz $sz "$BUILD_DIR/icon_1024.png" --out "$BUILD_DIR/AppIcon.iconset/icon_${sz}x${sz}.png" > /dev/null 2>&1
    sz2=$((sz * 2))
    sips -z $sz2 $sz2 "$BUILD_DIR/icon_1024.png" --out "$BUILD_DIR/AppIcon.iconset/icon_${sz}x${sz}@2x.png" > /dev/null 2>&1
done
cp "$BUILD_DIR/icon_1024.png" "$BUILD_DIR/AppIcon.iconset/icon_512x512@2x.png"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns" 2>/dev/null

# Create .app bundle structure
echo "  Assembling app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

mv "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [ -f "$BUILD_DIR/AppIcon.icns" ]; then
    cp "$BUILD_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Remove Google needs permission to run system commands for removing Google software.</string>
</dict>
</plist>
PLIST

# Sign if identity provided
if [ -n "$SIGNING_IDENTITY" ]; then
    echo "  Signing with: $SIGNING_IDENTITY"
    codesign --force --deep --timestamp --options runtime \
        --sign "$SIGNING_IDENTITY" \
        "$APP_BUNDLE"
    echo "  Verifying signature..."
    codesign --verify --deep --strict "$APP_BUNDLE"
fi

echo ""
echo "Built: $APP_BUNDLE"
echo ""
echo "To run:  open \"$APP_BUNDLE\""
echo ""
if [ -z "$SIGNING_IDENTITY" ]; then
    echo "To sign: bash build.sh --sign \"Developer ID Application: Your Name (TEAM_ID)\""
    echo ""
    echo "To notarize after signing:"
    echo "  ditto -c -k --sequesterRsrc --keepParent \"$APP_BUNDLE\" app.zip"
    echo "  xcrun notarytool submit app.zip --keychain-profile \"profile\" --wait"
    echo "  xcrun stapler staple \"$APP_BUNDLE\""
fi
