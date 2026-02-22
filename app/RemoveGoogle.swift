import Cocoa
import SwiftUI

// MARK: - Data Model

struct GoogleItem: Identifiable {
    let id = UUID()
    let name: String
    var detail: String
    var paths: [String]         // files/dirs to check and remove
    let category: Category
    var requiresSudo: Bool
    var isFound: Bool = false
    var isSelected: Bool = true
    var isRemoved: Bool = false
    var sizeString: String = ""

    enum Category: String {
        case service = "Background Services"
        case app = "Applications"
        case data = "Data & Preferences"
    }

    var isTogglable: Bool { true }
}

// Per-app definition: app path, display name, bundle ID prefixes for data matching, extra data dirs
struct AppDef {
    let appPath: String
    let name: String
    let bundleIds: [String]
    let extraDirs: [String]  // additional specific directories (relative to home)
}

// MARK: - Scanner / Remover

class GoogleManager: ObservableObject {
    @Published var items: [GoogleItem] = []
    @Published var status: String = "Scanning..."
    @Published var statusColor: NSColor = .secondaryLabelColor
    @Published var isWorking: Bool = false
    @Published var isDone: Bool = false
    @Published var mode: Mode = .ready

    enum Mode {
        case ready, removing, removed, restoring, restored
    }

    private let fm = FileManager.default
    private let trashPath = NSHomeDirectory() + "/.Trash"

    // All known Google process names
    private let processNames = [
        "GoogleUpdater", "GoogleSoftwareUpdateAgent", "GoogleSoftwareUpdateDaemon",
        "Google Chrome Helper", "Google Chrome", "Google Chrome Canary",
        "Google Chrome Beta", "Google Chrome Dev", "Google Earth Pro",
        "Google Drive", "Google Drive Helper", "GoogleDriveFS",
        "Android File Transfer Agent", "GoogleJapaneseInput",
        "remoting_me2me_host", "keystone", "ksinstall", "ksadmin"
    ]

    // Plist paths and their launchctl domains
    private let userPlists: [(path: String, domain: String)] = {
        let home = NSHomeDirectory()
        return [
            (home + "/Library/LaunchAgents/com.google.keystone.agent.plist", "gui/\(getuid())"),
            (home + "/Library/LaunchAgents/com.google.keystone.xpcservice.plist", "gui/\(getuid())"),
            (home + "/Library/LaunchAgents/com.google.GoogleUpdater.wake.login.plist", "gui/\(getuid())"),
            (home + "/Library/LaunchAgents/com.google.android.mtpagent.plist", "gui/\(getuid())"),
        ]
    }()

    private let systemPlists: [(path: String, domain: String)] = [
        ("/Library/LaunchAgents/com.google.keystone.agent.plist", "system"),
        ("/Library/LaunchAgents/com.google.keystone.xpcservice.plist", "system"),
        ("/Library/LaunchDaemons/com.google.keystone.daemon.plist", "system"),
        ("/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist", "system"),
        ("/Library/LaunchAgents/com.google.inputmethod.Japanese.Converter.plist", "system"),
        ("/Library/LaunchAgents/com.google.inputmethod.Japanese.Renderer.plist", "system"),
        ("/Library/LaunchAgents/org.chromium.chromoting.plist", "system"),
        ("/Library/LaunchDaemons/org.chromium.chromoting.plist", "system"),
    ]

    // Library subdirectories to search for app-specific data
    private let librarySearchDirs = [
        "Caches", "Preferences", "Containers", "HTTPStorages",
        "Saved Application State", "WebKit", "Application Scripts", "Logs"
    ]

