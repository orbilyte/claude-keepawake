import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let uid = String(getuid())
    private let agentLabel = "com.claude-keepawake.agent"
    private let agentPlist: String
    private let uiLabel = "com.claude-keepawake.menu"
    private let logPath: String
    private var manualProc: Process?

    private let appVersion: String = {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return " v\(v)"
        }
        return ""
    }()

    private struct Snapshot {
        var awake = false
        var ac = true
        var agent = true
        var clamshell = false
        var login = true
        var fetched = Date.distantPast
    }
    private var snap = Snapshot()
    private var refreshing = false
    private let stateQueue = DispatchQueue(label: "claude-keepawake.state", qos: .userInitiated)

    private var statusLine: NSMenuItem!
    private var powerLine: NSMenuItem!
    private var autoItem: NSMenuItem!
    private var manualItem: NSMenuItem!
    private var clamItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    override init() {
        let home = NSHomeDirectory()
        agentPlist = home + "/Library/LaunchAgents/com.claude-keepawake.agent.plist"
        logPath = home + "/.local/state/claude-keepawake/agent.log"
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if peers.count > 1 {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "KeepAwake"
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = iconImage(filled: false) ?? NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "Claude KeepAwake")
            if button.image == nil { button.title = "☕︎" }
            button.toolTip = "Claude KeepAwake"
        }
        menu.delegate = self
        statusItem.menu = menu
        buildMenu()
        applySnapshot()
        refreshState(force: true)
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
    }

    private func buildMenu() {
        let title = NSMenuItem(title: "Claude KeepAwake" + appVersion, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        statusLine = NSMenuItem(title: "Status: …", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        powerLine = NSMenuItem(title: "Power: …", action: nil, keyEquivalent: "")
        powerLine.isEnabled = false
        menu.addItem(powerLine)

        menu.addItem(.separator())

        autoItem = NSMenuItem(
            title: "Automatic – stay awake while Claude / dev servers run",
            action: #selector(toggleAgent), keyEquivalent: "")
        autoItem.target = self
        menu.addItem(autoItem)

        manualItem = NSMenuItem(
            title: "Stay awake now (unlimited, AC only)",
            action: #selector(toggleManual), keyEquivalent: "")
        manualItem.target = self
        menu.addItem(manualItem)

        clamItem = NSMenuItem(
            title: "Clamshell mode – keep running with lid closed (AC only)",
            action: #selector(toggleClamshell), keyEquivalent: "")
        clamItem.target = self
        menu.addItem(clamItem)

        menu.addItem(.separator())

        let logItem = NSMenuItem(title: "Open log in Console", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func applySnapshot() {
        let statusTitle = snap.awake ? "Status: Mac is being kept awake" : "Status: sleep allowed"
        if statusLine.title != statusTitle { statusLine.title = statusTitle }
        let powerTitle = snap.ac ? "Power: AC adapter" : "Power: battery"
        if powerLine.title != powerTitle { powerLine.title = powerTitle }
        let autoState: NSControl.StateValue = snap.agent ? .on : .off
        if autoItem.state != autoState { autoItem.state = autoState }
        let manualState: NSControl.StateValue = (manualProc?.isRunning ?? false) ? .on : .off
        if manualItem.state != manualState { manualItem.state = manualState }
        let clamState: NSControl.StateValue = snap.clamshell ? .on : .off
        if clamItem.state != clamState { clamItem.state = clamState }
        let loginState: NSControl.StateValue = snap.login ? .on : .off
        if loginItem.state != loginState { loginItem.state = loginState }
        refreshIcon()
    }

    private func refreshState(force: Bool = false) {
        if !force, Date().timeIntervalSince(snap.fetched) < 3 { return }
        guard !refreshing else { return }
        refreshing = true
        stateQueue.async { [weak self] in
            guard let self else { return }
            var s = self.snap
            s.awake = self.shell(["/usr/bin/pgrep", "-x", "caffeinate"]) == 0
            s.ac = (self.shellOut(["/usr/bin/pmset", "-g", "batt"]) ?? "").contains("AC Power")
            s.agent = self.shell(["/bin/launchctl", "print", "gui/\(self.uid)/\(self.agentLabel)"]) == 0
            s.clamshell = Self.parseClamshell(self.shellOut(["/usr/bin/pmset", "-g"]) ?? "")
            s.login = Self.parseLogin(self.shellOut(["/bin/launchctl", "print-disabled", "gui/\(self.uid)"]) ?? "", label: self.uiLabel)
            s.fetched = Date()
            DispatchQueue.main.async {
                self.snap = s
                self.refreshing = false
                self.applySnapshot()
            }
        }
    }

    private static func parseClamshell(_ out: String) -> Bool {
        var found = false
        for raw in out.split(separator: "\n") {
            let t = String(raw).trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("SleepDisabled") || t.hasPrefix("disablesleep") {
                found = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).last == "1"
            }
        }
        return found
    }

    private static func parseLogin(_ out: String, label: String) -> Bool {
        for line in out.split(separator: "\n") {
            if line.contains(label) { return !line.contains("true") }
        }
        return true
    }

    private func shell(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch { return -1 }
    }

    private func shellOut(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }

    @objc private func toggleAgent() {
        let loaded = shell(["/bin/launchctl", "print", "gui/\(uid)/\(agentLabel)"]) == 0
        if loaded {
            shell(["/bin/launchctl", "bootout", "gui/\(uid)/\(agentLabel)"])
        } else {
            shell(["/bin/launchctl", "bootstrap", "gui/\(uid)", agentPlist])
        }
        refreshState(force: true)
    }

    @objc private func toggleManual() {
        if let p = manualProc, p.isRunning {
            p.terminate()
            manualProc = nil
        } else {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-s"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do {
                try p.run()
                manualProc = p
            } catch {
                NSSound.beep()
            }
        }
        applySnapshot()
        refreshState(force: true)
    }

    @objc private func toggleClamshell() {
        let current = Self.parseClamshell(shellOut(["/usr/bin/pmset", "-g"]) ?? "")
        let args = current ? "-a disablesleep 0" : "-c disablesleep 1"
        let script = "do shell script \"/usr/bin/pmset \(args)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        p.standardError = errPipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            if let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
                appendLog("clamshell error (\(p.terminationStatus)): \(msg)")
                NSSound.beep()
            } else if p.terminationStatus != 0 {
                appendLog("clamshell error: osascript exit \(p.terminationStatus)")
                NSSound.beep()
            } else {
                appendLog("clamshell toggled: pmset \(args)")
            }
        } catch {
            appendLog("clamshell error: osascript failed to start (\(error))")
            NSSound.beep()
        }
        refreshState(force: true)
    }

    @objc private func toggleLoginItem() {
        if loginItemEnabledNow() {
            shell(["/bin/launchctl", "disable", "gui/\(uid)/\(uiLabel)"])
        } else {
            shell(["/bin/launchctl", "enable", "gui/\(uid)/\(uiLabel)"])
        }
        refreshState(force: true)
    }

    private func loginItemEnabledNow() -> Bool {
        Self.parseLogin(shellOut(["/bin/launchctl", "print-disabled", "gui/\(uid)"]) ?? "", label: uiLabel)
    }

    @objc private func openLog() {
        shell(["/usr/bin/open", "-a", "Console", logPath])
    }

    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dir = (logPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let entry = formatter.string(from: Date()) + " " + line + "\n"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? entry.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }

    @objc private func quitApp() {
        if let p = manualProc, p.isRunning { p.terminate() }
        NSApp.terminate(nil)
    }

    private var isDarkMode: Bool {
        if let match = NSApp.effectiveAppearance.bestMatch(from: [NSAppearance.Name.darkAqua, NSAppearance.Name.aqua]) {
            return match == .darkAqua
        }
        return true
    }

    private func iconImage(filled: Bool) -> NSImage? {
        let name = filled ? "cup.and.saucer.fill" : "cup.and.saucer"
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let color: NSColor = isDarkMode ? .white : .black
        let cfg = NSImage.SymbolConfiguration(paletteColors: [color])
        let img = symbol.withSymbolConfiguration(cfg)
        img?.isTemplate = false
        return img
    }

    private var lastIconKey = ""

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let key = (snap.awake ? "1" : "0") + (isDarkMode ? "d" : "l")
        if key == lastIconKey { return }
        lastIconKey = key
        if let img = iconImage(filled: snap.awake) {
            button.image = img
        } else {
            button.title = snap.awake ? "☕️" : "☕︎"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        applySnapshot()
    }

    func menuDidClose(_ menu: NSMenu) {
        refreshState()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
