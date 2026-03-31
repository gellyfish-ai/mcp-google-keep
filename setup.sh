#!/bin/bash
set -euo pipefail

# Setup script for mcp-google-keep
# Run this from the repo root directory.
# Creates venv, installs deps, creates launchd plist, and loads the service.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.gellyfish.mcp-google-keep"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_PATH="$HOME/Library/Logs/mcp-google-keep.log"
CRED_FILE="${CREDENTIALS_FILE:-$HOME/.config/gellyfish/google-keep.env}"
VENV_DIR="${REPO_DIR}/.venv"
PYTHON="${VENV_DIR}/bin/python"

echo "=== mcp-google-keep setup ==="
echo "Repo:        ${REPO_DIR}"
echo "Credentials: ${CRED_FILE}"
echo "Venv:        ${VENV_DIR}"
echo "Plist:       ${PLIST_PATH}"
echo "Log:         ${LOG_PATH}"
echo ""

# Step 1: Check credentials
if [ ! -f "$CRED_FILE" ]; then
    echo "ERROR: Credential file not found at ${CRED_FILE}"
    echo ""
    echo "Create it with:"
    echo "  mkdir -p $(dirname "$CRED_FILE")"
    echo "  cat > ${CRED_FILE} << 'EOF'"
    echo "GOOGLE_EMAIL=your-email@gmail.com"
    echo "MASTER_TOKEN=your-master-token"
    echo "ANDROID_ID=your-hex-id"
    echo "UNSAFE_MODE=true"
    echo "EOF"
    echo "  chmod 600 ${CRED_FILE}"
    echo ""
    echo "See README.md for how to obtain a master token."
    exit 1
fi
echo "[ok] Credential file found"

# Step 2: Create venv and install deps
if [ ! -f "$PYTHON" ]; then
    echo "[..] Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi
echo "[..] Installing dependencies..."
"$VENV_DIR/bin/pip" install --quiet -e "$REPO_DIR"
echo "[ok] Dependencies installed"

# Step 3: Quick sanity check — can we import and load credentials?
echo "[..] Verifying credentials load..."
CREDENTIALS_FILE="$CRED_FILE" "$PYTHON" -c "
import os
os.environ['CREDENTIALS_FILE'] = '$CRED_FILE'
from server.keep_api import get_client
" 2>&1 | head -5
if [ "${PIPESTATUS[0]:-0}" -ne 0 ]; then
    echo "WARNING: Credential verification had issues (check output above)"
    echo "The service may still work — continuing with setup."
fi

# Step 4: Unload existing service if present
if launchctl list "$LABEL" &>/dev/null; then
    echo "[..] Stopping existing service..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

# Step 5: Create launchd plist
echo "[..] Creating launchd plist..."
cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${PYTHON}</string>
        <string>-m</string>
        <string>server</string>
    </array>

    <key>WorkingDirectory</key>
    <string>${REPO_DIR}</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>CREDENTIALS_FILE</key>
        <string>${CRED_FILE}</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${LOG_PATH}</string>

    <key>StandardErrorPath</key>
    <string>${LOG_PATH}</string>
</dict>
</plist>
EOF
echo "[ok] Plist created at ${PLIST_PATH}"

# Step 6: Load the service
echo "[..] Loading service..."
launchctl load "$PLIST_PATH"
sleep 2

# Step 7: Verify
echo "[..] Verifying service is running..."
if curl -s --max-time 3 http://localhost:8204/sse | head -1 | grep -q "event: endpoint"; then
    echo "[ok] Service is running on http://localhost:8204"
else
    echo "ERROR: Service did not start. Check logs:"
    echo "  tail -20 ${LOG_PATH}"
    exit 1
fi

echo ""
echo "=== Setup complete ==="
echo "Service: ${LABEL}"
echo "Port:    8204"
echo "Logs:    tail -f ${LOG_PATH}"
echo ""
echo "To stop:    launchctl unload ${PLIST_PATH}"
echo "To restart: launchctl unload ${PLIST_PATH} && launchctl load ${PLIST_PATH}"
