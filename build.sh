#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="AgentIsland"
APP_BUNDLE="${APP_NAME}.app"
OUTPUT_DIR="dist"

echo "==> Running App.swift static hygiene gate..."
python3 scripts/gate_app_hygiene.py

echo "==> Building ${APP_NAME} binary..."
swiftc -O Sources/AgentIsland/App.swift -o "${APP_NAME}Bin"

echo "==> Packaging ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}" "${OUTPUT_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mkdir -p "${OUTPUT_DIR}"

cp "${APP_NAME}Bin" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"
cp Resources/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "==> Creating release archive..."
cp -R "${APP_BUNDLE}" "${OUTPUT_DIR}/"
(cd "${OUTPUT_DIR}" && zip -rq "${APP_NAME}-macOS-arm64.zip" "${APP_BUNDLE}")
shasum -a 256 "${OUTPUT_DIR}/${APP_NAME}-macOS-arm64.zip" > "${OUTPUT_DIR}/${APP_NAME}-macOS-arm64.zip.sha256"

echo "==> Build successful: ${OUTPUT_DIR}/${APP_NAME}-macOS-arm64.zip"
