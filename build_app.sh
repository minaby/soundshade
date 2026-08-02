#!/bin/bash
# build_app.sh — Build SoundShade.app bundle from Swift Package
#
# Flags:
#   --sign       Sign with the Developer ID Application cert in Keychain
#                (falls back to ad-hoc if none found). Signs nested binaries
#                (m1ddc, ProxyAudioDevice.driver) with hardened runtime +
#                timestamp BEFORE the outer bundle — required order for
#                notarization; `codesign --deep` alone does not reliably
#                reach a bare CLI binary or a driver .bundle sitting inside
#                a plain resource bundle.
#   --notarize   Implies --sign. Submits to Apple's notary service via
#                notarytool using the keychain profile in $NOTARY_PROFILE
#                (default: gau-notary — same Developer ID/team, reused
#                across projects) and staples the ticket on success.

SIGN=0
NOTARIZE=0
NOTARY_PROFILE="${NOTARY_PROFILE:-gau-notary}"
DEVELOPER_ID_APPLICATION="Developer ID Application: Chau Hoang Hieu Lam (73CVFDQ653)"
for arg in "$@"; do
    case "$arg" in
        --sign) SIGN=1 ;;
        --notarize) SIGN=1; NOTARIZE=1 ;;
    esac
done

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

if [ "$SIGN" -eq 1 ]; then
    IDENTITY="-"  # ad-hoc fallback
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEVELOPER_ID_APPLICATION"; then
        IDENTITY="$DEVELOPER_ID_APPLICATION"
        echo "🔏 Signing with Developer ID (${IDENTITY})..."
    else
        echo "⚠️  No Developer ID Application cert found — falling back to ad-hoc signing."
        echo "    (Ad-hoc builds cannot be notarized.)"
    fi

    SIGN_OPTS=(--force --options runtime --timestamp -s "$IDENTITY")
    # Sign nested binaries first (inside-out) — notarization requires every
    # Mach-O in the bundle to individually carry hardened runtime + a secure
    # timestamp, and `codesign --deep` on the outer bundle alone does not
    # reliably reach these two (a bare CLI binary and a driver .bundle, both
    # sitting inside a plain resource bundle rather than a standard
    # Frameworks/PlugIns location codesign auto-discovers).
    M1DDC="${APP_BUNDLE}/Contents/Resources/SoundShade_SoundShade.bundle/m1ddc"
    DRIVER="${APP_BUNDLE}/Contents/Resources/SoundShade_SoundShade.bundle/ProxyAudioDevice.driver"
    [ -f "$M1DDC" ] && codesign "${SIGN_OPTS[@]}" "$M1DDC"
    [ -d "$DRIVER" ] && codesign "${SIGN_OPTS[@]}" "$DRIVER"
    codesign "${SIGN_OPTS[@]}" "${APP_BUNDLE}"

    codesign --verify --deep --strict "${APP_BUNDLE}"
    echo "  ✓ Signed and verified"
fi

if [ "$NOTARIZE" -eq 1 ]; then
    if [ "$IDENTITY" = "-" ]; then
        echo "❌ Cannot notarize an ad-hoc-signed build — need a Developer ID cert." >&2
        exit 1
    fi
    echo "📤 Submitting for notarization (profile: ${NOTARY_PROFILE})..."
    ZIP_PATH=$(mktemp -t SoundShade-notarize).zip
    ditto -c -k --keepParent "${APP_BUNDLE}" "$ZIP_PATH"
    if xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait; then
        xcrun stapler staple "${APP_BUNDLE}"
        spctl -a -vvv -t install "${APP_BUNDLE}"
        echo "  ✓ Notarized and stapled"
    else
        echo "❌ Notarization failed. If the profile is missing, create it with:" >&2
        echo "    xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" --apple-id ... --team-id 73CVFDQ653 --password ..." >&2
        rm -f "$ZIP_PATH"
        exit 1
    fi
    rm -f "$ZIP_PATH"
fi

echo ""
echo "✅ Done! Created: ${APP_BUNDLE}"
echo ""
echo "   Install/run from /Applications (recommended — avoids external-volume prompts):"
echo "   rm -rf /Applications/${APP_NAME}.app && cp -R ${APP_BUNDLE} /Applications/ && open /Applications/${APP_NAME}.app"
