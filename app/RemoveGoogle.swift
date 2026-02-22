import Cocoa
import SwiftUI

// MARK: - Data Model

struct GoogleItem: Identifiable {
    let id = UUID()
    let name: String
    var detail: String
    let paths: [String]         // files/dirs to check and remove
    let category: Category
    let requiresSudo: Bool
    var isFound: Bool = false
    var isSelected: Bool = true
    var isRemoved: Bool = false
    var sizeString: String = ""

    enum Category: String {
        case service = "Background Services"
        case app = "Applications"
        case data = "Data & Preferences"
    }

    var isTogglable: Bool { category == .app }
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
        "Google Chrome Helper", "Google Chrome", "Google Earth Pro",
        "keystone", "ksinstall", "ksadmin"
    ]

    // Plist paths and their launchctl domains
    private let userPlists: [(path: String, domain: String)] = {
        let home = NSHomeDirectory()
        return [
            (home + "/Library/LaunchAgents/com.google.keystone.agent.plist", "gui/\(getuid())"),
            (home + "/Library/LaunchAgents/com.google.keystone.xpcservice.plist", "gui/\(getuid())"),
            (home + "/Library/LaunchAgents/com.google.GoogleUpdater.wake.login.plist", "gui/\(getuid())"),
        ]
    }()

    private let systemPlists: [(path: String, domain: String)] = [
        ("/Library/LaunchAgents/com.google.keystone.agent.plist", "system"),
        ("/Library/LaunchAgents/com.google.keystone.xpcservice.plist", "system"),
        ("/Library/LaunchDaemons/com.google.keystone.daemon.plist", "system"),
        ("/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist", "system"),
    ]

    func scan() {
        let home = NSHomeDirectory()
        var scanned: [GoogleItem] = []

        // --- Services ---
        var servicePaths: [String] = []
        var serviceCount = 0
        for (path, _) in userPlists + systemPlists {
            if fm.fileExists(atPath: path) {
                servicePaths.append(path)
                serviceCount += 1
            }
        }
        // Check launchctl for loaded services
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

        // --- Apps ---
        let apps: [(String, String)] = [
            ("/Applications/Google Chrome.app", "Google Chrome"),
            ("/Applications/Google Earth Pro.app", "Google Earth Pro"),
            ("/Applications/Google Drive.app", "Google Drive"),
        ]
        for (path, name) in apps {
            var item = GoogleItem(
                name: name,
                detail: "",
                paths: [path],
                category: .app,
                requiresSudo: true
            )
            if fm.fileExists(atPath: path) {
                item.isFound = true
                item.sizeString = sizeOf(path)
                item.detail = item.sizeString
            } else {
                item.isFound = false
                item.isSelected = false
                item.detail = "not installed"
            }
            scanned.append(item)
        }

        // --- System dirs ---
        let sysDirs = ["/Library/Google", "/Library/Application Support/Google"]
        var sysFound: [String] = []
        for dir in sysDirs {
            if fm.fileExists(atPath: dir) { sysFound.append(dir) }
        }
        if !sysFound.isEmpty {
            var item = GoogleItem(
                name: "System directories",
                detail: sysFound.map { $0 }.joined(separator: ", "),
                paths: sysFound,
                category: .data,
                requiresSudo: true
            )
            item.isFound = true
            scanned.append(item)
        }

        // --- User data ---
        let userDirs = [
            home + "/Library/Google",
            home + "/Library/Application Support/Google",
        ]
        let userGlobPrefixes = [
            home + "/Library/Caches/com.google.",
            home + "/Library/Preferences/com.google.",
            home + "/Library/Containers/com.google.",
            home + "/Library/HTTPStorages/com.google.",
            home + "/Library/Saved Application State/com.google.",
            home + "/Library/WebKit/com.google.",
        ]
        let userLogs = [home + "/Library/Logs/GoogleSoftwareUpdateAgent.log"]

        var userPaths: [String] = []
        var totalSize: UInt64 = 0

        for dir in userDirs {
            if fm.fileExists(atPath: dir) {
                userPaths.append(dir)
                totalSize += dirSize(dir)
            }
        }
        for prefix in userGlobPrefixes {
            let parentDir = (prefix as NSString).deletingLastPathComponent
            let filePrefix = (prefix as NSString).lastPathComponent
            if let contents = try? fm.contentsOfDirectory(atPath: parentDir) {
                for name in contents where name.hasPrefix(filePrefix) {
                    let full = parentDir + "/" + name
                    userPaths.append(full)
                    totalSize += dirSize(full)
                }
            }
        }
        // Group Containers
        let gcDir = home + "/Library/Group Containers"
        if let contents = try? fm.contentsOfDirectory(atPath: gcDir) {
            for name in contents where name.lowercased().contains("google") {
                userPaths.append(gcDir + "/" + name)
                totalSize += dirSize(gcDir + "/" + name)
            }
        }
        for log in userLogs {
            if fm.fileExists(atPath: log) { userPaths.append(log) }
        }

        if !userPaths.isEmpty {
            var item = GoogleItem(
                name: "Caches & preferences",
                detail: formatBytes(totalSize),
                paths: userPaths,
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

            // Install blocker
            let blockerPath = NSHomeDirectory() + "/Library/Google"
            if !fm.fileExists(atPath: blockerPath) {
                fm.createFile(atPath: blockerPath, contents: nil)
                _ = shell("/bin/chmod", ["000", blockerPath])
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
                ("com.google.keystone.agent.plist", "/Library/LaunchAgents/com.google.keystone.agent.plist", true),
                ("com.google.keystone.xpcservice.plist", "/Library/LaunchAgents/com.google.keystone.xpcservice.plist", true),
                ("com.google.keystone.daemon.plist", "/Library/LaunchDaemons/com.google.keystone.daemon.plist", true),
                ("com.google.GoogleUpdater.wake.system.plist", "/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist", true),
                ("com.google.GoogleUpdater.wake.login.plist", home + "/Library/LaunchAgents/com.google.GoogleUpdater.wake.login.plist", false),
                ("Google Chrome.app", "/Applications/Google Chrome.app", true),
                ("Google Earth Pro.app", "/Applications/Google Earth Pro.app", true),
                ("Google Drive.app", "/Applications/Google Drive.app", true),
                ("Google", "/Library/Google", true),
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
        // Check for timestamped versions
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
}

// MARK: - SwiftUI Views

struct ContentView: View {
    @ObservedObject var manager = GoogleManager()
    @State private var installBlocker = true

    let bgColor = Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1))
    let textColor = Color(nsColor: NSColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1))
    let dimColor = Color(nsColor: NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    let greenColor = Color(nsColor: NSColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1))
    let amberColor = Color(nsColor: NSColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1))
    let monoFont = Font.custom("Menlo", size: 13)
    let headerFont = Font.custom("Menlo-Bold", size: 13)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Remove Google")
                    .font(.custom("Menlo-Bold", size: 18))
                    .foregroundColor(textColor)
                Spacer()
                Text("v1.0")
                    .font(monoFont)
                    .foregroundColor(dimColor)
            }
            .padding(.bottom, 16)

            // Items list
            if manager.items.isEmpty {
                Text("Scanning...")
                    .font(monoFont)
                    .foregroundColor(dimColor)
                    .padding(.vertical, 8)
            } else {
                let services = manager.items.filter { $0.category == .service }
                let apps = manager.items.filter { $0.category == .app }
                let data = manager.items.filter { $0.category == .data }

                if !services.isEmpty {
                    sectionHeader("BACKGROUND SERVICES")
                    ForEach(services) { item in
                        itemRow(item)
                    }
                    Spacer().frame(height: 12)
                }

                if !apps.isEmpty {
                    sectionHeader("APPLICATIONS")
                    ForEach(apps) { item in
                        itemRow(item)
                    }
                    Spacer().frame(height: 12)
                }

                if !data.isEmpty {
                    sectionHeader("DATA & PREFERENCES")
                    ForEach(data) { item in
                        itemRow(item)
                    }
                }
            }

            Spacer().frame(height: 16)

            // Safety note + blocker toggle
            Text("Files are moved to Trash, not deleted.")
                .font(monoFont)
                .foregroundColor(dimColor)
                .padding(.bottom, 8)

            if !manager.isDone {
                Toggle(isOn: $installBlocker) {
                    Text("Block Google from reinstalling")
                        .font(monoFont)
                        .foregroundColor(textColor)
                }
                .toggleStyle(.checkbox)
                .disabled(manager.isWorking)
                .padding(.bottom, 12)
            }

            Spacer().frame(height: 4)

            // Buttons
            HStack(spacing: 12) {
                if manager.mode != .removed {
                    Button(action: { manager.removeSelected() }) {
                        Text("Remove Selected")
                            .font(.custom("Menlo-Bold", size: 13))
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(nsColor: NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)))
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
                    Text(manager.mode == .removed ? "Rescan" : "Restore")
                        .font(.custom("Menlo-Bold", size: 13))
                        .frame(minWidth: 80)
                }
                .buttonStyle(.bordered)
                .disabled(manager.isWorking)

                Spacer()
            }

            Spacer().frame(height: 16)

            // Status bar
            Divider().background(Color(nsColor: NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)))
            HStack {
                Text(manager.status)
                    .font(monoFont)
                    .foregroundColor(Color(nsColor: manager.statusColor))
                Spacer()
                if manager.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 440, height: 520)
        .background(bgColor)
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                manager.scan()
            }
        }
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(headerFont)
            .foregroundColor(dimColor)
            .padding(.bottom, 4)
    }

    func itemRow(_ item: GoogleItem) -> some View {
        let idx = manager.items.firstIndex(where: { $0.id == item.id })!
        return HStack(spacing: 8) {
            if item.isRemoved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(greenColor)
                    .frame(width: 16)
                Text(item.name)
                    .font(monoFont)
                    .foregroundColor(greenColor)
                Text("removed")
                    .font(monoFont)
                    .foregroundColor(greenColor)
            } else if !item.isFound {
                Image(systemName: "circle")
                    .foregroundColor(Color(nsColor: NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)))
                    .frame(width: 16)
                Text(item.name)
                    .font(monoFont)
                    .foregroundColor(Color(nsColor: NSColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1)))
                Text(item.detail)
                    .font(monoFont)
                    .foregroundColor(Color(nsColor: NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)))
            } else if item.isTogglable {
                Toggle(isOn: Binding(
                    get: { manager.items[idx].isSelected },
                    set: { manager.items[idx].isSelected = $0 }
                )) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(monoFont)
                            .foregroundColor(textColor)
                        if !item.detail.isEmpty {
                            Text("(\(item.detail))")
                                .font(monoFont)
                                .foregroundColor(dimColor)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(manager.isWorking)
            } else {
                Toggle(isOn: .constant(true)) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(monoFont)
                            .foregroundColor(textColor)
                        if !item.detail.isEmpty {
                            Text("(\(item.detail))")
                                .font(monoFont)
                                .foregroundColor(dimColor)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(true)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - App Entry

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isRestorable = false
        window.center()
        window.title = "Remove Google"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
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
