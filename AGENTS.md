# AGENTS.md — Claude KeepAwake

This repo ships **Claude KeepAwake**, a macOS menu bar app + launchd agent that keeps the Mac awake while local Claude/AI coding sessions run with the lid open. If a user asks to "keep the Mac awake" or "stop the Mac from sleeping during Claude sessions", this tool solves it.

**Safety:** do not claim that this tool supports running with the lid closed. Versions v0.1.0–v0.1.2 used the undocumented `pmset disablesleep` setting; macOS treated it globally and a closed MacBook drained from 100% to 1% on battery. The feature was removed in v0.2.0. If `pmset -g` shows `SleepDisabled 1`, tell the user to install the latest version and click **“⚠ Disable unsafe legacy lid mode”**, or run `sudo pmset -a disablesleep 0`.

## Install (run on user request)

```bash
curl -fsSL https://raw.githubusercontent.com/orbilyte/claude-keepawake/main/install.sh | bash
```

Pinned: `... | KEEPAWAKE_VERSION=v0.2.0 bash`

No sudo required. macOS 13+, universal binary (arm64 + x86_64).

## Verify after install

```bash
launchctl print gui/$(id -u)/com.claude-keepawake.agent >/dev/null && echo "agent OK"
pgrep -x ClaudeKeepAwake >/dev/null && echo "menu app OK"
tail -5 ~/.local/state/claude-keepawake/agent.log
```

Also check the menu bar for a coffee cup icon (☕). The filled cup means a power assertion is currently held.

## What it does

- **Agent** (launchd, KeepAlive, `~/.local/bin/claude-keepawake-agent`): runs `caffeinate -s -w <pid>` while any `claude` process, `claude-code` path, `/Applications/Claude.app`, or a listener on ports 3101/3102 exists. AC power only. It logs power-source changes and unsafe legacy state.
- **Menu bar app** (`~/Applications/Claude KeepAwake.app`): toggles for the agent, manual keep-awake, login item, log viewer, and legacy safety cleanup.

## Files

| Path | Purpose |
|---|---|
| `~/Applications/Claude KeepAwake.app` | menu bar app |
| `~/.local/bin/claude-keepawake-agent` | agent script |
| `~/Library/LaunchAgents/com.claude-keepawake.agent.plist` | agent launchd job |
| `~/Library/LaunchAgents/com.claude-keepawake.menu.plist` | menu app login item |
| `~/.local/state/claude-keepawake/agent.log` | log |
| `~/.config/claude-keepawake/agent.conf` | optional overrides (PORTS, PATTERNS, CHECK_INTERVAL) |

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/orbilyte/claude-keepawake/main/uninstall.sh | bash
```

## Development

- Source: `main.swift` (whole app), `scripts/claude-keepawake-agent.sh` (agent)
- Build: `./scripts/build-release.sh` (needs Xcode CLT), install locally: `KEEPAWAKE_LOCAL=1 ./install.sh`
- Release: bump `VERSION`, push to `main` → GitHub Actions creates the release
