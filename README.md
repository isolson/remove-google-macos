# Remove Google from macOS

Safely remove **all** Google software from your Mac — not just Chrome, but everything Google installs: the hidden background updater that phones home every hour, apps, cached data, preferences, and system-level services. All of it.

## Download

**[Click here to download](https://github.com/isolson/remove-google-macos/archive/refs/heads/main.zip)** — this saves a `.zip` file to your Downloads folder. Then:

1. Open your **Downloads** folder and double-click `remove-google-macos-main.zip` to unzip it
2. Open the `remove-google-macos-main` folder
3. Double-click **`Remove Google.command`**
4. If macOS says it can't be opened because it's from an unidentified developer: go to **System Settings > Privacy & Security**, scroll down, and click **Open Anyway**
5. The script scans your Mac and shows you what it found, then gives you a menu

## How it works

When you run the script, it:

1. **Scans your Mac** and shows you everything Google it finds
2. **Gives you a menu:**

```
1) Remove   — remove Google software (asks about each app)
2) Dry run  — preview what would happen (no changes)
3) Restore  — put previously removed items back from Trash
4) Quit
```

If you choose **Remove**, it:

- Stops all running Google processes and background services
- **Asks you about each Google app individually** — you can keep some and remove others
- Removes Google's system directories, caches, preferences, and support files
- Installs a blocker to prevent Google's updater from reinstalling itself

If you choose **Dry run**, it shows everything it would do without actually changing anything.

If you choose **Restore**, it scans your Trash for previously removed Google items and puts them back.

## What it removes

This removes **all Google software**, not just Chrome.

### Applications (you choose which ones)

The script asks about each app individually — you can keep some and remove others:

- **Google Chrome** — web browser
- **Google Earth Pro** — desktop mapping/satellite app
- **Google Drive** — cloud file sync app

If an app isn't installed, it's simply skipped.

### Background services (removed automatically)

These run silently even after you delete Chrome:

- **Google Updater (Keystone)** — a hidden service that runs every hour, checks for updates, and sends hardware info to Google
- **LaunchAgents and LaunchDaemons** — the system configs that tell macOS to start Google services on login and on a timer

### Data and support files (removed automatically)

- **System directories** — `/Library/Google/` and `/Library/Application Support/Google/`
- **Caches** — `~/Library/Caches/com.google.*`
- **Preferences** — `~/Library/Preferences/com.google.*`
- **HTTP storage** — `~/Library/HTTPStorages/com.google.*`
- **WebKit data** — `~/Library/WebKit/com.google.*`
- **Saved state** — `~/Library/Saved Application State/com.google.*`
- **Containers** — `~/Library/Containers/com.google.*`
- **Log files** — `~/Library/Logs/GoogleSoftwareUpdateAgent.log`

## Is it safe?

Yes:

- **Nothing is permanently deleted** — everything is moved to your Trash
- **You choose which apps to remove** — the script asks about each one individually
- **Scans first** — always shows you what it found before doing anything
- **Dry run mode** — preview every action without making any changes
- **Built-in restore** — run the script again and choose Restore to put everything back from Trash

A **reboot** after running is recommended.
