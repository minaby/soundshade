#!/bin/bash
# build_app.sh — Build SoundShade.app bundle from Swift Package

set -e

SCHEME="SoundShade"
BUILD_DIR=".build/release"
APP_NAME="SoundShade"
# Output into a ".noindex" directory so Spotlight/LaunchServices never auto-register
# this dev build. Registering a copy here (on an external volume) is what made macOS
# prompt for "removable volume" access — the real app lives in /Applications.
OUT_DIR="dist.noindex"
APP_BUNDLE="${OUT_DIR}/${APP_NAME}.app"

echo "🔨 Building ${APP_NAME} (release)..."
swift build -c release 2>&1

echo "📦 Creating .app bundle..."

# Clean old bundle / stray top-level copy from older builds
rm -rf "${APP_BUNDLE}" "${APP_NAME}.app"
mkdir -p "${OUT_DIR}"

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
echo ""
echo "   Install/run from /Applications (recommended — avoids external-volume prompts):"
echo "   rm -rf /Applications/${APP_NAME}.app && cp -R ${APP_BUNDLE} /Applications/ && open /Applications/${APP_NAME}.app"
