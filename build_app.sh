#!/bin/bash
# build_app.sh — Build SoundShade.app bundle from Swift Package

set -e

SCHEME="SoundShade"
BUILD_DIR=".build/release"
APP_NAME="SoundShade"
APP_BUNDLE="${APP_NAME}.app"

echo "🔨 Building ${APP_NAME} (release)..."
swift build -c release 2>&1

echo "📦 Creating .app bundle..."

# Clean old bundle
rm -rf "${APP_BUNDLE}"

# Create bundle structure
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "${BUILD_DIR}/${SCHEME}" "${APP_BUNDLE}/Contents/MacOS/${SCHEME}"

# Copy Info.plist
cp "Sources/SoundShade/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Copy AppIcon.icns to Contents/Resources
cp "Sources/SoundShade/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# Copy resource bundle (contains m1ddc)
RESOURCE_BUNDLE=$(find .build -name "SoundShade_SoundShade.bundle" 2>/dev/null | head -1)
if [ -n "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "${APP_BUNDLE}/Contents/Resources/"
    echo "  ✓ Bundled resources: $(basename $RESOURCE_BUNDLE)"
fi

# Make m1ddc executable
chmod +x "${APP_BUNDLE}/Contents/Resources/SoundShade_SoundShade.bundle/m1ddc" 2>/dev/null || true

echo ""
echo "✅ Done! Created: ${APP_BUNDLE}"
echo "   Run with: open ${APP_BUNDLE}"
echo ""
echo "   To install: cp -R ${APP_BUNDLE} /Applications/"
