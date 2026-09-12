#!/bin/bash
set -euo pipefail

PURGE="${1:-}"

UID_N=$(id -u)
APP_DIR="$HOME/Applications/Claude KeepAwake.app"
AGENT_BIN="$HOME/.local/bin/claude-keepawake-agent"
AGENT_PLIST="$HOME/Library/LaunchAgents/com.claude-keepawake.agent.plist"
MENU_PLIST="$HOME/Library/LaunchAgents/com.claude-keepawake.menu.plist"
LOG_DIR="$HOME/.local/state/claude-keepawake"
STATE_DOMAIN="com.claude-keepawake.menu"

launchctl bootout "gui/$UID_N/com.claude-keepawake.agent" 2>/dev/null || true
launchctl bootout "gui/$UID_N/com.claude-keepawake.menu" 2>/dev/null || true
pkill -x ClaudeKeepAwake 2>/dev/null || true

rm -f "$AGENT_PLIST" "$MENU_PLIST" "$AGENT_BIN"
rm -rf "$APP_DIR"
defaults delete "$STATE_DOMAIN" 2>/dev/null || true

if [ "$PURGE" = "--purge" ]; then
  rm -rf "$LOG_DIR" "$HOME/.config/claude-keepawake"
  echo "Claude KeepAwake removed (including logs and config)."
else
  echo "Claude KeepAwake removed (logs kept at $LOG_DIR, use --purge to delete)."
fi

pmset -g 2>/dev/null | grep -Eq 'SleepDisabled[[:space:]]+1' && echo "WARNING: unsafe legacy SleepDisabled=1 is still active. Run: sudo pmset -a disablesleep 0" || true
