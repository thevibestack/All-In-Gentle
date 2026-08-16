#!/usr/bin/env bash
set -euo pipefail

# Env-overridable build configuration (defaults for local/ad-hoc use)
VERSION="${ALL_IN_GENTLE_VERSION:-1.0.0}"
BUILD_NUMBER="${ALL_IN_GENTLE_BUILD_NUMBER:-1}"
BUNDLE_ID="${ALL_IN_GENTLE_BUNDLE_ID:-com.allin.gentle}"
SIGN_IDENTITY="${ALL_IN_GENTLE_SIGN_IDENTITY:--}"
SKIP_SIGN="${ALL_IN_GENTLE_SKIP_SIGN:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build"
APP_NAME="All-In-Gentle"
EXECUTABLE_NAME="AllInGentle"

# Resolve the package root regardless of invocation cwd (SPM needs the package dir)
cd "${PROJECT_DIR}"

# Gate: the suite must stay green before packaging a release
echo "🧪 Running tests..."
swift test

# Build the release executable
echo "🛠️  Building release executable..."
swift build -c release

# Locate the built executable
EXECUTABLE_PATH="${BUILD_DIR}/release/${EXECUTABLE_NAME}"
if [ ! -f "${EXECUTABLE_PATH}" ]; then
    echo "❌ Executable not found at ${EXECUTABLE_PATH}"
    exit 1
fi

# Prepare .app bundle structure
APP_BUNDLE="${BUILD_DIR}/release/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "📦 Creating .app bundle at ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy executable
cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
chmod +x "${MACOS_DIR}/${EXECUTABLE_NAME}"

# Copy Resources directory if it exists
if [ -d "${PROJECT_DIR}/Resources" ]; then
    cp -R "${PROJECT_DIR}/Resources/" "${RESOURCES_DIR}/"
fi

# Write Info.plist
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Write PkgInfo
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Sign the bundle — loud: failures are fatal under set -e
if [ "${SKIP_SIGN}" = "1" ]; then
    echo "⚠️  Skipping code signing (ALL_IN_GENTLE_SKIP_SIGN=1)"
else
    echo "🔏 Signing ${APP_NAME}.app with identity '${SIGN_IDENTITY}'..."
    codesign --force --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
fi

echo "✅ ${APP_NAME}.app ready at:"
echo "   ${APP_BUNDLE}"
echo ""
echo "To run: open \"${APP_BUNDLE}\""
