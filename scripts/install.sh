#!/usr/bin/env bash
# Builds WheelSmith, installs it to ~/Applications, and registers a LaunchAgent so it starts at login
# and is restarted if it ever crashes. Re-run any time to upgrade. No sudo needed.
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="dev.wheelsmith.app"
DEST="$HOME/Applications/WheelSmith.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

./scripts/build.sh

echo "→ Stopping any running WheelSmith"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
pkill -x WheelSmith 2>/dev/null || true

echo "→ Installing to $DEST"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R build/WheelSmith.app "$DEST"

echo "→ Registering LaunchAgent $PLIST"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/WheelSmith</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Interactive</string>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF

launchctl bootstrap "$DOMAIN" "$PLIST"
# The app also auto-enables launch-at-login on first run; mark it as done so it doesn't re-write the file.
defaults write "$LABEL" didOfferLaunchAtLogin -bool true

echo "✓ WheelSmith is running. Hold ⌥ Space anywhere."
echo "  Config: ~/.config/wheelsmith/config.json   Menu bar: ◎"
