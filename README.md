# Claude KeepAwake ☕

A tiny macOS menu bar app that keeps your Mac awake while local Claude sessions, Claude Code, or dev servers are running — so long-running agent sessions survive idle time and usage-limit resets while the lid is open.

No admin rights needed to install. No background phoning home. Just a coffee cup in your menu bar.

## Why

Local AI coding sessions (Claude Code, Claude Desktop, OpenCode, …) run on *your* Mac. When you walk away, macOS puts the machine to sleep after a few minutes of idle time — killing the session mid-task. This tool makes sure that doesn't happen:

- **Automatic:** stays awake only while a Claude session or dev server actually runs (AC power only — battery is never held hostage)
- **Manual:** one click for "stay awake now, unlimited"
- **Safe by default:** it never changes macOS lid-close behavior and never keeps a closed MacBook awake on battery

## Safety notice

Versions v0.1.0–v0.1.2 included an experimental lid-closed mode based on the undocumented `pmset disablesleep` setting. Testing proved that macOS treats this setting globally even when invoked with `-c`: unplugging power with the lid closed kept the Mac awake and could drain the battery completely. The feature was removed in v0.2.0.

If an old version enabled it, install the latest release and use the menu item **“⚠ Disable unsafe legacy lid mode”**, or run:

```bash
sudo pmset -a disablesleep 0
```

## Requirements

- macOS 13 or newer (Apple Silicon or Intel — universal binary)
- No Xcode or command line tools needed for installation

## Install

One-liner (works from a terminal or from an AI coding session):

```bash
curl -fsSL https://raw.githubusercontent.com/orbilyte/claude-keepawake/main/install.sh | bash
```

Install a pinned version instead of latest:

```bash
curl -fsSL https://raw.githubusercontent.com/orbilyte/claude-keepawake/main/install.sh | KEEPAWAKE_VERSION=v0.2.0 bash
```

Then look for the **coffee cup icon ☕ in your menu bar**. It starts automatically at login.

## The menu

| Item | What it does |
|---|---|
| **Automatic – stay awake while Claude / dev servers run** | Background agent (launchd) holds a power assertion while any `claude` process, Claude Desktop, or a dev server on ports 3101/3102 runs. AC only. |
| **Stay awake now (unlimited, AC only)** | Immediate keep-awake until you turn it off or quit the app. |
| **⚠ Disable unsafe legacy lid mode** | Appears only if a v0.1.x installation left `SleepDisabled=1` active. Clears it globally via the standard macOS admin prompt. |
| **Start at login** | Toggles the menu bar app's login item. |

The cup is filled while the Mac is actively being kept awake.

## How it works

- **Menu bar app** (`~/Applications/Claude KeepAwake.app`, Swift, ~350 lines, no dependencies) — UI and toggles
- **Agent** (`~/.local/bin/claude-keepawake-agent`) — a launchd job (`com.claude-keepawake.agent`, KeepAlive) that:
  - watches for Claude processes/dev servers and runs `caffeinate -s -w <pid>` (power assertion on AC power only)
  - logs power-source changes and warns if an unsafe legacy `SleepDisabled=1` state is detected
- Log: `~/.local/state/claude-keepawake/agent.log` (openable from the menu)

Nothing runs as root. The app only requests an admin password if it needs to clear an unsafe legacy sleep override — the app never sees or stores your password.

## Configuration (optional)

Create `~/.config/claude-keepawake/agent.conf` to override defaults:

```bash
CHECK_INTERVAL=5
PORTS=(3101 3102 3000 8080)
PATTERNS=("claude-code" "/Applications/Claude.app" "opencode")
```

Changes apply on next agent restart (toggle "Automatic" off and on in the menu, or `launchctl kickstart -k gui/$(id -u)/com.claude-keepawake.agent`).

## Install from source / development

```bash
git clone https://github.com/orbilyte/claude-keepawake.git
cd claude-keepawake
./scripts/build-release.sh          # builds dist/claude-keepawake.tar.gz (needs Xcode CLT)
KEEPAWAKE_LOCAL=1 ./install.sh      # installs the local build
```

## Releases

Pushing to `main` with a bumped `VERSION` file builds and publishes a new GitHub release (universal binary) automatically via GitHub Actions. Old versions stay pinned and installable.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/orbilyte/claude-keepawake/main/uninstall.sh | bash
```

Add `--purge` to also delete logs and config. If an unsafe legacy sleep override is still active, the uninstaller tells you how to clear it.

## Notes

- macOS 26 dims third-party menu bar icons on the inactive display — the cup is rendered non-template white so it stays visible
- If you ever remove the cup from the menu bar by accident (⌘-drag out), it comes back on the next app start
- ⌘-drag to move the icon; its position persists

## License

[MIT](LICENSE)
