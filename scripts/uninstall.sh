#!/usr/bin/env bash
# Stops WheelSmith, removes the LaunchAgent and the app. Keeps ~/.config/wheelsmith (delete it yourself if you want).
set -euo pipefail

LABEL="dev.wheelsmith.app"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x WheelSmith 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/WheelSmith.app"
defaults delete "$LABEL" 2>/dev/null || true
echo "✓ WheelSmith removed. Your config is still at ~/.config/wheelsmith/config.json"