    // All app definitions with their associated data
    private var appDefs: [AppDef] {
        let home = NSHomeDirectory()
        return [
            AppDef(appPath: "/Applications/Google Chrome.app", name: "Google Chrome",
                   bundleIds: ["com.google.Chrome"],
                   extraDirs: [home + "/Library/Application Support/Google/Chrome"]),

            AppDef(appPath: "/Applications/Google Chrome Canary.app", name: "Chrome Canary",
                   bundleIds: ["com.google.Chrome.canary"],
                   extraDirs: [home + "/Library/Application Support/Google/Chrome Canary"]),

            AppDef(appPath: "/Applications/Google Chrome Beta.app", name: "Chrome Beta",
                   bundleIds: ["com.google.Chrome.beta"],
                   extraDirs: [home + "/Library/Application Support/Google/Chrome Beta"]),

            AppDef(appPath: "/Applications/Google Chrome Dev.app", name: "Chrome Dev",
                   bundleIds: ["com.google.Chrome.dev"],
                   extraDirs: [home + "/Library/Application Support/Google/Chrome Dev"]),

            AppDef(appPath: "/Applications/Google Earth Pro.app", name: "Google Earth Pro",
                   bundleIds: ["com.google.GoogleEarthPro", "com.google.GECommonSettings", "com.Google.GoogleEarthPro"],
                   extraDirs: [home + "/Library/Application Support/Google Earth",
                               home + "/Library/Caches/Google Earth"]),

            AppDef(appPath: "/Applications/Google Drive.app", name: "Google Drive",
                   bundleIds: ["com.google.drivefs"],
                   extraDirs: [home + "/Library/Application Support/Google/DriveFS",
                               home + "/Library/Application Support/FileProvider/com.google.drivefs.fpext",
                               home + "/Library/Preferences/Google Drive File Stream Helper.plist"]),

            AppDef(appPath: "/Applications/Backup and Sync.app", name: "Backup and Sync",
                   bundleIds: ["com.google.Backup"],
                   extraDirs: []),

            AppDef(appPath: "/Applications/Android File Transfer.app", name: "Android File Transfer",
                   bundleIds: ["com.google.android.filetransfer"],
                   extraDirs: [home + "/Library/Application Support/Google/Android File Transfer"]),

            AppDef(appPath: "/Applications/Android Studio.app", name: "Android Studio",
                   bundleIds: ["com.google.android.studio"],
                   extraDirs: [home + "/Library/Application Support/Google/AndroidStudio",
                               home + "/.android"]),

            AppDef(appPath: "/Applications/Google Ads Editor.app", name: "Google Ads Editor",
                   bundleIds: ["com.google.googleadseditor"],
                   extraDirs: []),

            AppDef(appPath: "/Applications/Google Web Designer.app", name: "Google Web Designer",
                   bundleIds: ["com.google.WebDesigner"],
                   extraDirs: [home + "/Library/Application Support/Google/Web Designer"]),

            AppDef(appPath: "/Applications/Chat.app", name: "Google Chat",
                   bundleIds: ["com.google.chat"],
                   extraDirs: [home + "/Library/Application Support/Chat",
                               home + "/Library/Logs/Chat"]),

            AppDef(appPath: "/Library/Input Methods/GoogleJapaneseInput.app", name: "Google Japanese Input",
                   bundleIds: ["com.google.inputmethod.Japanese"],
                   extraDirs: [home + "/Library/Logs/GoogleJapaneseInput"]),
        ]
    }

