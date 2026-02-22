# What Google installs on your Mac

Google software installs far more than what you see in `/Applications`. Here is a comprehensive list of everything that can end up on a Mac.

## Applications

| App | Install path | Status |
|-----|-------------|--------|
| Google Chrome | `/Applications/Google Chrome.app` | Active |
| Chrome Canary | `/Applications/Google Chrome Canary.app` | Active |
| Chrome Beta | `/Applications/Google Chrome Beta.app` | Active |
| Chrome Dev | `/Applications/Google Chrome Dev.app` | Active |
| Google Earth Pro | `/Applications/Google Earth Pro.app` | Active |
| Google Drive | `/Applications/Google Drive.app` | Active |
| Backup and Sync | `/Applications/Backup and Sync.app` | Replaced by Drive |
| Android File Transfer | `/Applications/Android File Transfer.app` | Discontinued 2024 |
| Android Studio | `/Applications/Android Studio.app` | Active |
| Google Ads Editor | `/Applications/Google Ads Editor.app` | Active |
| Google Web Designer | `/Applications/Google Web Designer.app` | Discontinued |
| Google Chat | `/Applications/Chat.app` | Discontinued Jan 2026 |
| Google Japanese Input | `/Library/Input Methods/GoogleJapaneseInput.app` | Active |

## Background services

Google Updater (formerly Keystone) is a persistent background service that runs every hour via macOS launchctl. It checks for updates and sends hardware information to Google.

### LaunchAgents (per-user, run on login)

- `~/Library/LaunchAgents/com.google.keystone.agent.plist`
- `~/Library/LaunchAgents/com.google.keystone.xpcservice.plist`
- `~/Library/LaunchAgents/com.google.GoogleUpdater.wake.login.plist`
- `~/Library/LaunchAgents/com.google.android.mtpagent.plist`

### LaunchAgents (system-wide)

- `/Library/LaunchAgents/com.google.keystone.agent.plist`
- `/Library/LaunchAgents/com.google.keystone.xpcservice.plist`
- `/Library/LaunchAgents/com.google.inputmethod.Japanese.Converter.plist`
- `/Library/LaunchAgents/com.google.inputmethod.Japanese.Renderer.plist`
- `/Library/LaunchAgents/org.chromium.chromoting.plist`

### LaunchDaemons (system-wide, run as root)

- `/Library/LaunchDaemons/com.google.keystone.daemon.plist`
- `/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist`
- `/Library/LaunchDaemons/org.chromium.chromoting.plist`

## Per-app data locations

Each app stores data across multiple `~/Library` subdirectories, matched by bundle ID prefix:

| App | Bundle ID prefix | Extra directories |
|-----|-----------------|-------------------|
| Chrome | `com.google.Chrome` | `~/Library/Application Support/Google/Chrome` |
| Chrome Canary | `com.google.Chrome.canary` | `~/Library/Application Support/Google/Chrome Canary` |
| Chrome Beta | `com.google.Chrome.beta` | `~/Library/Application Support/Google/Chrome Beta` |
| Chrome Dev | `com.google.Chrome.dev` | `~/Library/Application Support/Google/Chrome Dev` |
| Earth Pro | `com.google.GoogleEarthPro`, `com.google.GECommonSettings` | `~/Library/Application Support/Google Earth`, `~/Library/Caches/Google Earth` |
| Drive | `com.google.drivefs` | `~/Library/Application Support/Google/DriveFS`, `~/Library/Application Support/FileProvider/com.google.drivefs.fpext` |
| Android Studio | `com.google.android.studio` | `~/.android` |
| Chat | `com.google.chat` | `~/Library/Application Support/Chat`, `~/Library/Logs/Chat` |
| Japanese Input | `com.google.inputmethod.Japanese` | `~/Library/Logs/GoogleJapaneseInput` |

Bundle ID matching searches these directories:

- `~/Library/Caches/`
- `~/Library/Preferences/`
- `~/Library/Containers/`
- `~/Library/HTTPStorages/`
- `~/Library/Saved Application State/`
- `~/Library/WebKit/`
- `~/Library/Application Scripts/`
- `~/Library/Logs/`
- `~/Library/Group Containers/`

## Shared Google infrastructure

These don't belong to any specific app:

- `/Library/Google/`
- `/Library/Application Support/Google/`
- `/Library/Caches/com.google.SoftwareUpdate/`
- `~/Library/Google/` (Keystone/updater home)
- `~/Library/Application Support/Google/`
- `~/Library/Logs/GoogleSoftwareUpdateAgent.log`
- `com.google.keystone*` and `com.google.Keystone*` entries across Library subdirs

## Google Cloud SDK

Installed separately (not via App Store or .app):

- `~/google-cloud-sdk/`
- `~/.config/gcloud/`
- Modifies shell profile (`~/.zshrc`) for PATH and completions

## Processes

Known Google process names:

`GoogleUpdater`, `GoogleSoftwareUpdateAgent`, `GoogleSoftwareUpdateDaemon`, `Google Chrome`, `Google Chrome Helper`, `Google Chrome Canary`, `Google Chrome Beta`, `Google Chrome Dev`, `Google Earth Pro`, `Google Drive`, `Google Drive Helper`, `GoogleDriveFS`, `Android File Transfer Agent`, `GoogleJapaneseInput`, `remoting_me2me_host`, `keystone`, `ksinstall`, `ksadmin`
