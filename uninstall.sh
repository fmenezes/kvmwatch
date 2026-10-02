#!/usr/bin/env bash
set -euo pipefail

LABEL="com.filipe.kvmwatch"
BIN_DIR="${BIN_DIR:-$HOME/bin}"
AGENT_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

echo "==> stopping launch agent"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true

echo "==> removing files"
rm -f "$AGENT_PLIST"
rm -f "$BIN_DIR/kvmwatch"

echo "==> done (config and log left in place)."
echo "    config: $HOME/.config/kvmwatch/config.json"
echo "    log   : $HOME/Library/Logs/kvmwatch.log"