    func scan() {
        let home = NSHomeDirectory()
        var scanned: [GoogleItem] = []
        // Track which data paths are claimed by an app so shared infra doesn't double-count
        var claimedPaths = Set<String>()

        // --- Services ---
        var servicePaths: [String] = []
        var serviceCount = 0
        for (path, _) in userPlists + systemPlists {
            if fm.fileExists(atPath: path) {
                servicePaths.append(path)
                serviceCount += 1
            }
        }
        let launchctlOutput = shell("/bin/bash", ["-c", "launchctl list 2>/dev/null | grep -i google || true"])
        let hasLoadedService = !launchctlOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasLoadedService || serviceCount > 0 {
            var detail = ""
            if hasLoadedService { detail = "Google Updater runs every hour" }
            if serviceCount > 0 {
                if !detail.isEmpty { detail += " · " }
                detail += "\(serviceCount) plist\(serviceCount == 1 ? "" : "s")"
            }
            var item = GoogleItem(
                name: "Background services",
                detail: detail,
                paths: servicePaths,
                category: .service,
                requiresSudo: servicePaths.contains(where: { !$0.hasPrefix(home) })
            )
            item.isFound = true
            scanned.append(item)
        }

        // --- Apps with per-app data ---
        for def in appDefs {
            var paths = [def.appPath]
            var dataSize: UInt64 = 0
            let appExists = fm.fileExists(atPath: def.appPath)

            // Search Library subdirs for matching bundle IDs
            for id in def.bundleIds {
                for subdir in librarySearchDirs {
                    let dir = home + "/Library/" + subdir
                    if let contents = try? fm.contentsOfDirectory(atPath: dir) {
                        for name in contents where name.hasPrefix(id) {
                            let full = dir + "/" + name
                            paths.append(full)
                            claimedPaths.insert(full)
                            dataSize += dirSize(full)
                        }
                    }
                }
            }

            // Check extra dirs
            for extra in def.extraDirs {
                if fm.fileExists(atPath: extra) {
                    paths.append(extra)
                    claimedPaths.insert(extra)
                    dataSize += dirSize(extra)
                }
            }

            // Group containers matching bundle IDs
            let gcDir = home + "/Library/Group Containers"
            for id in def.bundleIds {
                if let contents = try? fm.contentsOfDirectory(atPath: gcDir) {
                    for name in contents where name.lowercased().contains(id.lowercased()) {
                        let full = gcDir + "/" + name
                        if !paths.contains(full) {
                            paths.append(full)
                            claimedPaths.insert(full)
                            dataSize += dirSize(full)
                        }
                    }
                }
            }
            // Also check for EQHXZ8M8AV (Google Drive group container)
            if def.bundleIds.contains("com.google.drivefs") {
                if let contents = try? fm.contentsOfDirectory(atPath: gcDir) {
                    for name in contents where name.hasPrefix("EQHXZ8M8AV.") {
                        let full = gcDir + "/" + name
                        if !paths.contains(full) {
                            paths.append(full)
                            claimedPaths.insert(full)
                            dataSize += dirSize(full)
                        }
                    }
                }
                // Application Scripts for Drive
                let scriptsDir = home + "/Library/Application Scripts"
                if let contents = try? fm.contentsOfDirectory(atPath: scriptsDir) {
                    for name in contents where name.hasPrefix("EQHXZ8M8AV.") {
                        let full = scriptsDir + "/" + name
                        if !paths.contains(full) {
                            paths.append(full)
                            claimedPaths.insert(full)
                        }
                    }
                }
            }

            let hasData = paths.count > 1 // more than just the .app path
            let needsSudo = !def.appPath.hasPrefix(home)

            var item = GoogleItem(
                name: def.name,
                detail: "",
                paths: paths,
                category: .app,
                requiresSudo: needsSudo
            )

            if appExists {
                item.isFound = true
                let appSize = sizeOf(def.appPath)
                if dataSize > 0 {
                    item.detail = "\(appSize) app + \(formatBytes(dataSize)) data"
                } else {
                    item.detail = appSize
                }
            } else if hasData {
                // App not installed but orphaned data remains
                item.isFound = true
                item.paths = Array(paths.dropFirst()) // remove the .app path since it doesn't exist
                item.requiresSudo = false // orphaned data is user-level
                item.detail = "app removed, \(formatBytes(dataSize)) data remains"
            } else {
                item.isFound = false
                item.isSelected = false
                item.detail = "not installed"
            }
            scanned.append(item)
        }

        // --- System directories ---
        let sysDirs = [
            "/Library/Google",
            "/Library/Application Support/Google",
            "/Library/Caches/com.google.SoftwareUpdate",
        ]
        var sysFound: [String] = []
        for dir in sysDirs {
            if fm.fileExists(atPath: dir) { sysFound.append(dir) }
        }
        if !sysFound.isEmpty {
            var item = GoogleItem(
                name: "System directories",
                detail: sysFound.joined(separator: ", "),
                paths: sysFound,
                category: .data,
                requiresSudo: true
            )
            item.isFound = true
            scanned.append(item)
        }

        // --- Shared Google infrastructure (unclaimed user data) ---
        // These are Keystone/updater files not tied to any specific app
        let sharedPrefixes = [
            "com.google.keystone", "com.google.Keystone",
            "com.google.GoogleUpdater", "com.google.SoftwareUpdate",
        ]
        let sharedDirs = [
            home + "/Library/Google",
            home + "/Library/Application Support/Google",
        ]
        let sharedFiles = [
            home + "/Library/Logs/GoogleSoftwareUpdateAgent.log",
        ]

        var sharedPaths: [String] = []
        var sharedSize: UInt64 = 0

        for dir in sharedDirs {
            if fm.fileExists(atPath: dir) && !claimedPaths.contains(dir) {
                sharedPaths.append(dir)
                sharedSize += dirSize(dir)
            }
        }
        for prefix in sharedPrefixes {
            for subdir in librarySearchDirs {
                let dir = home + "/Library/" + subdir
                if let contents = try? fm.contentsOfDirectory(atPath: dir) {
                    for name in contents where name.hasPrefix(prefix) {
                        let full = dir + "/" + name
                        if !claimedPaths.contains(full) {
                            sharedPaths.append(full)
                            claimedPaths.insert(full)
                            sharedSize += dirSize(full)
                        }
                    }
                }
            }
        }
        // Unclaimed google group containers
        let gcDir = home + "/Library/Group Containers"
        if let contents = try? fm.contentsOfDirectory(atPath: gcDir) {
            for name in contents where name.lowercased().contains("google") {
                let full = gcDir + "/" + name
                if !claimedPaths.contains(full) {
                    sharedPaths.append(full)
                    sharedSize += dirSize(full)
                }
            }
        }
        for file in sharedFiles {
            if fm.fileExists(atPath: file) && !claimedPaths.contains(file) {
                sharedPaths.append(file)
            }
        }

        if !sharedPaths.isEmpty {
            var item = GoogleItem(
                name: "Shared Google data",
                detail: "\(formatBytes(sharedSize)) — updater, Keystone",
                paths: sharedPaths,
                category: .data,
                requiresSudo: false
            )
            item.isFound = true
            scanned.append(item)
        }

        // --- Google Cloud SDK (standalone) ---
        let gcloudPaths = [
            home + "/google-cloud-sdk",
            home + "/.config/gcloud",
        ]
        var gcloudFound: [String] = []
        var gcloudSize: UInt64 = 0
        for path in gcloudPaths {
            if fm.fileExists(atPath: path) {
                gcloudFound.append(path)
                gcloudSize += dirSize(path)
            }
        }
        if !gcloudFound.isEmpty {
            var item = GoogleItem(
                name: "Google Cloud SDK",
                detail: formatBytes(gcloudSize),
                paths: gcloudFound,
                category: .data,
                requiresSudo: false
            )
            item.isFound = true
            scanned.append(item)
        }

        DispatchQueue.main.async {
            self.items = scanned
            let foundCount = scanned.filter({ $0.isFound }).count
            if foundCount == 0 {
                self.status = "No Google software found"
                self.statusColor = NSColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1)
            } else {
                self.status = "Found \(foundCount) item\(foundCount == 1 ? "" : "s")"
                self.statusColor = .secondaryLabelColor
            }
        }
    }

    func removeSelected() {
        guard !isWorking else { return }
        isWorking = true
        mode = .removing
        status = "Stopping Google processes..."
        statusColor = NSColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // Kill processes
            for name in processNames {
                _ = shell("/usr/bin/killall", [name])
            }
            Thread.sleep(forTimeInterval: 1)

            // Unload plists
            updateStatus("Unloading services...")
            for (path, domain) in userPlists {
                if fm.fileExists(atPath: path) {
                    unloadPlist(path: path, domain: domain, sudo: false)
                }
            }

            // Build sudo command for privileged operations
            var sudoCommands: [String] = []

            // Unload system plists
            for (path, domain) in systemPlists {
                if fm.fileExists(atPath: path) {
                    let label = plistLabel(path)
                    if let label = label {
                        sudoCommands.append("launchctl bootout \(domain)/\(label) 2>/dev/null || true")
                    } else {
                        sudoCommands.append("launchctl unload -w '\(path)' 2>/dev/null || true")
                    }
                }
            }

            // Collect all selected items
            let selected = items.filter({ $0.isFound && $0.isSelected })

            // Separate user-level and sudo-level paths
            var userPaths: [String] = []
            for item in selected {
                for path in item.paths {
                    if fm.fileExists(atPath: path) {
                        if item.requiresSudo || !path.hasPrefix(NSHomeDirectory()) {
                            let dest = trashDest(for: path)
                            sudoCommands.append("mv '\(path)' '\(dest)'")
                        } else {
                            userPaths.append(path)
                        }
                    }
                }
            }

            // Trash user-level files (no sudo needed)
            updateStatus("Moving files to Trash...")
            for path in userPaths {
                let url = URL(fileURLWithPath: path)
                try? fm.trashItem(at: url, resultingItemURL: nil)
            }

            // Execute privileged commands in one sudo call
            if !sudoCommands.isEmpty {
                updateStatus("Requesting admin access...")
                let script = sudoCommands.joined(separator: " && ")
                let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                _ = shell("/usr/bin/osascript", [
                    "-e", "do shell script \"\(escaped)\" with administrator privileges"
                ])
            }

            // Install blocker if requested (check on main thread)
            var shouldBlock = false
            DispatchQueue.main.sync {
                // installBlocker is on ContentView, but we pass it through
                // For now, always install blocker — controlled by UI toggle
                shouldBlock = true
            }
            if shouldBlock {
                let blockerPath = NSHomeDirectory() + "/Library/Google"
                if !fm.fileExists(atPath: blockerPath) {
                    fm.createFile(atPath: blockerPath, contents: nil)
                    _ = shell("/bin/chmod", ["000", blockerPath])
                }
            }

            // Mark items as removed and rescan
            updateStatus("Verifying...")
            Thread.sleep(forTimeInterval: 0.5)

            DispatchQueue.main.async {
                for i in self.items.indices {
                    if self.items[i].isSelected && self.items[i].isFound {
                        let anyRemain = self.items[i].paths.contains(where: { self.fm.fileExists(atPath: $0) })
                        self.items[i].isRemoved = !anyRemain
                    }
                }
                let removedCount = self.items.filter({ $0.isRemoved }).count
                self.status = "Done — \(removedCount) item\(removedCount == 1 ? "" : "s") moved to Trash"
                self.statusColor = NSColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1)
                self.isWorking = false
                self.isDone = true
                self.mode = .removed
            }
        }
    }

    func restore() {
        guard !isWorking else { return }
        isWorking = true
        mode = .restoring
        status = "Scanning Trash..."
        statusColor = NSColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // Remove blocker file
            let blockerPath = NSHomeDirectory() + "/Library/Google"
            if fm.fileExists(atPath: blockerPath) {
                _ = shell("/bin/chmod", ["644", blockerPath])
                try? fm.removeItem(atPath: blockerPath)
            }

            // Build restore map: basename → original path
            let home = NSHomeDirectory()
            let restoreMap: [(basename: String, dest: String, sudo: Bool)] = [
                // Plists
                ("com.google.keystone.agent.plist", "/Library/LaunchAgents/com.google.keystone.agent.plist", true),
                ("com.google.keystone.xpcservice.plist", "/Library/LaunchAgents/com.google.keystone.xpcservice.plist", true),
                ("com.google.keystone.daemon.plist", "/Library/LaunchDaemons/com.google.keystone.daemon.plist", true),
                ("com.google.GoogleUpdater.wake.system.plist", "/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist", true),
                ("com.google.GoogleUpdater.wake.login.plist", home + "/Library/LaunchAgents/com.google.GoogleUpdater.wake.login.plist", false),
                // Apps
                ("Google Chrome.app", "/Applications/Google Chrome.app", true),
                ("Google Chrome Canary.app", "/Applications/Google Chrome Canary.app", true),
                ("Google Chrome Beta.app", "/Applications/Google Chrome Beta.app", true),
                ("Google Chrome Dev.app", "/Applications/Google Chrome Dev.app", true),
                ("Google Earth Pro.app", "/Applications/Google Earth Pro.app", true),
                ("Google Drive.app", "/Applications/Google Drive.app", true),
                ("Backup and Sync.app", "/Applications/Backup and Sync.app", true),
                ("Android File Transfer.app", "/Applications/Android File Transfer.app", true),
                ("Android Studio.app", "/Applications/Android Studio.app", true),
                ("Google Ads Editor.app", "/Applications/Google Ads Editor.app", true),
                ("Google Web Designer.app", "/Applications/Google Web Designer.app", true),
                ("Chat.app", "/Applications/Chat.app", true),
                ("GoogleJapaneseInput.app", "/Library/Input Methods/GoogleJapaneseInput.app", true),
                // System dirs
                ("Google", "/Library/Google", true),
                // User data
                ("com.google.GoogleUpdater", home + "/Library/Caches/com.google.GoogleUpdater", false),
                ("com.google.Chrome.plist", home + "/Library/Preferences/com.google.Chrome.plist", false),
                ("com.google.GECommonSettings.plist", home + "/Library/Preferences/com.google.GECommonSettings.plist", false),
                ("com.google.GoogleEarthPro.plist", home + "/Library/Preferences/com.google.GoogleEarthPro.plist", false),
                ("com.google.Keystone.Agent.plist", home + "/Library/Preferences/com.google.Keystone.Agent.plist", false),
                ("com.google.Chrome", home + "/Library/WebKit/com.google.Chrome", false),
            ]

            var sudoCommands: [String] = []
            var userRestores: [(from: String, to: String)] = []
            var restoredCount = 0

            for entry in restoreMap {
                if fm.fileExists(atPath: entry.dest) { continue }
                if let trashItem = findInTrash(entry.basename) {
                    if entry.sudo {
                        let parentDir = (entry.dest as NSString).deletingLastPathComponent
                        sudoCommands.append("mkdir -p '\(parentDir)' && mv '\(trashItem)' '\(entry.dest)'")
                    } else {
                        userRestores.append((from: trashItem, to: entry.dest))
                    }
                    restoredCount += 1
                }
            }

            if restoredCount == 0 {
                DispatchQueue.main.async {
                    self.status = "Nothing found in Trash to restore"
                    self.statusColor = NSColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1)
                    self.isWorking = false
                    self.mode = .ready
                }
                return
            }

            updateStatus("Restoring \(restoredCount) items...")

            // Restore user-level files
            for entry in userRestores {
                let parentDir = (entry.to as NSString).deletingLastPathComponent
                try? fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                try? fm.moveItem(atPath: entry.from, toPath: entry.to)
            }

            // Restore system-level files
            if !sudoCommands.isEmpty {
                let script = sudoCommands.joined(separator: " && ")
                let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                _ = shell("/usr/bin/osascript", [
                    "-e", "do shell script \"\(escaped)\" with administrator privileges"
                ])
            }

            // Reload plists
            let reloadPlists = [
                ("/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist", true),
                ("/Library/LaunchDaemons/com.google.keystone.daemon.plist", true),
                ("/Library/LaunchAgents/com.google.keystone.agent.plist", true),
                ("/Library/LaunchAgents/com.google.keystone.xpcservice.plist", true),
                (home + "/Library/LaunchAgents/com.google.GoogleUpdater.wake.login.plist", false),
            ]
            for (path, sudo) in reloadPlists {
                if fm.fileExists(atPath: path) {
                    if sudo {
                        let escaped = "launchctl load -w '\(path)' 2>/dev/null || true"
                            .replacingOccurrences(of: "\"", with: "\\\"")
                        _ = shell("/usr/bin/osascript", [
                            "-e", "do shell script \"\(escaped)\" with administrator privileges"
                        ])
                    } else {
                        _ = shell("/bin/launchctl", ["load", "-w", path])
                    }
                }
            }

            DispatchQueue.main.async {
                self.status = "Restored \(restoredCount) item\(restoredCount == 1 ? "" : "s")"
                self.statusColor = NSColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1)
                self.isWorking = false
                self.mode = .restored
                // Rescan
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.scan()
                    self.mode = .ready
                }
            }
        }
    }

    // MARK: - Helpers

    private func updateStatus(_ msg: String) {
        DispatchQueue.main.async { self.status = msg }
    }

    private func shell(_ cmd: String, _ args: [String]) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: cmd)
        task.arguments = args
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func unloadPlist(path: String, domain: String, sudo: Bool) {
        let label = plistLabel(path)
        if let label = label {
            if sudo {
                _ = shell("/usr/bin/osascript", ["-e",
                    "do shell script \"launchctl bootout \(domain)/\(label) 2>/dev/null || true\" with administrator privileges"])
            } else {
                _ = shell("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
            }
        } else {
            if sudo {
                _ = shell("/usr/bin/osascript", ["-e",
                    "do shell script \"launchctl unload -w '\(path)' 2>/dev/null || true\" with administrator privileges"])
            } else {
                _ = shell("/bin/launchctl", ["unload", "-w", path])
            }
        }
    }

    private func plistLabel(_ path: String) -> String? {
        let output = shell("/usr/libexec/PlistBuddy", ["-c", "Print :Label", path])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func trashDest(for path: String) -> String {
        let basename = (path as NSString).lastPathComponent
        let dest = trashPath + "/" + basename
        if fm.fileExists(atPath: dest) {
            return trashPath + "/" + basename + "_\(Int(Date().timeIntervalSince1970))"
        }
        return dest
    }

    private func findInTrash(_ basename: String) -> String? {
        let exact = trashPath + "/" + basename
        if fm.fileExists(atPath: exact) { return exact }
        if let contents = try? fm.contentsOfDirectory(atPath: trashPath) {
            for name in contents where name.hasPrefix(basename + "_") {
                let suffix = String(name.dropFirst(basename.count + 1))
                if suffix.allSatisfy({ $0.isNumber }) {
                    return trashPath + "/" + name
                }
            }
        }
        return nil
    }

    private func sizeOf(_ path: String) -> String {
        let output = shell("/usr/bin/du", ["-sh", path])
        return output.split(separator: "\t").first.map(String.init) ?? ""
    }

    private func dirSize(_ path: String) -> UInt64 {
        // If it's a file not a directory, return file size
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? UInt64 { return size }
            return 0
        }
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var total: UInt64 = 0
        while let file = enumerator.nextObject() as? String {
            let full = path + "/" + file
            if let attrs = try? fm.attributesOfItem(atPath: full),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // All app names for the "scanned for" display
    var allAppNames: [String] {
        appDefs.map { $0.name }
    }
}

// MARK: - SwiftUI Views

struct ContentView: View {
    @ObservedObject var manager = GoogleManager()
    @State private var installBlocker = true
    @State private var hovering = false
    @State private var showingInfoFor: UUID? = nil

    let mono = Font.system(size: 12, design: .monospaced)
    let monoBold = Font.system(size: 12, weight: .semibold, design: .monospaced)
    let sectionFont = Font.system(size: 10, weight: .bold, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Remove Google")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                Spacer()
                Text("v1.0")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 20)

            // Items list
            if manager.items.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning...")
                        .font(mono)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            } else {
                let services = manager.items.filter { $0.category == .service }
                let apps = manager.items.filter { $0.category == .app }
                let data = manager.items.filter { $0.category == .data }

                if !services.isEmpty {
                    sectionHeader("BACKGROUND SERVICES")
                    ForEach(services) { item in itemRow(item) }
                    Spacer().frame(height: 16)
                }

                if !apps.isEmpty {
                    let foundApps = apps.filter { $0.isFound }
                    let notFoundApps = apps.filter { !$0.isFound }
                    sectionHeader("APPLICATIONS")
                    if foundApps.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.green)
                                .font(.system(size: 14))
                            Text("No Google apps installed")
                                .font(mono)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    } else {
                        ForEach(foundApps) { item in itemRow(item) }
                    }
                    if !notFoundApps.isEmpty {
                        let names = notFoundApps.map { $0.name }.joined(separator: ", ")
                        Text("Also scanned: \(names)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .padding(.top, 4)
                    }
                    Spacer().frame(height: 16)
                }

                if !data.isEmpty {
                    sectionHeader("DATA & PREFERENCES")
                    ForEach(data) { item in itemRow(item) }
                    Spacer().frame(height: 8)
                }
            }

            Spacer().frame(height: 12)

            // Blocker toggle with inline explanation
            if !manager.isDone {
                Toggle(isOn: $installBlocker) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Block Google from reinstalling")
                            .font(mono)
                        Text("Places a locked file at ~/Library/Google to prevent the updater from returning")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(manager.isWorking)
                .padding(.bottom, 14)
            }

            // Safety note
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Files are moved to Trash, not permanently deleted.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            // Disclaimer
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("Use at your own risk. Not responsible for data loss.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            // Buttons
            HStack(spacing: 16) {
                if manager.mode != .removed {
                    Button(action: { manager.removeSelected() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                            Text("Remove Selected")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }
                        .frame(minWidth: 160, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(manager.isWorking || !manager.items.contains(where: { $0.isFound && $0.isSelected }))
                }

                Button(action: {
                    if manager.mode == .removed {
                        manager.scan()
                        manager.mode = .ready
                        manager.isDone = false
                    } else {
                        manager.restore()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: manager.mode == .removed ? "arrow.clockwise" : "arrow.uturn.backward")
                            .font(.system(size: 12))
                        Text(manager.mode == .removed ? "Rescan" : "Restore")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    .frame(minWidth: 100, minHeight: 28)
                }
                .buttonStyle(.bordered)
                .disabled(manager.isWorking)

                Spacer()

                if manager.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Status bar + footer
            Divider()
                .padding(.top, 12)
                .padding(.bottom, 8)

            HStack {
                Text(manager.status)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(nsColor: manager.statusColor))
                Spacer()
                Text("by")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
                Text("IO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .onTapGesture {
                        if let url = URL(string: "https://github.com/isolson/remove-google-macos") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .onHover { h in hovering = h }
                    .underline(hovering)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(.ultraThinMaterial)
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                manager.scan()
            }
        }
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(sectionFont)
            .foregroundStyle(.tertiary)
            .tracking(1.5)
            .padding(.bottom, 6)
    }

    func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    @ViewBuilder
    func itemRow(_ item: GoogleItem) -> some View {
        let idx = manager.items.firstIndex(where: { $0.id == item.id })!

        if item.isRemoved {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                Text(item.name)
                    .font(mono)
                    .foregroundColor(.green)
                Text("removed")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.7))
                Spacer()
            }
            .padding(.vertical, 3)
        } else if !item.isFound {
            HStack(spacing: 8) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.quaternary)
                    .font(.system(size: 14))
                Text(item.name)
                    .font(mono)
                    .foregroundStyle(.quaternary)
                Text(item.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.quaternary)
                Spacer()
            }
            .padding(.vertical, 3)
        } else {
            HStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { manager.items[idx].isSelected },
                    set: { manager.items[idx].isSelected = $0 }
                )) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(mono)
                        if !item.detail.isEmpty {
                            Text("(\(item.detail))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(manager.isWorking)

                Spacer()

                // Info button showing paths
                if item.paths.count > 0 {
                    Button(action: {
                        if showingInfoFor == item.id {
                            showingInfoFor = nil
                        } else {
                            showingInfoFor = item.id
                        }
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(
                        get: { showingInfoFor == item.id },
                        set: { if !$0 { showingInfoFor = nil } }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Will remove:")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .padding(.bottom, 4)
                            ForEach(item.paths, id: \.self) { path in
                                Text(shortPath(path))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: 400)
                    }
                }
            }
            .padding(.vertical, 3)
        }
    }
}

// MARK: - App Entry

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 100),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isRestorable = false
        window.center()
        window.title = "Remove Google"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
