import Foundation
import Combine

/// Finds the MacGuardian project folder (the one containing MacGuardianSuite/).
/// Order: the path chosen in Settings, then the folder the app was built from
/// (build_app.sh writes it into Info.plist), then ~/Desktop/MacGuardianProject.
enum RepoLocator {
    static let defaultsKey = "repositoryPath"

    static var path: String {
        let candidates: [String?] = [
            UserDefaults.standard.string(forKey: defaultsKey),
            Bundle.main.object(forInfoDictionaryKey: "MGRepositoryPath") as? String,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/MacGuardianProject").path
        ]
        for case let candidate? in candidates where isProject(candidate) {
            return candidate
        }
        return candidates.compactMap { $0 }.first ?? ""
    }

    /// Absolute path of something inside the project, e.g. "MacGuardianSuite/mac_guardian.sh".
    static func resolve(_ relativePath: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .appendingPathComponent(relativePath).path
    }

    private static func isProject(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: "\(expanded)/MacGuardianSuite")
    }
}

/// Global app state that stores the workspace path and currently selected items.
final class WorkspaceState: ObservableObject {
    @Published var repositoryPath: String {
        didSet {
            UserDefaults.standard.set(repositoryPath, forKey: RepoLocator.defaultsKey)
        }
    }
    @Published var hasSeenWelcome: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenWelcome, forKey: "hasSeenWelcome")
        }
    }
    @Published var selectedView: AppView = .dashboard
    @Published var auditSection: AuditSection = .posture
    @Published var incidentsSection: IncidentsSection = .incidents
    @Published var fixSection: FixSection = .remediation
    @Published var cleanerSection: CleanerSection = .caches
    @Published var reportEmail: String = ""
    @Published var smtpUsername: String = ""
    @Published var smtpPassword: String = "" {
        didSet {
            // Don't store password in UserDefaults - use Keychain instead
            // This is handled in SettingsView
        }
    }

    init(defaultPath: String = RepoLocator.path) {
        self.repositoryPath = defaultPath
        self.hasSeenWelcome = true
        self.reportEmail = UserDefaults.standard.string(forKey: "reportEmail") ?? ""
        self.smtpUsername = UserDefaults.standard.string(forKey: "smtpUsername") ?? ""
        
        // Load password from Keychain if available
        if let password = SecureStorage.shared.getPassword(forKey: "smtpPassword") {
            self.smtpPassword = password
        }
        
        runSelfCheck()
    }

    /// Result of MacGuardian checking its own scripts, app and background jobs.
    struct SelfCheckResult {
        let passed: Bool
        let summary: String
        let problems: [String]
    }
    @Published var selfCheck: SelfCheckResult?

    /// Runs MacGuardianSuite/self_check.sh in the background (at launch and on demand).
    func runSelfCheck() {
        let script = "\(repositoryPath)/MacGuardianSuite/self_check.sh"
        guard FileManager.default.fileExists(atPath: script) else {
            selfCheck = SelfCheckResult(passed: false,
                                        summary: "Self-check script not found",
                                        problems: ["Check the project folder in Settings, or run install.sh again."])
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script]
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            guard (try? process.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let lines = (String(data: data, encoding: .utf8) ?? "").components(separatedBy: "\n")
            let summary = lines.last(where: { $0.hasPrefix("Summary:") })?
                .replacingOccurrences(of: "Summary: ", with: "") ?? "No result"
            let problems = lines.filter { $0.hasPrefix("FAIL") || $0.hasPrefix("WARN") }
                .map { String($0.dropFirst(6)) }
            let result = SelfCheckResult(passed: process.terminationStatus == 0,
                                         summary: summary, problems: problems)
            DispatchQueue.main.async { self.selfCheck = result }
        }
    }

    func resolve(path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        let expanded = (repositoryPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).appendingPathComponent(path).path
    }

    func validateRepositoryPath() -> (isValid: Bool, message: String) {
        let expanded = (repositoryPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory)
        
        if !exists {
            return (false, "Repository path does not exist. Please select a valid MacGuardian project folder.")
        }
        
        if !isDirectory.boolValue {
            return (false, "Repository path is not a directory. Please select a folder, not a file.")
        }
        
        // Check if it looks like a MacGuardian project
        let macSuitePath = url.appendingPathComponent("MacGuardianSuite").path
        let hasMacSuite = FileManager.default.fileExists(atPath: macSuitePath)
        
        if !hasMacSuite {
            return (false, "This doesn't appear to be a MacGuardian project folder. Make sure it contains the MacGuardianSuite directory.")
        }
        
        return (true, "Repository path is valid")
    }
    
    /// Load reports from the reports directory
    func loadReports() -> [ReportFile] {
        let reportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".macguardian")
            .appendingPathComponent("reports")
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: reportDir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]) else {
            return []
        }
        
        return files
            .filter { $0.pathExtension == "html" || $0.pathExtension == "txt" || $0.pathExtension == "json" }
            .compactMap { url in
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let date = attributes[.creationDate] as? Date,
                      let size = attributes[.size] as? Int64 else {
                    return nil
                }
                return ReportFile(url: url, date: date, size: size)
            }
            .sorted { $0.date > $1.date }
    }
}

/// Top-level tabs. Kept short on purpose: one tab per job, mirroring the
/// LinuxGuardian layout. Related screens live inside a tab as sections.
enum AppView: String, CaseIterable {
    case dashboard = "Dashboard"
    case audit = "Audit"
    case threats = "Threats"
    case incidents = "Incidents"
    case fix = "Fix"
    case processes = "Processes"
    case cleaner = "Cleaner"
    case reports = "Reports"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .audit: return "checkmark.shield.fill"
        case .threats: return "shield.lefthalf.filled"
        case .incidents: return "exclamationmark.triangle.fill"
        case .fix: return "wrench.and.screwdriver.fill"
        case .processes: return "xmark.circle.fill"
        case .cleaner: return "trash.fill"
        case .reports: return "doc.text.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// A screen shown inside a tab, picked with a segmented control.
protocol TabSection: Hashable, CaseIterable, RawRepresentable where RawValue == String, AllCases: RandomAccessCollection {}

enum AuditSection: String, TabSection {
    case posture = "Posture"
    case integrity = "File Integrity"
    case selfCheck = "Self-Check"
    case ssh = "SSH"
    case users = "User Accounts"
    case privacy = "Privacy"
}

enum IncidentsSection: String, TabSection {
    case incidents = "Incidents"
    case timeline = "Timeline"
}

enum FixSection: String, TabSection {
    case remediation = "Remediation"
    case panicKill = "Panic Kill"
}

enum CleanerSection: String, TabSection {
    case caches = "System & Browser"
    case cursor = "Cursor"
    case appIcons = "App Icons"
}

/// Report file model
struct ReportFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let date: Date
    let size: Int64
    
    var name: String { url.lastPathComponent }
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
