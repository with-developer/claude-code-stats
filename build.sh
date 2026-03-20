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

# Copy icon and logo
cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp logo.png "$APP_BUNDLE/Contents/Resources/logo.png"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
    </dict>
</dict>
</plist>
PLIST

# Create entitlements (outside bundle)
cat > "entitlements.plist" << 'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
ENT

# Re-sign with entitlements
codesign --force --sign - --entitlements "entitlements.plist" "$APP_BUNDLE"
rm -f entitlements.plist

# Cache OAuth token from keychain (avoids keychain prompts at runtime)
TOKEN_CACHE="$HOME/.claude/.stats-token-cache"
if [ ! -f "$TOKEN_CACHE" ]; then
    echo "=== Caching OAuth token ==="
    RAW=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
    if [ -n "$RAW" ]; then
        # Extract accessToken from JSON
        TOKEN=$(echo "$RAW" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('claudeAiOauth',{}).get('accessToken',''))" 2>/dev/null || true)
        if [ -n "$TOKEN" ]; then
            echo "$TOKEN" > "$TOKEN_CACHE"
            chmod 600 "$TOKEN_CACHE"
            echo "Token cached to $TOKEN_CACHE"
        fi
    fi
fi

echo "=== Build complete ==="
echo "App bundle created at: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "To install: cp -r $APP_BUNDLE /Applications/"
