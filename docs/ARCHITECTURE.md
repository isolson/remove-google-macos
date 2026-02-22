# Architecture

## Overview

Remove Google is a single-file SwiftUI app (`app/RemoveGoogle.swift`) compiled with `swiftc`. No Xcode project, no dependencies, no package manager.

## Build

```bash
bash build.sh                    # compile + assemble .app bundle
bash build.sh --sign "Dev ID..." # compile + sign
```

`build.sh` compiles with `xcrun swiftc`, creates the `.app` bundle structure (`Contents/MacOS`, `Contents/Resources`, `Info.plist`), and optionally signs with `codesign`.

### Notarization

```bash
ditto -c -k --sequesterRsrc --keepParent "build/Remove Google.app" app.zip
xcrun notarytool submit app.zip --keychain-profile "profile" --wait
xcrun stapler staple "build/Remove Google.app"
```

## Code structure

The app is ~600 lines in a single file with four sections:

### Data model (`GoogleItem`, `AppDef`)

`GoogleItem` represents a scannable/removable item (app, service, or data). Each has a name, paths array, category, and selection state.

`AppDef` maps an app to its bundle ID prefixes and extra data directories. This is how per-app data association works — when you uncheck Chrome, its `com.google.Chrome*` caches/preferences stay intact.

### GoogleManager (ObservableObject)

The core logic class with three main operations:

- **`scan()`** — Checks the filesystem for Google software. For each app, it collects the `.app` path plus all matching data paths (by bundle ID prefix across `~/Library/{Caches,Preferences,Containers,...}`). Orphaned data (app removed but data remains) is detected and shown. A `claimedPaths` set prevents double-counting between app-specific and shared infrastructure data.

- **`removeSelected()`** — Kills Google processes, unloads launchctl plists, then removes selected items. User-level files use `FileManager.trashItem()`. System-level files are batched into a single `osascript "do shell script ... with administrator privileges"` call to minimize password prompts.

- **`restore()`** — Scans Trash for known Google filenames and moves them back to their original locations. Reloads launchctl plists.

### ContentView (SwiftUI)

Dark translucent window (`.ultraThinMaterial`) with monospaced fonts. Items are grouped by category (services, apps, data). Found items get checkboxes and an info button (popover showing exact paths). Not-found apps are hidden, with a summary line listing what was scanned.

### AppDelegate + entry point

Minimal `NSWindow` setup with no state restoration, no UserDefaults, no persistence. The app leaves no trace after deletion.

## Design decisions

**Per-app data association**: Each app definition includes bundle ID prefixes. During scan, data matching those prefixes is rolled into the app's paths array. This means unchecking an app preserves its data — no accidental data loss.

**Trash, not delete**: All operations use Trash (user-level via `FileManager.trashItem`, system-level via `mv` to `~/.Trash`). This makes every operation reversible.

**Single sudo prompt**: System-level operations (unloading daemons, moving `/Applications/*.app`, moving `/Library/Google`) are batched into one `osascript` call. The user sees one password dialog.

**Zero-trace design**: `window.isRestorable = false`, no `@AppStorage`, no `UserDefaults`, no `NSUbiquitousKeyValueStore`. The app writes nothing to disk except Trash operations.

**Anti-reinstall blocker**: Creates an empty file at `~/Library/Google` with `chmod 000`. Google Updater expects this to be a directory it can write to — the locked file prevents it from recreating its infrastructure.

## Known limitations

- Restore relies on finding items in Trash by basename. If the user renames or empties Trash, restore won't find them.
- `.help()` tooltips don't render with `fullSizeContentView` window style; info button popovers are used instead.
