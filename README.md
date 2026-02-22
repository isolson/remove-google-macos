# Remove Google from macOS

A small native macOS app that safely removes **all** Google software from your Mac — not just Chrome, but everything Google installs: the hidden background updater that phones home every hour, apps, cached data, preferences, and system-level services.

## Download

**[Download Remove Google.app](https://github.com/isolson/remove-google-macos/releases/latest)** from the Releases page.

Or build it yourself:

```bash
git clone https://github.com/isolson/remove-google-macos.git
cd remove-google-macos
bash build.sh
open "build/Remove Google.app"
```

## How it works

When you open the app, it immediately scans your Mac and shows you everything Google it found. Each item has a checkbox:

- **Applications** (Google Chrome, Earth Pro, Drive) — you choose which to keep or remove
- **Background services** — the hourly Google Updater and its launch configs
- **Data & preferences** — caches, preferences, support files under ~/Library

Click **Remove Selected** and you're done. The app asks for your password once (for system-level files), moves everything to Trash, and installs a blocker to prevent Google from reinstalling itself.

Changed your mind? Click **Restore** to put everything back from Trash.

## What it removes

### Applications (you choose which ones)

- **Google Chrome** — web browser
- **Google Earth Pro** — desktop mapping/satellite app
- **Google Drive** — cloud file sync app

### Background services (removed automatically)

- **Google Updater (Keystone)** — a hidden service that runs every hour, checks for updates, and sends hardware info to Google
- **LaunchAgents and LaunchDaemons** — the system configs that tell macOS to start Google services on login and on a timer

### Data and support files (removed automatically)

- System directories (`/Library/Google/`, `/Library/Application Support/Google/`)
- Caches, preferences, HTTP storage, WebKit data, containers, saved state, logs

## Is it safe?

- **Nothing is permanently deleted** — everything is moved to your Trash
- **You choose which apps to remove** — each app has its own checkbox
- **Built-in restore** — click Restore to put everything back from Trash
- **No trace left behind** — the app itself stores nothing; delete it when you're done

A **reboot** after removal is recommended.

## Signing and notarization

If you have an Apple Developer account:

```bash
# Build and sign
bash build.sh --sign "Developer ID Application: Your Name (TEAM_ID)"

# Notarize
ditto -c -k --sequesterRsrc --keepParent "build/Remove Google.app" app.zip
xcrun notarytool submit app.zip --keychain-profile "profile" --wait
xcrun stapler staple "build/Remove Google.app"
```

## Command-line alternative

Prefer the terminal? `remove-google.sh` does the same thing interactively:

```bash
bash remove-google.sh
```
