# Remove Google from macOS

Safely remove **all** Google software from your Mac — not just Chrome, but everything Google installs: the hidden background updater that phones home every hour, apps, cached data, preferences, and system-level services. All of it.

## Download

**[Click here to download](https://github.com/isolson/remove-google-macos/archive/refs/heads/main.zip)** — this saves a `.zip` file to your Downloads folder. Then:

1. Open your **Downloads** folder and double-click `remove-google-macos-main.zip` to unzip it
2. Open the `remove-google-macos-main` folder
3. Double-click **`Remove Google.command`**
4. If macOS says it can't be opened because it's from an unidentified developer: go to **System Settings > Privacy & Security**, scroll down, and click **Open Anyway**
5. Terminal opens with a simple menu — start with option **1 (Audit)** to see what's on your system before removing anything

## What it removes

This removes **all Google software**, not just Chrome.

### Applications (you choose which ones)

The script checks for these apps in `/Applications/` and asks about each one individually — you can keep some and remove others:

- **Google Chrome** — web browser
- **Google Earth Pro** — desktop mapping/satellite app
- **Google Drive** — cloud file sync app

If an app isn't installed, it's simply skipped.

### Background services (the hidden stuff)

These run silently even after you delete Chrome:

- **Google Updater (Keystone)** — a hidden service that runs every hour, checks for updates, and sends hardware info to Google. This is usually what people want gone.
- **LaunchAgents and LaunchDaemons** — the system configs in `/Library/LaunchAgents/` and `/Library/LaunchDaemons/` that tell macOS to start Google services on login and on a timer

### Data and support files

- **System directories** — `/Library/Google/` and `/Library/Application Support/Google/`
- **Caches** — `~/Library/Caches/com.google.*`
- **Preferences** — `~/Library/Preferences/com.google.*` (Chrome settings, Earth Pro settings, Keystone config)
- **HTTP storage** — `~/Library/HTTPStorages/com.google.*`
- **WebKit data** — `~/Library/WebKit/com.google.*`
- **Saved state** — `~/Library/Saved Application State/com.google.*`
- **Containers** — `~/Library/Containers/com.google.*`
- **Log files** — `~/Library/Logs/GoogleSoftwareUpdateAgent.log`

### Anti-reinstall blocker

After removal, the script creates a locked file at `~/Library/Google` that prevents Google's updater from silently reinstalling itself.

## Can I keep some things and remove others?

Yes. The script asks about each application individually — for example, you can keep Google Earth Pro but remove everything else. The background services and cached data are handled as separate phases, each with its own confirmation prompt.

You can also run individual phases if you only want to remove specific categories:

```bash
bash remove-google.sh phase1   # Kill running Google processes only
bash remove-google.sh phase2   # Remove background services only
bash remove-google.sh phase3   # Remove applications only (asks per app)
bash remove-google.sh phase4   # Remove caches/prefs/data only
bash remove-google.sh phase5   # Install anti-reinstall blocker only
```

## Is it safe?

Yes. The script is designed to be cautious:

- **Nothing is permanently deleted** — everything is moved to your Trash, so you can recover it
- **Scans first** — always shows you what it found before doing anything
- **Asks permission** — confirms with you before each step, and asks per app
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

# Remove everything (confirms each phase, asks per app)
bash remove-google.sh all
```

## Restoring

Changed your mind? As long as you haven't emptied the Trash, you can put everything back.

Double-click **`Restore Google.command`** in Finder — it has the same menu style:

```
1) Scan    - Show what can be restored from Trash
2) Dry Run - Preview restore without changes
3) Restore - Restore all Google items from Trash
4) Quit
```

Or from the command line:

```bash
bash restore-google.sh scan      # See what can be restored
bash restore-google.sh dryrun    # Preview restore without changes
bash restore-google.sh all       # Put it all back
```

## How it works

The script runs in 5 phases, in this order:

1. **Kill processes** — stops any running Google software
2. **Unload services** — stops the hourly updater and removes its system configs
3. **Trash apps** — asks about each Google app individually, moves selected ones to Trash
4. **Trash user data** — moves caches, preferences, and support files to Trash
5. **Block reinstall** — prevents Google's updater from reinstalling itself

A **reboot** after running is recommended.
