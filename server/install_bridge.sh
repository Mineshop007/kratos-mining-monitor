#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║   Kratos Link — Auto-install & autostart bridge              ║
# ║   Run once: curl -sL https://kratos.mineshop.eu/install.sh | bash -s YOUR_KEY
# ╚══════════════════════════════════════════════════════════════╝

set -e

KEY="$1"
if [ -z "$KEY" ]; then
  echo ""
  echo "Usage: curl -sL https://kratos.mineshop.eu/install.sh | bash -s YOUR_KEY"
  echo "  YOUR_KEY = the access key from Kratos app → Remote Access"
  echo ""
  exit 1
fi

OS="$(uname -s)"
INSTALL_DIR="$HOME/.kratos-link"
SCRIPT="$INSTALL_DIR/kratos_link.py"
RELAY_URL="wss://kratos.mineshop.eu"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║          KRATOS LINK — INSTALLER                 ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  Key:  ${KEY:0:8}…"
echo "  OS:   $OS"
echo ""

# ── Install Python deps ───────────────────────────────────────────────────────

echo "▶ Checking Python…"
if ! command -v python3 &>/dev/null; then
  echo "  ✗ Python3 not found. Install Python 3.8+ then re-run."
  exit 1
fi
echo "  ✓ $(python3 --version)"

echo "▶ Installing aiohttp + websockets…"
python3 -m pip install --quiet --user aiohttp websockets 2>/dev/null || \
  python3 -m pip install --quiet aiohttp websockets 2>/dev/null

# ── Download bridge script ────────────────────────────────────────────────────

mkdir -p "$INSTALL_DIR"
echo "▶ Downloading kratos_link.py…"
curl -fsSL "https://kratos.mineshop.eu/relay/kratos_link.py" -o "$SCRIPT" 2>/dev/null || \
  curl -fsSL "https://mineshop.eu/relay/kratos_link.py" -o "$SCRIPT"
chmod +x "$SCRIPT"
echo "  ✓ Saved to $SCRIPT"

# ── Save config ───────────────────────────────────────────────────────────────

cat > "$INSTALL_DIR/config.env" << EOF
KRATOS_KEY=$KEY
KRATOS_RELAY=$RELAY_URL
EOF
echo "  ✓ Config saved"

# ── Autostart ─────────────────────────────────────────────────────────────────

if [[ "$OS" == "Linux" ]]; then
  # systemd user service (works without root on modern Linux)
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/kratos-link.service" << EOF
[Unit]
Description=Kratos Link — home network bridge
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=python3 $SCRIPT --key $KEY --relay $RELAY_URL
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable kratos-link
  systemctl --user start kratos-link
  echo "  ✓ systemd user service installed and started"
  echo "  ✓ Will auto-start at every login"
  echo ""
  echo "  Status: systemctl --user status kratos-link"
  echo "  Logs:   journalctl --user -u kratos-link -f"

elif [[ "$OS" == "Darwin" ]]; then
  # launchd plist (macOS)
  PLIST="$HOME/Library/LaunchAgents/eu.mineshop.kratos-link.plist"
  cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>eu.mineshop.kratos-link</string>
  <key>ProgramArguments</key>
  <array>
    <string>python3</string>
    <string>$SCRIPT</string>
    <string>--key</string>
    <string>$KEY</string>
    <string>--relay</string>
    <string>$RELAY_URL</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$INSTALL_DIR/kratos-link.log</string>
  <key>StandardErrorPath</key>
  <string>$INSTALL_DIR/kratos-link.log</string>
</dict>
</plist>
EOF
  launchctl load "$PLIST" 2>/dev/null || true
  launchctl start eu.mineshop.kratos-link 2>/dev/null || true
  echo "  ✓ launchd service installed (auto-starts at login)"
  echo ""
  echo "  Logs: tail -f $INSTALL_DIR/kratos-link.log"

else
  # Generic: just run it (Windows/WSL users see instructions)
  echo "  ℹ Windows: run this once and it bridges your miners:"
  echo "    python3 $SCRIPT --key $KEY"
  echo ""
  echo "  For autostart on Windows, run in PowerShell as admin:"
  echo "    \$action = New-ScheduledTaskAction -Execute 'python3' -Argument '$SCRIPT --key $KEY'"
  echo "    \$trigger = New-ScheduledTaskTrigger -AtLogon"
  echo "    Register-ScheduledTask -TaskName 'KratosLink' -Action \$action -Trigger \$trigger -RunLevel Highest"
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ✅  Kratos Link is running!                     ║"
echo "║  Open Kratos app → Remote Access to see miners  ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
