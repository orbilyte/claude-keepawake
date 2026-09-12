# Security and safety

## Unsafe lid-closed mode in v0.1.x

Versions v0.1.0–v0.1.2 offered an experimental lid-closed mode based on the undocumented `pmset disablesleep` setting. macOS treated this as a system-wide override even when invoked with `-c`. If power was disconnected while the lid was closed, the Mac could remain awake on battery until it was empty, with an additional heat risk if transported in a bag.

The feature was removed in v0.2.0. Releases v0.1.0–v0.1.2 were withdrawn.

Upgrade to the latest version. If an old installation left the override active, use the menu item **“⚠ Disable unsafe legacy lid mode”** or run:

```bash
sudo pmset -a disablesleep 0
```

Verify the kernel state:

```bash
pmset -g | grep SleepDisabled
ioreg -n IOPMrootDomain -l | grep SleepDisabled
```

Both should report `0` / `No`.

Please report security or safety issues through GitHub's private security advisory feature rather than a public issue.
