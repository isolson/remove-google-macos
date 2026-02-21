# Remove Google from macOS

Safely remove all Google software from your Mac, including the persistent Keystone auto-updater that runs every hour in the background even after you've stopped using Chrome.

## What it removes

- **Google Updater / Keystone** - the hourly background service (`com.google.GoogleUpdater.wake`)
- **LaunchAgents & LaunchDaemons** - all `com.google.*` plists in `/Library/` and `~/Library/`
- **Google applications** - Chrome, Earth Pro, Drive (if present in `/Applications/`)
- **System directories** - `/Library/Google/`, `/Library/Application Support/Google/`
- **User data** - caches, preferences, HTTP storage, WebKit data under `~/Library/`
- **Creates a blocker** - prevents Keystone from silently reinstalling itself

## Safety

- **Moves to Trash** - nothing is permanently deleted; everything goes to `~/.Trash/`
- **Audit first** - always scans and reports before taking action
- **Dry run mode** - preview all changes without touching anything
- **Phase-by-phase confirmation** - asks "yes/no" before each destructive step
- **Explicit paths only** - no broad filesystem searches; only known Google locations
- **Unloads before removing** - properly stops services via `launchctl` before moving plists
- **Fully reversible** - included restore script puts everything back from Trash

## Quick start

### Option 1: Double-click

Double-click **`Remove Google.command`** in Finder. It opens Terminal with a menu to audit, dry run, or remove.

### Option 2: Command line

```bash
# See what Google software is on your system
bash remove-google.sh audit

# Preview what would be removed (no changes)
bash remove-google.sh dryrun

# Remove everything (confirms each phase)
bash remove-google.sh all
```

### Individual phases

```bash
bash remove-google.sh phase1   # Kill running Google processes
bash remove-google.sh phase2   # Unload + trash LaunchAgents/Daemons
bash remove-google.sh phase3   # Trash Google apps + /Library/Google
bash remove-google.sh phase4   # Trash user-level caches/prefs/data
bash remove-google.sh phase5   # Anti-reinstall blocker + verification
```

## Restoring

Changed your mind? As long as you haven't emptied the Trash:

```bash
# See what can be restored
bash restore-google.sh scan

# Put it all back
bash restore-google.sh all
```

Or double-click **`Restore Google.command`** in Finder.

## Phase ordering

The phases run in a specific order for a reason:

1. **Kill processes** - stop running Google software so it can't re-register services
2. **Unload + trash plists** - stop the hourly updater and remove its launch configs
3. **Trash apps** - remove the application bundles that plists point to
4. **Trash user data** - clean up caches, preferences, and support files
5. **Block reinstall** - create a `chmod 000` file at `~/Library/Google` so Keystone can't recreate its directory

A **reboot** after running is recommended to clear any lingering launchd state.
