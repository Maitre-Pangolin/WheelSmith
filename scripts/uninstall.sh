#!/usr/bin/env bash
# Stops TheOneRing, removes the LaunchAgent and the app. Keeps ~/.config/theonering (delete it yourself if you want).
set -euo pipefail

LABEL="dev.theonering.app"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x TheOneRing 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/TheOneRing.app"
defaults delete "$LABEL" 2>/dev/null || true
echo "✓ The One Ring removed. Your config is still at ~/.config/theonering/config.json"
