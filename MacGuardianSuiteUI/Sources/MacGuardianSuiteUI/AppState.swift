import Foundation
import Combine

/// Represents a runnable script or module in the MacGuardian suite.
struct SuiteTool: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Codable {
        case shell
        case python
    }

    enum SafetyLevel: String, CaseIterable {
        case safe = "Safe"
        case caution = "Caution"
        case destructive = "Destructive"
        
        var description: String {
            switch self {
            case .safe:
                return "Read-only operations. No files will be modified or deleted."
            case .caution:
                return "May modify system settings or clean temporary files. Generally safe."
            case .destructive:
                return "⚠️ Can delete files, kill processes, or make permanent changes. Use with caution!"
            }
        }
        
        var icon: String {
            switch self {
            case .safe: return "checkmark.shield"
            case .caution: return "exclamationmark.triangle"
            case .destructive: return "exclamationmark.triangle.fill"
            }
        }
    }
    
    enum ExecutionMode: String {
        case ui = "UI"
        case terminal = "Terminal"
        case terminalRecommended = "Terminal Recommended"
        
        var description: String {
            switch self {
            case .ui:
                return "Can be run from the UI"
            case .terminal:
                return "Must be run from Terminal (requires sudo or interactive input)"
            case .terminalRecommended:
                return "Recommended to run from Terminal for full functionality and security"
            }
        }
        
        var icon: String {
            switch self {
            case .ui: return "app.window"
            case .terminal: return "terminal.fill"
            case .terminalRecommended: return "terminal"
            }
        }
    }

    let id = UUID()
    let name: String
    let description: String
    let relativePath: String
    let kind: Kind
    let arguments: [String]
    let requiresSudo: Bool
    let safetyLevel: SafetyLevel
    let destructiveOperations: [String] // List of what this script might do
    let executionMode: ExecutionMode

    init(
        name: String,
        description: String,
        relativePath: String,
        kind: Kind = .shell,
        arguments: [String] = [],
        requiresSudo: Bool = false,
        safetyLevel: SafetyLevel = .safe,
        destructiveOperations: [String] = [],
        executionMode: ExecutionMode = .ui
    ) {
        self.name = name
        self.description = description
        self.relativePath = relativePath
        self.kind = kind
        self.arguments = arguments
        self.requiresSudo = requiresSudo
        self.safetyLevel = safetyLevel
        self.destructiveOperations = destructiveOperations
        self.executionMode = executionMode
    }

    func commandLine(using workspace: WorkspaceState) -> [String] {
        var resolvedPath = workspace.resolve(path: relativePath)
        if requiresSudo {
            resolvedPath = "sudo " + resolvedPath
        }
        let command = [workspace.interpreter(for: self), resolvedPath] + arguments
        if requiresSudo {
            return ["/bin/zsh", "-lc", (["sudo", resolvedPath] + arguments).joined(separator: " ")]
        }
        return command
    }
}

/// Logical grouping for tools, used for the navigation sidebar.
struct SuiteCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let description: String
    let tools: [SuiteTool]
}

