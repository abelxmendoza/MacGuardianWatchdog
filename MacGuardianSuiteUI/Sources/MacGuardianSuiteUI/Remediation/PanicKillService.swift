import Foundation

extension Notification.Name {
    /// Posted whenever a panic-kill run finishes, regardless of whether it
    /// was triggered from the in-app button or the menu-bar item, so any
    /// visible PanicKillerView can refresh without polling.
    static let panicKillCompleted = Notification.Name("com.macguardian.panicKillCompleted")
}

class PanicKillService {
    static let shared = PanicKillService()

    private let repositoryPath: String
    private let sessionsDir: URL

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        repositoryPath = "\(homeDir)/Desktop/MacGuardianProject"
        sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".macguardian")
            .appendingPathComponent("panic_sessions")
    }

    /// Runs the panic-kill script: terminates every live node/npm/npx/corepack
    /// process on the machine and returns what was killed.
    func runPanicKill() async -> Result<PanicKillSession, PanicKillError> {
        let scriptPath = "\(repositoryPath)/MacGuardianSuite/remediation/node_panic_kill.sh"

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return .failure(.scriptNotFound)
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [scriptPath]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()

                    guard let session = try? JSONDecoder().decode(PanicKillSession.self, from: data) else {
                        let output = String(data: data, encoding: .utf8) ?? ""
                        let result: Result<PanicKillSession, PanicKillError> = .failure(.invalidOutput(output))
                        NotificationCenter.default.post(name: .panicKillCompleted, object: nil, userInfo: ["result": result])
                        continuation.resume(returning: result)
                        return
                    }

                    let result: Result<PanicKillSession, PanicKillError> = .success(session)
                    NotificationCenter.default.post(name: .panicKillCompleted, object: nil, userInfo: ["result": result])
                    continuation.resume(returning: result)
                } catch {
                    let result: Result<PanicKillSession, PanicKillError> = .failure(.launchFailed(error.localizedDescription))
                    NotificationCenter.default.post(name: .panicKillCompleted, object: nil, userInfo: ["result": result])
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Loads every past panic-kill session from disk, newest first.
    func loadSessions() -> [PanicKillSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        let sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> PanicKillSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(PanicKillSession.self, from: data)
            }

        return sessions.sorted { $0.date > $1.date }
    }

    /// Best-effort relaunch of a previously killed process: same resolved
    /// binary, same argv[1:], same working directory. This is recovery, not
    /// a guarantee - if the original process depended on in-memory state,
    /// open sockets, or a parent process, this only restarts the binary.
    func relaunch(_ entry: KilledProcessEntry) -> Result<Void, PanicKillError> {
        var executablePath = entry.path
        if !executablePath.hasPrefix("/") {
            executablePath = URL(fileURLWithPath: entry.cwd)
                .appendingPathComponent(executablePath).path
        }

        guard FileManager.default.fileExists(atPath: executablePath) else {
            return .failure(.binaryNoLongerExists(executablePath))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = entry.args

        if !entry.cwd.isEmpty, FileManager.default.fileExists(atPath: entry.cwd) {
            process.currentDirectoryURL = URL(fileURLWithPath: entry.cwd)
        }

        // Detach: this should keep running as its own background process,
        // independent of MacGuardianSuiteUI's own lifecycle.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            return .success(())
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }
    }
}

enum PanicKillError: Error, LocalizedError {
    case scriptNotFound
    case launchFailed(String)
    case invalidOutput(String)
    case binaryNoLongerExists(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "The panic-kill script could not be found in the repository."
        case .launchFailed(let message):
            return "Failed to launch: \(message)"
        case .invalidOutput(let output):
            return "Panic-kill script returned unexpected output: \(output.prefix(300))"
        case .binaryNoLongerExists(let path):
            return "Cannot relaunch - the binary no longer exists at \(path)."
        }
    }
}
