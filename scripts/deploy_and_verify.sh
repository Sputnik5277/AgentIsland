#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

EXEC_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" Resources/Info.plist)"
TARGET_APP="/Users/l/Applications/AgentIsland.app"
SRC_BIN="${REPO_DIR}/AgentIsland.app/Contents/MacOS/${EXEC_NAME}"
DST_BIN="${TARGET_APP}/Contents/MacOS/${EXEC_NAME}"

./build.sh

pkill -x "$EXEC_NAME" 2>/dev/null || true
sleep 1
rm -rf /tmp/AgentIsland.app.deploy && cp -Rp "${REPO_DIR}/AgentIsland.app" /tmp/AgentIsland.app.deploy
ditto /tmp/AgentIsland.app.deploy "$TARGET_APP"
rm -rf /tmp/AgentIsland.app.deploy
open "$TARGET_APP"
sleep 2

# T1 read-back verification: running process + binary SHA256 parity
NEW_PID="$(pgrep -x "$EXEC_NAME" | head -n 1 || true)"
SRC_SHA="$(shasum -a 256 "$SRC_BIN" | awk '{print $1}')"
DST_SHA="$(shasum -a 256 "$DST_BIN" | awk '{print $1}')"

if [ -z "$NEW_PID" ] || [ "$SRC_SHA" != "$DST_SHA" ]; then
  echo "DEPLOY_T1=FAIL pid=${NEW_PID:-none} src=${SRC_SHA:0:12} dst=${DST_SHA:0:12}"
  exit 1
fi
echo "DEPLOY_T1=PASS exec=${EXEC_NAME} pid=${NEW_PID} sha256=${DST_SHA:0:12}"
