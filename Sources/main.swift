import Cocoa

let version = "1.2.1"
let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/dark-scripter")
let stateDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".local/state/dark-scripter")
let lastRunFile = stateDir.appendingPathComponent("last-run.json")

// MARK: - Data model

struct ScriptResult: Codable {
    let name: String
    let exitCode: Int?
    let error: String?
    let durationMs: Int

    enum CodingKeys: String, CodingKey {
        case name
        case exitCode = "exit_code"
        case error
        case durationMs = "duration_ms"
    }
}

struct RunLog: Codable {
    let timestamp: String
    let mode: String
    let scripts: [ScriptResult]
}

// MARK: - Last-run subcommand

func showLastRun(asJSON: Bool) {
    let fm = FileManager.default
    guard fm.fileExists(atPath: lastRunFile.path) else {
        print("No runs recorded yet.")
        exit(0)
    }

    guard let data = fm.contents(atPath: lastRunFile.path) else {
        fputs("dark-scripter: could not read \(lastRunFile.path)\n", stderr)
        exit(1)
    }

    if asJSON {
        print(String(data: data, encoding: .utf8) ?? "")
        exit(0)
    }

    let decoder = JSONDecoder()
    guard let log = try? decoder.decode(RunLog.self, from: data) else {
        fputs("dark-scripter: could not parse \(lastRunFile.path)\n", stderr)
        exit(1)
    }

    let modeLabel = log.mode == "dark" ? "dark mode" : "light mode"
    print("Last run: \(log.timestamp) (\(modeLabel))")

    for script in log.scripts {
        let duration = "\(script.durationMs)ms"
        if let error = script.error {
            print("  FAIL  \(script.name)  \(error)  \(duration)")
        } else if let code = script.exitCode, code != 0 {
            print("  FAIL  \(script.name)  exit \(code)  \(duration)")
        } else {
            print("  ok    \(script.name)  \(duration)")
        }
    }

    exit(0)
}

// MARK: - Write run log

func writeRunLog(mode: String, results: [ScriptResult]) {
    let fm = FileManager.default

    if !fm.fileExists(atPath: stateDir.path) {
        try? fm.createDirectory(at: stateDir, withIntermediateDirectories: true)
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let log = RunLog(
        timestamp: formatter.string(from: Date()),
        mode: mode,
        scripts: results
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(log) else { return }
    fm.createFile(atPath: lastRunFile.path, contents: data)
}

// MARK: - CLI routing

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("dark-scripter v\(version)")
    print("Runs scripts in ~/.config/dark-scripter/ when macOS appearance changes.")
    print("")
    print("Each executable file in the config directory is run with DARKMODE=1 (dark)")
    print("or DARKMODE=0 (light) set in the environment. Scripts run in alphabetical order.")
    print("Files starting with _ are skipped, so you can use them as helpers called by other scripts.")
    print("")
    print("Usage: dark-scripter [command] [--help] [--version]")
    print("")
    print("Commands:")
    print("  last-run          Show results of the most recent script run")
    print("  last-run --json   Output last run results as JSON")
    print("")
    print("With no command, starts listening for appearance changes.")
    exit(0)
}
if CommandLine.arguments.contains("--version") || CommandLine.arguments.contains("-v") {
    print(version)
    exit(0)
}
if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "last-run" {
    let asJSON = CommandLine.arguments.contains("--json")
    showLastRun(asJSON: asJSON)
}

// MARK: - Daemon mode

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

    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    var results: [ScriptResult] = []

    for script in scripts {
        let path = configDir.appendingPathComponent(script).path
        guard !script.hasPrefix("_"), fm.isExecutableFile(atPath: path) else { continue }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "DARKMODE=\(mode) exec \(path)"]
        process.currentDirectoryURL = configDir
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        let start = Date()

        do {
            try process.run()
            process.waitUntilExit()
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)

            if process.terminationStatus != 0 {
                fputs("dark-scripter: \(script) exited with status \(process.terminationStatus)\n", stderr)
            }

            results.append(ScriptResult(
                name: script,
                exitCode: Int(process.terminationStatus),
                error: nil,
                durationMs: durationMs
            ))
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            fputs("dark-scripter: failed to run \(script): \(error.localizedDescription)\n", stderr)

            results.append(ScriptResult(
                name: script,
                exitCode: nil,
                error: error.localizedDescription,
                durationMs: durationMs
            ))
        }
    }

    let modeLabel = dark ? "dark" : "light"
    writeRunLog(mode: modeLabel, results: results)
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