/// Global app state that stores the workspace path and currently selected items.
final class WorkspaceState: ObservableObject {
    @Published var repositoryPath: String
    @Published var selectedCategory: SuiteCategory?
    @Published var selectedTool: SuiteTool?
    @Published var execution: CommandExecution?
    @Published var hasSeenWelcome: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenWelcome, forKey: "hasSeenWelcome")
        }
    }
    @Published var safeMode: Bool {
        didSet {
            UserDefaults.standard.set(safeMode, forKey: "safeMode")
        }
    }
    @Published var showSafetyConfirmation: Bool = false
    @Published var pendingExecution: (() -> Void)? = nil
    @Published var executionHistory: [CommandExecution] = []
    @Published var selectedView: AppView = .tools
    @Published var showProcessKiller: Bool = false
    @Published var showCacheCleaner: Bool = false
    @Published var showCursorCacheCleaner: Bool = false
    @Published var showSidebar: Bool = true {
        didSet {
            UserDefaults.standard.set(showSidebar, forKey: "showSidebar")
        }
    }
    @Published var reportEmail: String = ""
    @Published var smtpUsername: String = ""
    @Published var smtpPassword: String = "" {
        didSet {
            // Don't store password in UserDefaults - use Keychain instead
            // This is handled in SettingsView
        }
    }

    init(defaultPath: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop")
        .appendingPathComponent("MacGuardianProject").path) {
        self.repositoryPath = defaultPath
        self.hasSeenWelcome = true
        self.safeMode = UserDefaults.standard.object(forKey: "safeMode") as? Bool ?? true
        self.showSidebar = UserDefaults.standard.object(forKey: "showSidebar") as? Bool ?? true
        self.reportEmail = UserDefaults.standard.string(forKey: "reportEmail") ?? ""
        self.smtpUsername = UserDefaults.standard.string(forKey: "smtpUsername") ?? ""
        
        // Load password from Keychain if available
        if let password = SecureStorage.shared.getPassword(forKey: "smtpPassword") {
            self.smtpPassword = password
        }
        
        // Verify integrity of critical files on startup
        verifyAppIntegrity()
    }
    
    /// Verify integrity of critical app files
    private func verifyAppIntegrity() {
        let results = IntegrityVerifier.shared.verifyCriticalFiles(repositoryPath: repositoryPath)
        
        var hasIssues = false
        for (file, result) in results {
            if !result.isValid {
                hasIssues = true
                print("⚠️ Integrity check failed for \(file): \(result.message)")
            }
        }
        
        if hasIssues {
            // Log to audit trail
            print("🔒 Security Warning: Some files failed integrity verification")
        }
    }

    func resolve(path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        let expanded = (repositoryPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).appendingPathComponent(path).path
    }

    func interpreter(for tool: SuiteTool) -> String {
        switch tool.kind {
        case .shell:
            return "/bin/zsh"
        case .python:
            return "/usr/bin/python3"
        }
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
    
    func checkScriptExists(for tool: SuiteTool) -> Bool {
        // UI-only tools don't have script paths
        if tool.relativePath.isEmpty {
            return true
        }
        let scriptPath = resolve(path: tool.relativePath)
        return FileManager.default.fileExists(atPath: scriptPath)
    }
    
    /// Check if a tool requires safety confirmation before running
    func requiresSafetyConfirmation(for tool: SuiteTool) -> Bool {
        // In safe mode, require confirmation for caution and destructive operations
        if safeMode {
            return tool.safetyLevel == .caution || tool.safetyLevel == .destructive
        }
        // Only require confirmation for destructive operations when safe mode is off
        return tool.safetyLevel == .destructive
    }
    
    /// Request confirmation before running a potentially dangerous tool
    func requestSafetyConfirmation(for tool: SuiteTool, execute: @escaping () -> Void) {
        if requiresSafetyConfirmation(for: tool) {
            pendingExecution = execute
            showSafetyConfirmation = true
        } else {
            execute()
        }
    }
    
    /// Add execution to history
    func addToHistory(_ execution: CommandExecution) {
        executionHistory.insert(execution, at: 0)
        // Keep only last 100 executions
        if executionHistory.count > 100 {
            executionHistory = Array(executionHistory.prefix(100))
        }
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

/// App view navigation
enum AppView: String, CaseIterable {
    case dashboard = "Dashboard"
    case tools = "Tools"
    case threatIntelligence = "Threat Intel"
    case blueTeam = "Blue Team"
    case securityAudit = "Security Audit"
    case remediation = "Remediation"
    case omegaGuardian = "Omega Guardian"
    case realTimeMonitor = "Real-Time Monitor"
    case reports = "Reports"
    case history = "History"
    case security = "Security"
    case settings = "Settings"
    case sshSecurity = "SSH Security"
    case userAccountSecurity = "User Accounts"
    case privacyHeatmap = "Privacy"
    case networkGraph = "Network Graph"
    case incidentTimeline = "Timeline"
    
    var icon: String {
        switch self {
        case .threatIntelligence:
            return "shield.lefthalf.filled"
        case .blueTeam: return "shield.lefthalf.filled"
        case .securityAudit: return "checkmark.shield.fill"
        case .remediation: return "wrench.and.screwdriver.fill"
        case .omegaGuardian: return "shield.lefthalf.filled"
        case .realTimeMonitor: return "waveform.path.ecg"
        case .dashboard: return "chart.bar.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .reports: return "doc.text.fill"
        case .history: return "clock.fill"
        case .security: return "shield.checkered.fill"
        case .settings: return "gearshape.fill"
        case .sshSecurity: return "key.fill"
        case .userAccountSecurity: return "person.2.fill"
        case .privacyHeatmap: return "hand.raised.fill"
        case .networkGraph: return "network"
        case .incidentTimeline: return "clock.fill"
        }
    }
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

/// Represents an execution request and its mutable progress state.
final class CommandExecution: ObservableObject, Identifiable, Hashable {
    static func == (lhs: CommandExecution, rhs: CommandExecution) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    enum State: Equatable {
        case idle
        case running
        case finished(Int32)
        case failed(String)
    }

    let id = UUID()
    let tool: SuiteTool
    @Published var log: String
    @Published var state: State
    @Published var startedAt: Date
    @Published var finishedAt: Date?

    init(tool: SuiteTool) {
        self.tool = tool
        self.log = ""
        self.state = .idle
        self.startedAt = Date()
        self.finishedAt = nil
    }
}

/// Bridges Process output into published updates for SwiftUI.
final class ShellCommandRunner {
    func run(tool: SuiteTool, workspace: WorkspaceState) -> CommandExecution {
        print("🟢 ShellCommandRunner.run() called")
        print("   Tool: \(tool.name)")
        print("   Path: \(tool.relativePath)")
        
        let execution = CommandExecution(tool: tool)
        execution.state = .running
        execution.startedAt = Date()
        
        // Add initial log message with debug info
        let resolvedPath = workspace.resolve(path: tool.relativePath)
        execution.log = "🚀 Starting execution...\n"
        execution.log.append("📁 Repository: \(workspace.repositoryPath)\n")
        execution.log.append("📜 Script: \(tool.relativePath)\n")
        execution.log.append("📍 Resolved Path: \(resolvedPath)\n")
        execution.log.append("🔍 Checking script existence...\n\n")
        
        print("🟢 Execution object created with ID: \(execution.id)")

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Set working directory to repository path
            let expandedPath = (workspace.repositoryPath as NSString).expandingTildeInPath
            let workingDirURL = URL(fileURLWithPath: expandedPath)
            
            // Validate working directory exists
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory) || !isDirectory.boolValue {
                DispatchQueue.main.async {
                    execution.state = .failed("Invalid repository path")
                    execution.finishedAt = Date()
                    execution.log.append("❌ Error: Repository path does not exist or is not a directory:\n\(expandedPath)\n")
                }
                return
            }
            
            process.currentDirectoryURL = workingDirURL
            
            // Set environment variables
            var env = Foundation.ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["SHELL"] = "/bin/zsh"
            process.environment = env
            
            DispatchQueue.main.async {
                execution.log.append("✅ Working directory set: \(expandedPath)\n")
            }

            switch tool.kind {
            case .shell:
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                let resolvedPath = workspace.resolve(path: tool.relativePath)
                
                DispatchQueue.main.async {
                    execution.log.append("🔍 Checking script: \(resolvedPath)\n")
                }
                
                // Make sure script is executable
                if !fileManager.fileExists(atPath: resolvedPath) {
                    DispatchQueue.main.async {
                        execution.state = .failed("Script not found")
                        execution.finishedAt = Date()
                        execution.log.append("❌ Error: Script not found at path:\n\(resolvedPath)\n\n")
                        execution.log.append("💡 Debug Info:\n")
                        execution.log.append("   - Repository: \(workspace.repositoryPath)\n")
                        execution.log.append("   - Relative Path: \(tool.relativePath)\n")
                        execution.log.append("   - Resolved: \(resolvedPath)\n")
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    execution.log.append("✅ Script found\n")
                }
                
                // Check and set permissions
                let attributes = try? fileManager.attributesOfItem(atPath: resolvedPath)
                if let perms = attributes?[.posixPermissions] as? Int {
                    if (perms & 0o111) == 0 {
                        // Make executable
                        do {
                            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: resolvedPath)
                            DispatchQueue.main.async {
                                execution.log.append("🔧 Made script executable\n")
                            }
                        } catch {
                            DispatchQueue.main.async {
                                execution.log.append("⚠️ Warning: Could not set executable permissions: \(error.localizedDescription)\n")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            execution.log.append("✅ Script is executable\n")
                        }
                    }
                }
                
                // Build command: cd to directory and execute script
                let scriptDir = (resolvedPath as NSString).deletingLastPathComponent
                let scriptName = (resolvedPath as NSString).lastPathComponent
                
                // Properly escape paths for shell
                func escapeShell(_ path: String) -> String {
                    return path.replacingOccurrences(of: "'", with: "'\\''")
                }
                
                let escapedDir = escapeShell(scriptDir)
                let escapedName = escapeShell(scriptName)
                
                // Validate script path before execution
                let pathValidation = InputValidator.shared.validateScriptPath(resolvedPath, repositoryPath: expandedPath)
                if !pathValidation.isValid {
                    DispatchQueue.main.async {
                        execution.state = .failed("Security validation failed")
                        execution.finishedAt = Date()
                        execution.log.append("❌ Security Error: \(pathValidation.message)\n")
                        execution.log.append("🔒 This action has been blocked for security reasons.\n")
                    }
                    return
                }
                
                // Verify file integrity before execution
                let integrityCheck = IntegrityVerifier.shared.verifyFile(resolvedPath)
                if !integrityCheck.isValid {
                    DispatchQueue.main.async {
                        execution.log.append("⚠️ Integrity Warning: \(integrityCheck.message)\n")
                        execution.log.append("   Continuing execution, but file may have been modified.\n\n")
                    }
                }
                
                // Verify file permissions
                let permCheck = IntegrityVerifier.shared.verifyPermissions(resolvedPath)
                if !permCheck.isValid {
                    DispatchQueue.main.async {
                        execution.log.append("⚠️ Permission Warning: \(permCheck.message)\n")
                    }
                }
                
                // Build command with arguments - add non-interactive flag for scripts that support it
                var scriptArgs = tool.arguments
                
                // Sanitize arguments to prevent injection
                scriptArgs = InputValidator.shared.sanitizeArguments(scriptArgs)
                
                // Auto-add non-interactive flag for common scripts if no args provided
                if scriptArgs.isEmpty {
                    let scriptLower = scriptName.lowercased()
                    if scriptLower.contains("guardian") || scriptLower.contains("watchdog") || 
                       scriptLower.contains("blueteam") || scriptLower.contains("remediation") ||
                       scriptLower.contains("audit") {
                        scriptArgs = ["-y", "--non-interactive"]
                        DispatchQueue.main.async {
                            execution.log.append("💡 Auto-added non-interactive flag (-y) for automated execution\n")
                        }
                    }
                }
                
                // Auto-add --resume flag if checkpoint exists (for mac_guardian.sh and mac_watchdog.sh)
                let checkpointDir = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.macguardian/checkpoints"
                if scriptName.contains("mac_guardian") {
                    let checkpointFile = "\(checkpointDir)/mac_guardian_checkpoint.txt"
                    if FileManager.default.fileExists(atPath: checkpointFile) {
                        if !scriptArgs.contains("--resume") {
                            scriptArgs.append("--resume")
                            DispatchQueue.main.async {
                                execution.log.append("🔄 Auto-added --resume flag (checkpoint detected)\n")
                            }
                        }
                    }
                } else if scriptName.contains("mac_watchdog") {
                    let checkpointFile = "\(checkpointDir)/mac_watchdog_checkpoint.txt"
                    if FileManager.default.fileExists(atPath: checkpointFile) {
                        if !scriptArgs.contains("--resume") {
                            scriptArgs.append("--resume")
                            DispatchQueue.main.async {
                                execution.log.append("🔄 Auto-added --resume flag (checkpoint detected)\n")
                            }
                        }
                    }
                }
                
                // Build command with arguments
                var command = "cd '\(escapedDir)' && ./'\(escapedName)'"
                if !scriptArgs.isEmpty {
                    let escapedArgs = scriptArgs.map { escapeShell($0) }.joined(separator: " ")
                    command += " \(escapedArgs)"
                }
                command += " 2>&1"
                
                DispatchQueue.main.async {
                    execution.log.append("📝 Command: \(command)\n")
                    execution.log.append("🚀 Launching process...\n\n")
                }
                
                process.arguments = ["-lc", command]
                
            case .python:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                let resolvedPath = workspace.resolve(path: tool.relativePath)
                process.arguments = [resolvedPath] + tool.arguments
            }

            let outputHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading
            var outputObserver: NSObjectProtocol?
            var errorObserver: NSObjectProtocol?

            // Read stdout
            outputObserver = NotificationCenter.default.addObserver(forName: .NSFileHandleDataAvailable, object: outputHandle, queue: nil) { [weak outputHandle] _ in
                guard let handle = outputHandle else { return }
                let data = handle.availableData
                if data.count > 0 {
                    if let chunk = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            execution.log.append(contentsOf: chunk)
                        }
                    }
                    handle.waitForDataInBackgroundAndNotify()
                }
            }

            // Read stderr
            errorObserver = NotificationCenter.default.addObserver(forName: .NSFileHandleDataAvailable, object: errorHandle, queue: nil) { [weak errorHandle] _ in
                guard let handle = errorHandle else { return }
                let data = handle.availableData
                if data.count > 0 {
                    if let chunk = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            execution.log.append(contentsOf: chunk)
                        }
                    }
            handle.waitForDataInBackgroundAndNotify()
                }
            }

            outputHandle.waitForDataInBackgroundAndNotify()
            errorHandle.waitForDataInBackgroundAndNotify()

            do {
                try process.run()
                DispatchQueue.main.async {
                    execution.log.append("✅ Process started (PID: \(process.processIdentifier))\n")
                    execution.log.append("📡 Waiting for output...\n\n")
                }
            } catch {
                if let obs = outputObserver {
                    NotificationCenter.default.removeObserver(obs)
                }
                if let obs = errorObserver {
                    NotificationCenter.default.removeObserver(obs)
                }
                DispatchQueue.main.async {
                    execution.state = .failed(error.localizedDescription)
                    execution.finishedAt = Date()
                    execution.log.append("\n❌ Failed to start process\n")
                    execution.log.append("   Error: \(error.localizedDescription)\n")
                    execution.log.append("\n💡 Debug Info:\n")
                    execution.log.append("   - Executable: \(process.executableURL?.path ?? "nil")\n")
                    execution.log.append("   - Arguments: \(process.arguments?.joined(separator: " ") ?? "nil")\n")
                    execution.log.append("   - Working Dir: \(process.currentDirectoryURL?.path ?? "nil")\n")
                }
                return
            }

            process.waitUntilExit()
            
            // Read any remaining data from both pipes
            let remainingOutput = outputHandle.readDataToEndOfFile()
            let remainingError = errorHandle.readDataToEndOfFile()
            
            if remainingOutput.count > 0, let outputChunk = String(data: remainingOutput, encoding: .utf8) {
                DispatchQueue.main.async {
                    execution.log.append(contentsOf: outputChunk)
                }
            }
            
            if remainingError.count > 0, let errorChunk = String(data: remainingError, encoding: .utf8) {
                DispatchQueue.main.async {
                    execution.log.append("\n[STDERR]\n")
                    execution.log.append(contentsOf: errorChunk)
                }
            }
            
            if let obs = outputObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = errorObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            
            let status = process.terminationStatus
            DispatchQueue.main.async {
                execution.finishedAt = Date()
                execution.log.append("\n\n" + String(repeating: "─", count: 60) + "\n")
                execution.log.append("📊 Process finished\n")
                execution.log.append("   Exit Code: \(status)\n")
                execution.log.append("   Duration: \(String(format: "%.2f", Date().timeIntervalSince(execution.startedAt)))s\n")
                
                // Save to history
                workspace.addToHistory(execution)
                
                if status == 0 {
                    execution.state = .finished(status)
                    execution.log.append("✅ Execution completed successfully\n")
                } else {
                    // Detect common error patterns and provide helpful guidance
                    let logText = execution.log.lowercased()
                    let logTrimmed = logText.trimmingCharacters(in: .whitespacesAndNewlines)
                    var errorMessage = "Exit code \(status)"
                    var helpfulTip = ""
                    
                    // Check for interactive scripts (empty output + terminal mode + quick failure)
                    if (logTrimmed.isEmpty || logTrimmed.count < 50) && tool.executionMode == .terminal && Date().timeIntervalSince(execution.startedAt) < 1.0 {
                        errorMessage = "Interactive script - Terminal required"
                        let repoPath = workspace.repositoryPath
                        let scriptPath = tool.relativePath
                        helpfulTip = """
                        
                        🖥️ Interactive Script Detected
                        
                        This script requires interactive input (menu selection, user prompts).
                        It cannot run from the UI - you must use Terminal.
                        
                        ✅ Solution:
                        1. Click the "Run in Terminal" button (purple button above)
                        2. Or run manually: cd '\(repoPath)' && ./\(scriptPath)
                        
                        The script will show an interactive menu where you can select options.
                        
                        """
                    } else if logText.contains("sudo") && (logText.contains("password") || logText.contains("terminal is required") || logText.contains("sudo access required")) {
                        errorMessage = "Sudo access required"
                        let repoPath = workspace.repositoryPath
                        let scriptPath = tool.relativePath
                        helpfulTip = """
                        
                        🔐 Sudo Access Required
                        
                        Some operations (like rootkit scan) require administrator privileges.
                        The app cannot provide interactive password input for security reasons.
                        
                        ✅ Good News: Most steps completed! Only rootkit scan was skipped.
                        
                        Options:
                        1. 🔄 Resume from checkpoint:
                           Click "Run Module" again - completed steps will be skipped.
                        
                        2. Run rootkit scan from Terminal (safest):
                           cd '\(repoPath)'
                           sudo ./\(scriptPath) --resume
                           (This will skip completed steps and only run rootkit scan)
                        
                        3. Use sudo cache (password lasts 15 min):
                           Run: sudo -v
                           Then click "Run Module" again
                        
                        4. Configure passwordless sudo (advanced - reduces security):
                           Run: sudo visudo
                           Add: \(NSUserName()) ALL=(ALL) NOPASSWD: /usr/local/bin/rkhunter, /opt/homebrew/bin/rkhunter
                           ⚠️  Warning: This reduces security. See SUDO_SECURITY.md for details.
                        
                        Note: All other security checks completed successfully. Rootkit scan is optional.
                        
                        """
                    } else if logText.contains("interactive") || logText.contains("read") || (logText.isEmpty && tool.executionMode == .terminal) {
                        errorMessage = "Interactive script - Terminal required"
                        let repoPath = workspace.repositoryPath
                        let scriptPath = tool.relativePath
                        helpfulTip = """
                        
                        🖥️ Interactive Script Detected
                        
                        This script requires interactive input (menu selection, user prompts).
                        It cannot run from the UI - you must use Terminal.
                        
                        ✅ Solution:
                        1. Click the "Run in Terminal" button (purple button above)
                        2. Or run manually: cd '\(repoPath)' && ./\(scriptPath)
                        
                        The script will show an interactive menu where you can select options.
                        
                        """
                    } else if logText.contains("permission denied") || logText.contains("cannot execute") {
                        errorMessage = "Permission denied"
                        helpfulTip = "\n💡 Tip: The script may need execute permissions. Try: chmod +x '\(tool.relativePath)'\n"
                    } else if logText.contains("not found") || logText.contains("no such file") {
                        errorMessage = "Script not found"
                        helpfulTip = "\n💡 Tip: Verify the script path is correct: \(tool.relativePath)\n"
                    } else if logText.contains("interactive") || logText.contains("input required") {
                        errorMessage = "Interactive input required"
                        helpfulTip = "\n💡 Tip: This script requires interactive input. Try running it from Terminal, or check if it supports non-interactive flags.\n"
                    } else {
                        helpfulTip = "\n💡 Tip: Check the output above for specific error messages. The script may require additional setup or permissions.\n"
                    }
                    
                    execution.state = .failed(errorMessage)
                    execution.log.append("❌ Execution failed: \(errorMessage)\n")
                    execution.log.append(helpfulTip)
                }
            }
        }

        return execution
    }

    // This method is no longer used but kept for compatibility
    private func shellCommand(for tool: SuiteTool, workspace: WorkspaceState) -> String {
        let resolved = workspace.resolve(path: tool.relativePath)
        let scriptDir = (resolved as NSString).deletingLastPathComponent
        let scriptName = (resolved as NSString).lastPathComponent
        return "cd '\(scriptDir)' && ./'\(scriptName)'"
    }
}

