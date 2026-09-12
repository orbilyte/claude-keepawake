#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

STATE_DIR="$HOME/.local/state/claude-keepawake"
LOG_FILE="$STATE_DIR/agent.log"
CONF_FILE="$HOME/.config/claude-keepawake/agent.conf"

CHECK_INTERVAL=5
PORTS=(3101 3102)
PATTERNS=("claude-code" "/Applications/Claude.app")

if [ -f "$CONF_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONF_FILE"
fi

CHILD=""
LAST_MODE=""
LAST_POWER=""

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"; }

shutdown() {
  [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null
  log "claude-keepawake stopped"
  exit 0
}
trap shutdown TERM INT

find_target_pid() {
  local pid pattern port
  pid=$(pgrep -o -x claude 2>/dev/null)
  if [ -n "$pid" ]; then echo "$pid"; return 0; fi
  for pattern in "${PATTERNS[@]}"; do
    pid=$(pgrep -o -f "$pattern" 2>/dev/null)
    if [ -n "$pid" ]; then echo "$pid"; return 0; fi
  done
  for port in "${PORTS[@]}"; do
    pid=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | sort -n | sed -n '1p')
    if [ -n "$pid" ]; then echo "$pid"; return 0; fi
  done
  return 1
}

lid_state() {
  if ioreg -r -k AppleClamshellState -d 4 2>/dev/null | grep -q 'AppleClamshellState" = Yes'; then
    echo "closed"
  else
    echo "open"
  fi
}

sleep_disabled() {
  pmset -g 2>/dev/null | awk '/SleepDisabled|disablesleep/ {on = ($NF == "1")} END {print (on ? "1" : "0")}'
}

mkdir -p "$STATE_DIR"
log "claude-keepawake agent started (power-source diagnostics active)"
if [ "$(sleep_disabled)" = "1" ]; then
  log "WARNING: unsafe legacy SleepDisabled=1 detected - disable it from the menu"
fi

TICK=0
while true; do
  TICK=$((TICK + 1))

  POWER=$(pmset -g batt 2>/dev/null | grep -q "AC Power" && echo "AC" || echo "BATT")
  if [ "$POWER" != "$LAST_POWER" ]; then
    if [ -n "$LAST_POWER" ]; then
      DISABLED=$(sleep_disabled)
      LID=$(lid_state)
      log "power source changed: $LAST_POWER -> $POWER (SleepDisabled=$DISABLED, lid=$LID)"
      if [ "$POWER" = "BATT" ] && [ "$DISABLED" = "1" ]; then
        log "CRITICAL: unsafe SleepDisabled=1 active on battery"
      fi
    fi
    LAST_POWER="$POWER"
  fi

  if [ -n "$CHILD" ] && ! kill -0 "$CHILD" 2>/dev/null; then
    log "target exited, stay-awake stopped"
    CHILD=""
    LAST_MODE=""
  fi

  if [ -z "$CHILD" ] && [ $((TICK % 3)) -eq 1 ]; then
    pid=$(find_target_pid)
    if [ -n "$pid" ]; then
      if [ "$LAST_MODE" != "auto:$pid" ]; then
        log "keeping Mac awake (auto, PID $pid)"
        LAST_MODE="auto:$pid"
      fi
      caffeinate -s -w "$pid" &
      CHILD=$!
    elif [ -z "$LAST_MODE" ]; then
      log "idle"
      LAST_MODE="idle"
    fi
  fi

  sleep "$CHECK_INTERVAL" &
  wait $!
done
