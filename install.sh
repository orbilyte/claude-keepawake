#!/bin/bash
set -euo pipefail

REPO="${KEEPAWAKE_REPO:-orbilyte/claude-keepawake}"
VERSION="${KEEPAWAKE_VERSION:-latest}"
LOCAL="${KEEPAWAKE_LOCAL:-0}"

APP_NAME="Claude KeepAwake"
APP_DIR="$HOME/Applications/$APP_NAME.app"
AGENT_BIN="$HOME/.local/bin/claude-keepawake-agent"
AGENT_PLIST="$HOME/Library/LaunchAgents/com.claude-keepawake.agent.plist"
MENU_PLIST="$HOME/Library/LaunchAgents/com.claude-keepawake.menu.plist"
LOG_DIR="$HOME/.local/state/claude-keepawake"
UID_N=$(id -u)

fail() { echo "ERROR: $*" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "macOS required"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ "$LOCAL" = "1" ]; then
  [ -f "$(pwd)/dist/claude-keepawake.tar.gz" ] || fail "dist/claude-keepawake.tar.gz missing - run scripts/build-release.sh first"
  cp "$(pwd)/dist/claude-keepawake.tar.gz" "$TMP/"
else
  if [ "$VERSION" = "latest" ]; then
    URL="https://github.com/$REPO/releases/latest/download/claude-keepawake.tar.gz"
  else
    URL="https://github.com/$REPO/releases/download/$VERSION/claude-keepawake.tar.gz"
  fi
  echo "Downloading $URL ..."
  curl -fsSL "$URL" -o "$TMP/claude-keepawake.tar.gz" || fail "download failed (version exists?)"
fi

tar -xzf "$TMP/claude-keepawake.tar.gz" -C "$TMP"
[ -d "$TMP/$APP_NAME.app" ] || fail "invalid archive"
[ -f "$TMP/claude-keepawake-agent" ] || fail "invalid archive (agent missing)"

mkdir -p "$HOME/Applications" "$HOME/.local/bin" "$LOG_DIR"

pkill -x ClaudeKeepAwake 2>/dev/null || true
sleep 1

rm -rf "$APP_DIR"
cp -R "$TMP/$APP_NAME.app" "$APP_DIR"

cp "$TMP/claude-keepawake-agent" "$AGENT_BIN"
chmod +x "$AGENT_BIN"

cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.claude-keepawake.agent</string>
    <key>ProgramArguments</key><array><string>$AGENT_BIN</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Background</string>
    <key>StandardOutPath</key><string>$LOG_DIR/agent.log</string>
    <key>StandardErrorPath</key><string>$LOG_DIR/agent.log</string>
</dict>
</plist>
PLIST

cat > "$MENU_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.claude-keepawake.menu</string>
    <key>ProgramArguments</key><array><string>$APP_DIR/Contents/MacOS/ClaudeKeepAwake</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>
PLIST

bootout_and_wait() {
  launchctl bootout "gui/$UID_N/$1" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    launchctl print "gui/$UID_N/$1" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
}

bootstrap_with_retry() {
  local plist="$1" attempt
  for attempt in 1 2 3; do
    launchctl bootstrap "gui/$UID_N" "$plist" 2>/dev/null && return 0
    sleep 1
  done
  launchctl bootstrap "gui/$UID_N" "$plist"
}

bootout_and_wait "com.claude-keepawake.agent"
bootout_and_wait "com.claude-keepawake.menu"
bootstrap_with_retry "$AGENT_PLIST"
bootstrap_with_retry "$MENU_PLIST"
launchctl enable "gui/$UID_N/com.claude-keepawake.menu" 2>/dev/null || true

sleep 2

if ! pgrep -x ClaudeKeepAwake >/dev/null; then
  open "$APP_DIR"
fi

echo
echo "Claude KeepAwake installed successfully."
echo
echo "  Menu bar:  $APP_DIR (starts at login)"
echo "  Agent:     $AGENT_BIN (auto-starts, KeepAlive)"
echo "  Log:       $LOG_DIR/agent.log"
echo
echo "Look for the coffee cup icon in your menu bar."
if pmset -g 2>/dev/null | grep -Eq 'SleepDisabled[[:space:]]+1'; then
  echo
  echo "WARNING: unsafe legacy SleepDisabled=1 is active."
  echo "Open the coffee menu and click '⚠ Disable unsafe legacy lid mode'."
  echo "Until cleared, a closed MacBook can stay awake and drain its battery."
fi