extension SuiteCategory {
    static func defaultCategories() -> [SuiteCategory] {
        return [
            SuiteCategory(
                name: "System Tools",
                description: "Quick access to system management tools with beautiful UIs.",
                tools: [
                    SuiteTool(
                        name: "Process Killer",
                        description: "Safely kill processes and force quit applications that won't close normally. Perfect for Cursor, Firefox, Slack, Discord, and other stubborn apps.",
                        relativePath: "", // This is a UI-only tool
                        kind: .shell,
                        safetyLevel: .destructive,
                        destructiveOperations: ["Can terminate running applications", "Force quit may cause data loss"],
                        executionMode: .ui
                    ),
                    SuiteTool(
                        name: "Cache Cleaner",
                        description: "Safely clear browser caches (Safari, Chrome, Firefox, Edge) and system caches to free up disk space. Preview before cleaning.",
                        relativePath: "", // This is a UI-only tool
                        kind: .shell,
                        safetyLevel: .caution,
                        destructiveOperations: ["Cleans browser cache files", "May delete cookies and browsing history if selected", "Cleans system cache files"],
                        executionMode: .ui
                    ),
                    SuiteTool(
                        name: "Cursor Cache Cleaner",
                        description: "Clear Cursor editor cache for your projects. Fixes cache issues and frees up disk space. Scans for projects automatically.",
                        relativePath: "", // This is a UI-only tool
                        kind: .shell,
                        safetyLevel: .safe,
                        destructiveOperations: ["Cleans Cursor project cache files", "Cleans Cursor global cache"],
                        executionMode: .ui
                    ),
                    SuiteTool(
                        name: "Fix App Icons",
                        description: "Fix macOS app icons that aren't displaying correctly. Clears icon cache and restarts Dock.",
                        relativePath: "", // This is a UI-only tool
                        kind: .shell,
                        safetyLevel: .safe,
                        destructiveOperations: ["Clears macOS icon cache", "Restarts Dock"],
                        executionMode: .ui
                    )
                ]
            ),
            SuiteCategory(
                name: "Mac Suite",
                description: "Main entry point combining all modules.",
                tools: [
                    SuiteTool(
                        name: "Run mac_suite.sh",
                        description: "Launch the interactive command-line menu for the entire suite. ⚠️ This is an interactive menu - must be run from Terminal.",
                        relativePath: "mac_suite.sh",
                        arguments: [],
                        requiresSudo: false,
                        executionMode: .terminal
                    ),
                    SuiteTool(
                        name: "Run mac_guardian.sh",
                        description: "Execute the cleanup and security hardening workflow. ⚠️ Terminal recommended for full functionality (rootkit scan requires sudo).",
                        relativePath: "MacGuardianSuite/mac_guardian.sh",
                        safetyLevel: .caution,
                        destructiveOperations: ["Cleans temporary files", "Updates system packages", "May require sudo for some operations"],
                        executionMode: .terminalRecommended
                    ),
                    SuiteTool(
                        name: "Run mac_watchdog.sh",
                        description: "Start file integrity monitoring and Tripwire-style checks.",
                        relativePath: "MacGuardianSuite/mac_watchdog.sh",
                        safetyLevel: .safe
                    ),
                    SuiteTool(
                        name: "Run mac_blueteam.sh",
                        description: "Advanced detection of suspicious processes, network connections, and anomalies.",
                        relativePath: "MacGuardianSuite/mac_blueteam.sh",
                        safetyLevel: .safe
                    ),
                    SuiteTool(
                        name: "Run mac_ai.sh",
                        description: "Machine learning-driven security analytics and behavioral insights.",
                        relativePath: "MacGuardianSuite/mac_ai.sh",
                        safetyLevel: .safe
                    ),
                    SuiteTool(
                        name: "Run mac_security_audit.sh",
                        description: "Comprehensive security posture assessment for macOS.",
                        relativePath: "MacGuardianSuite/mac_security_audit.sh",
                        safetyLevel: .safe
                    ),
                    SuiteTool(
                        name: "Run mac_remediation.sh",
                        description: "Automated remediation workflows with dry-run safety checks.",
                        relativePath: "MacGuardianSuite/mac_remediation.sh",
                        safetyLevel: .destructive,
                        destructiveOperations: [
                            "Can delete suspicious files",
                            "Can kill processes",
                            "Can remove launch items",
                            "Can modify system permissions",
                            "Can quarantine files"
                        ]
                    )
                ]
            ),
            SuiteCategory(
                name: "Threat Intelligence",
                description: "Collectors, schedulers, and alerting utilities.",
                tools: [
                    SuiteTool(
                        name: "Threat Intel Feeds",
                        description: "Fetch and correlate the latest threat intelligence feeds.",
                        relativePath: "MacGuardianSuite/threat_intel_feeds.sh"
                    ),
                    SuiteTool(
                        name: "Scheduled Reports",
                        description: "Generate scheduled HTML and text reports.",
                        relativePath: "MacGuardianSuite/scheduled_reports.sh"
                    ),
                    SuiteTool(
                        name: "Advanced Alerting",
                        description: "Manage custom alert rules and severity-based notifications.",
                        relativePath: "MacGuardianSuite/advanced_alerting.sh",
                        arguments: ["process"]
                    ),
                    SuiteTool(
                        name: "STIX Exporter",
                        description: "Export collected indicators of compromise to STIX format.",
                        relativePath: "MacGuardianSuite/stix_exporter_wrapper.sh"
                    )
                ]
            ),
            SuiteCategory(
                name: "Utilities",
                description: "Helpful maintenance and troubleshooting utilities.",
                tools: [
                    SuiteTool(
                        name: "Performance Monitor",
                        description: "Track execution times and identify suite bottlenecks.",
                        relativePath: "MacGuardianSuite/performance_monitor.sh"
                    ),
                    SuiteTool(
                        name: "Error Tracker",
                        description: "Review and triage recorded errors from recent runs.",
                        relativePath: "MacGuardianSuite/error_tracker.sh"
                    ),
                    SuiteTool(
                        name: "View Errors",
                        description: "Quickly open the generated error logs.",
                        relativePath: "MacGuardianSuite/view_errors.sh"
                    ),
                    SuiteTool(
                        name: "Module Manager",
                        description: "Enable, disable, and configure suite modules.",
                        relativePath: "MacGuardianSuite/module_manager.py",
                        kind: .python
                    ),
                    SuiteTool(
                        name: "Browser Cleanup",
                        description: "Clean browser caches, cookies, history, and autofill data for Safari, Chrome, Firefox, and Edge.",
                        relativePath: "MacGuardianSuite/browser_cleanup.sh",
                        safetyLevel: .caution,
                        destructiveOperations: ["Cleans browser cache files", "May delete cookies and browsing history if --all flag is used"]
                    ),
                    SuiteTool(
                        name: "App Security Check",
                        description: "Verify integrity and security of MacGuardian Suite files. Checks file checksums, permissions, and detects tampering.",
                        relativePath: "MacGuardianSuite/app_security.sh",
                        arguments: ["--all"],
                        safetyLevel: .safe
                    ),
                    SuiteTool(
                        name: "Fix App Icons",
                        description: "Clear macOS icon cache and fix app icons. Use this if app icons aren't displaying correctly in Finder or Dock.",
                        relativePath: "MacGuardianSuite/fix_app_icons.sh",
                        safetyLevel: .safe
                    )
                ]
            )
        ]
    }
}
