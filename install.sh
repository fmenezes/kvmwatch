#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.filipe.kvmwatch"
BIN_DIR="${BIN_DIR:-$HOME/bin}"
AGENT_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONFIG_DIR="$HOME/.config/kvmwatch"
CONFIG_FILE="$CONFIG_DIR/config.json"
LOG_FILE="$HOME/Library/Logs/kvmwatch.log"
UID_NUM="$(id -u)"

echo "==> building release"
swift build -c release --package-path "$REPO_DIR"
BIN_SRC="$(swift build -c release --package-path "$REPO_DIR" --show-bin-path)/kvmwatch"

echo "==> installing binary -> $BIN_DIR/kvmwatch"
mkdir -p "$BIN_DIR"
cp "$BIN_SRC" "$BIN_DIR/kvmwatch"

echo "==> config"
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
    cp "$REPO_DIR/config.example.json" "$CONFIG_FILE"
    echo "    wrote default $CONFIG_FILE"
else
    echo "    keeping existing $CONFIG_FILE"
fi

echo "==> launch agent"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
sed -e "s|__LABEL__|$LABEL|g" \
    -e "s|__BIN__|$BIN_DIR/kvmwatch|g" \
    -e "s|__CONFIG__|$CONFIG_FILE|g" \
    -e "s|__LOG__|$LOG_FILE|g" \
    "$REPO_DIR/Resources/com.filipe.kvmwatch.plist.template" > "$AGENT_PLIST"

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$AGENT_PLIST"
launchctl kickstart -k "gui/$UID_NUM/$LABEL" 2>/dev/null || true

echo "==> installed."
echo "    binary : $BIN_DIR/kvmwatch"
echo "    config : $CONFIG_FILE"
echo "    log    : $LOG_FILE"
echo "    status : kvmwatch --status"
