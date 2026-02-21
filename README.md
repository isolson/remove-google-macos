# Remove Google from macOS

Safely remove **all** Google software from your Mac — not just Chrome, but everything Google installs: the hidden background updater that phones home every hour, Google Earth Pro, Google Drive, cached data, preferences, and system-level services. All of it.

## Download

**[Click here to download](https://github.com/isolson/remove-google-macos/archive/refs/heads/main.zip)** — this saves a `.zip` file to your Downloads folder. Then:

1. Open your **Downloads** folder and double-click `remove-google-macos-main.zip` to unzip it
2. Open the `remove-google-macos-main` folder
3. Double-click **`Remove Google.command`**
4. If macOS says it can't be opened because it's from an unidentified developer: go to **System Settings > Privacy & Security**, scroll down, and click **Open Anyway**
5. Terminal opens with a simple menu — start with option **1 (Audit)** to see what's on your system before removing anything

## What it removes

This removes **all Google software**, not just Chrome. Specifically:

- **Google Chrome** — the browser app itself
- **Google Earth Pro** — the desktop mapping app
- **Google Drive** — the cloud sync app
- **Google Updater / Keystone** — the hidden background service that runs every hour, even if you've already deleted Chrome
- **Launch services** — the system configs that tell macOS to start Google software automatically
- **System directories** — Google's folders in your system Library
- **User data** — caches, preferences, saved state, and cookies stored under your account
- **Installs a blocker** — prevents Google's updater from silently reinstalling itself

If a particular Google app isn't installed on your Mac, the script simply skips it.

## Is it safe?

Yes. The script is designed to be cautious:

- **Nothing is permanently deleted** — everything is moved to your Trash, so you can recover it
- **Scans first** — always shows you what it found before doing anything
- **Asks permission** — confirms with you before each step
- **Dry run mode** — lets you preview every action without making any changes
- **Included restore script** — puts everything back from Trash if you change your mind

## Quick start

### Option 1: Double-click (recommended)

Double-click **`Remove Google.command`** in Finder. Terminal opens with a menu:

```
1) Audit   - Scan and report (no changes)
2) Dry Run - Preview all changes
3) Remove  - Remove all Google software
4) Quit
```

Start with **1** to see what Google software is on your Mac. When you're ready, use **3** to remove it.

### Option 2: Command line

```bash
# See what Google software is on your system
bash remove-google.sh audit

# Preview what would be removed (no changes)
bash remove-google.sh dryrun

# Remove everything (confirms each phase)
bash remove-google.sh all
```

## Restoring

Changed your mind? As long as you haven't emptied the Trash:

Double-click **`Restore Google.command`** in Finder, or run:

```bash
bash restore-google.sh scan    # See what can be restored
bash restore-google.sh all     # Put it all back
```

## How it works

The script runs in 5 phases, in this order:

1. **Kill processes** — stops any running Google software
2. **Unload services** — stops the hourly updater and removes its system configs
3. **Trash apps** — moves Google apps from `/Applications/` to Trash
4. **Trash user data** — moves caches, preferences, and support files to Trash
5. **Block reinstall** — prevents Google's updater from reinstalling itself

A **reboot** after running is recommended.
