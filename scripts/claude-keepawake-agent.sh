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
WAS_CLOSED=""
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

clamshell_closed() {
  ioreg -r -k AppleClamshellState -d 4 2>/dev/null | grep -q 'AppleClamshellState" = Yes'
}

stay_awake_mode() {
  pmset -g 2>/dev/null | awk '/SleepDisabled|disablesleep/ {on = ($NF == "1")} END {print (on ? "1" : "0")}'
}

mkdir -p "$STATE_DIR"
log "claude-keepawake agent started (clamshell watcher active)"

TICK=0
while true; do
  TICK=$((TICK + 1))

  POWER=$(pmset -g batt 2>/dev/null | grep -q "AC Power" && echo "AC" || echo "BATT")
  if [ "$POWER" != "$LAST_POWER" ]; then
    if [ -n "$LAST_POWER" ]; then
      log "power source changed: $LAST_POWER -> $POWER (SleepDisabled=$(stay_awake_mode), lid=$(clamshell_closed && echo closed || echo open))"
    fi
    LAST_POWER="$POWER"
  fi

  if clamshell_closed; then
    if [ -z "$WAS_CLOSED" ]; then
      WAS_CLOSED=1
      if [ "$(stay_awake_mode)" = "1" ]; then
        log "lid closed (clamshell mode active) - display off"
        /usr/bin/pmset displaysleepnow
      else
        log "lid closed (clamshell mode inactive - no display off)"
      fi
    fi
  else
    WAS_CLOSED=""
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
