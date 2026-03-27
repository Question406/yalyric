#!/bin/bash
set -euo pipefail

APP_NAME="yalyric"
BUNDLE_DIR="dist/${APP_NAME}.app"
CONTENTS="${BUNDLE_DIR}/Contents"
VERSION="${1:-0.1.0}"

echo "Building ${APP_NAME} v${VERSION} release binary..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf dist
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"

# Copy binary
cp ".build/release/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"

# Copy app icon
if [ -f "Resources/yalyric.icns" ]; then
    cp "Resources/yalyric.icns" "${CONTENTS}/Resources/AppIcon.icns"
    echo "App icon included."
fi

# Create Info.plist
cat > "${CONTENTS}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>yalyric</string>
    <key>CFBundleIdentifier</key>
    <string>com.yalyric.app</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>yalyric needs access to Spotify and Apple Music to read the currently playing track and sync lyrics.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Creating zip for distribution..."
cd dist
zip -r -y "${APP_NAME}-v${VERSION}-macos.zip" "${APP_NAME}.app"
cd ..

echo ""
echo "Done!"
echo "  App bundle: ${BUNDLE_DIR}"
echo "  Release zip: dist/${APP_NAME}-v${VERSION}-macos.zip"
echo ""
echo "To install: unzip and drag yalyric.app to /Applications"
