#!/bin/bash
set -euo pipefail

APP_NAME="ClaudeCodeStats"
BUILD_DIR=".build"
APP_BUNDLE="$APP_NAME.app"
BUNDLE_ID="com.claudecodestats.app"

echo "=== Building $APP_NAME ==="

# Build the Swift package
swift build -c release

# Create .app bundle
echo "=== Creating app bundle ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeCodeStats</string>
    <key>CFBundleIdentifier</key>
    <string>com.claudecodestats.app</string>
    <key>CFBundleName</key>
    <string>Claude Code Stats</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Code Stats</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "=== Build complete ==="
echo "App bundle created at: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "To install: cp -r $APP_BUNDLE /Applications/"
