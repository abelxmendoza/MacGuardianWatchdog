import Foundation

struct KilledProcessEntry: Codable, Identifiable, Hashable {
    let pid: Int
    let ppid: Int
    let path: String
    let args: [String]
    let fullCommand: String
    let cwd: String
    let signalSequence: String
    let terminated: Bool

    var id: String { "\(pid)-\(path)" }

    enum CodingKeys: String, CodingKey {
        case pid, ppid, path, args, cwd, terminated
        case fullCommand = "full_command"
        case signalSequence = "signal_sequence"
    }

    var canRelaunch: Bool {
        !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }
}

struct PanicKillSession: Codable, Identifiable, Hashable {
    let sessionId: String
    let timestamp: String
    let killedCount: Int
    let killed: [KilledProcessEntry]

    var id: String { sessionId }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case timestamp
        case killedCount = "killed_count"
        case killed
    }

    var date: Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: timestamp) ?? Date.distantPast
    }
}
