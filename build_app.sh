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

# Stamp the version (YYMMDD.HHmm, 24h) with the actual build time, so every
# build — not just git commits — carries an accurate timestamp.
PLIST="Sources/SoundShade/Resources/Info.plist"
NEW_VERSION=$(date +"%y%m%d.%H%M")
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_VERSION}" "$PLIST"
echo "🔖 Version stamped: ${NEW_VERSION}"

echo "📦 Creating .app bundle..."

# Clean old bundle / stray top-level copy from older builds
rm -rf "${APP_BUNDLE}" "${APP_NAME}.app"
mkdir -p "${OUT_DIR}"

# Create bundle structure
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "${BUILD_DIR}/${SCHEME}" "${APP_BUNDLE}/Contents/MacOS/${SCHEME}"

# Strip any rpath that points outside the system (e.g. the Xcode toolchain on an
# external volume). dyld probing such a path at launch triggers macOS "removable
# volume" access prompts. The Swift runtime resolves from /usr/lib/swift anyway.
EXEC="${APP_BUNDLE}/Contents/MacOS/${SCHEME}"
otool -l "$EXEC" | awk '/LC_RPATH/{f=1} f&&/path /{print $2; f=0}' | while read -r rp; do
    case "$rp" in
        /usr/lib/swift|@loader_path|@executable_path*) : ;;  # keep system rpaths
        *) install_name_tool -delete_rpath "$rp" "$EXEC" 2>/dev/null \
              && echo "  ✓ removed external rpath: $rp" ;;
    esac
done

# Copy Info.plist
cp "Sources/SoundShade/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Copy AppIcon.icns to Contents/Resources
cp "Sources/SoundShade/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# Copy resource bundle (contains m1ddc, SVGs, driver) into Contents/Resources
# (standard, sealed location). The app loads it via Bundle.appResources, which
# resolves from Contents/Resources — NOT via SwiftPM's Bundle.module, whose
# generated accessor hardcodes an absolute build path on this external volume and
# would make the shipped app reach for the removable drive at runtime.
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
