import Cocoa

let version = "1.1.0"
let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/dark-scripter")

// CLI flags
if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("dark-scripter v\(version)")
    print("Runs scripts in ~/.config/dark-scripter/ when macOS appearance changes.")
    print("")
    print("Each executable file in the config directory is run with DARKMODE=1 (dark)")
    print("or DARKMODE=0 (light) set in the environment. Scripts run in alphabetical order.")
    print("Files starting with _ are skipped, so you can use them as helpers called by other scripts.")
    print("")
    print("Usage: dark-scripter [--help] [--version]")
    exit(0)
}
if CommandLine.arguments.contains("--version") || CommandLine.arguments.contains("-v") {
    print(version)
    exit(0)
}

// State tracking for debouncing
nonisolated(unsafe) var lastMode: String?

func isDarkMode() -> Bool {
    UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
}

func runScripts() {
    let dark = isDarkMode()
    let mode = dark ? "1" : "0"

    // Debounce: skip if appearance hasn't changed
    if mode == lastMode { return }
    lastMode = mode

    let fm = FileManager.default
    guard fm.fileExists(atPath: configDir.path) else {
        fputs("dark-scripter: config directory not found at \(configDir.path)\n", stderr)
        fputs("dark-scripter: create it and add executable scripts to get started\n", stderr)
        return
    }

    guard let entries = try? fm.contentsOfDirectory(atPath: configDir.path) else {
        return
    }
    let scripts = entries.sorted()

    var env = ProcessInfo.processInfo.environment
    env["DARKMODE"] = mode

    for script in scripts {
        let path = configDir.appendingPathComponent(script).path
        guard !script.hasPrefix("_"), fm.isExecutableFile(atPath: path) else { continue }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.environment = env
        process.currentDirectoryURL = configDir
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                fputs("dark-scripter: \(script) exited with status \(process.terminationStatus)\n", stderr)
            }
        } catch {
            fputs("dark-scripter: failed to run \(script): \(error.localizedDescription)\n", stderr)
        }
    }
}

// Suppress Dock icon
NSApplication.shared.setActivationPolicy(.prohibited)

// Listen for appearance changes
DistributedNotificationCenter.default.addObserver(
    forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
    object: nil, queue: .main
) { _ in runScripts() }

// Listen for wake to catch time-based auto-switching
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification,
    object: nil, queue: .main
) { _ in runScripts() }

// Run once on startup
runScripts()

// Keep alive
NSApplication.shared.run()
