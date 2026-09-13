import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ToolDetailView: View {
    @EnvironmentObject private var workspace: WorkspaceState
    let tool: SuiteTool
    let runAction: (SuiteTool) -> Void
    @State private var updateTimer: Timer?
    @State private var currentTime = Date()
    
    // Timer to update running status
    private func startStatusTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    private func stopStatusTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    var body: some View {
        // Special handling for UI-only tools
        if tool.name == "Process Killer" {
            ProcessKillerView()
                .padding(32)
                .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.themePurpleDark, lineWidth: 2)
                )
                .shadow(color: .themePurple.opacity(0.3), radius: 12)
        } else if tool.name == "Cache Cleaner" {
            CacheCleanerView()
                .padding(32)
                .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.themePurpleDark, lineWidth: 2)
                )
                .shadow(color: .themePurple.opacity(0.3), radius: 12)
        } else if tool.name == "Cursor Cache Cleaner" {
            CursorCacheCleanerView()
                .padding(32)
                .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.themePurpleDark, lineWidth: 2)
                )
                .shadow(color: .themePurple.opacity(0.3), radius: 12)
        } else if tool.name == "Fix App Icons" {
            FixAppIconsView()
                .padding(32)
                .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.themePurpleDark, lineWidth: 2)
                )
                .shadow(color: .themePurple.opacity(0.3), radius: 12)
        } else {
            VStack(alignment: .leading, spacing: 24) {
                header
                Divider()
                    .background(Color.themePurpleDark)
                executionSection
                Spacer()
            }
            .padding(32)
            .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.themePurpleDark, lineWidth: 2)
            )
            .shadow(color: .themePurple.opacity(0.3), radius: 12)
            .onChange(of: workspace.execution?.state) { _, newState in
                if case .running = newState {
                    startStatusTimer()
                } else {
                    stopStatusTimer()
                }
            }
            .onAppear {
                if case .running = workspace.execution?.state {
                    startStatusTimer()
                }
            }
            .onDisappear {
                stopStatusTimer()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LogoView(size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.name)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundColor(.themeText)
                    Text(tool.description)
                        .font(.title3)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                if !tool.relativePath.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Script Path")
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                        HStack(spacing: 6) {
                        Text(verbatim: workspace.resolve(path: tool.relativePath))
                            .font(.callout.monospaced())
                                .foregroundColor(.themeText)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .frame(maxWidth: 320, alignment: .trailing)
                            if !workspace.checkScriptExists(for: tool) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .help("Script file not found. Check the repository path.")
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                    .help("Script file found and ready to run")
                            }
                        }
                    }
                }
            }

            if !tool.whyItMatters.isEmpty {
                FeatureInfoCard(
                    icon: "info.circle",
                    title: tool.name,
                    whatItDoes: tool.description,
                    whyItMatters: tool.whyItMatters,
                    checks: tool.destructiveOperations,
                    checksLabel: tool.safetyLevel == .safe ? "What it looks at" : "What it can do"
                )
            }

            // Safety warning badge
            if tool.safetyLevel != .safe {
                HStack(spacing: 8) {
                    Image(systemName: tool.safetyLevel.icon)
                        .foregroundColor(tool.safetyLevel == .destructive ? .red : .orange)
                    Text(tool.safetyLevel.rawValue)
                        .font(.subheadline.bold())
                        .foregroundColor(tool.safetyLevel == .destructive ? .red : .orange)
                    Text("•")
                        .foregroundColor(.themeTextSecondary)
                    Text(tool.safetyLevel.description)
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    (tool.safetyLevel == .destructive ? Color.red : Color.orange).opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
            
            // Terminal recommendation badge
            if tool.executionMode == .terminalRecommended || tool.executionMode == .terminal {
                HStack(spacing: 8) {
                    Image(systemName: tool.executionMode.icon)
                        .foregroundColor(.themePurple)
                    Text(tool.executionMode.rawValue)
                        .font(.subheadline.bold())
                        .foregroundColor(.themePurple)
                    Text("•")
                        .foregroundColor(.themeTextSecondary)
                    Text(tool.executionMode.description)
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Color.themePurple.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                
                // Terminal command helper
                TerminalCommandView(tool: tool)
                    .environmentObject(workspace)
            }

            HStack(spacing: 12) {
                // Show "Run in Terminal" button for terminal-recommended tools
                if tool.executionMode == .terminalRecommended || tool.executionMode == .terminal {
                    Button {
                        openTerminalForTool()
                    } label: {
                        Label("Run in Terminal", systemImage: "terminal.fill")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.themePurple)
                    .help("Opens Terminal with command ready to run")
                }
                
                // For terminal-only tools, disable UI execution and show warning
                if tool.executionMode == .terminal {
                    Button {
                        // Do nothing - just show info
                    } label: {
                        Label("Terminal Only", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(true)
                    .help("This script requires Terminal - use the 'Run in Terminal' button above")
                } else {
                    Button {
                        // Clear any previous execution for this tool
                        if let currentExecution = workspace.execution, currentExecution.tool.id == tool.id {
                            workspace.execution = nil
                        }
                        // Request safety confirmation if needed
                        workspace.requestSafetyConfirmation(for: tool) {
                            // Small delay to ensure UI updates
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        runAction(tool)
                            }
                        }
                    } label: {
                        Label("Run Module", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.themePurple)
                    .disabled(!workspace.checkScriptExists(for: tool) || !workspace.validateRepositoryPath().isValid)
                    .help(workspace.checkScriptExists(for: tool) ? "Execute this module" : "Script not found - check repository path")
                }

                Button {
                    revealInFinder()
                } label: {
                    Label("Reveal Script", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .tint(.themePurple)

                Spacer()

                Button(role: .destructive) {
                    workspace.execution = nil
                } label: {
                    Label("Clear Output", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.themePurple)
                .disabled(workspace.execution == nil)
            }
        }
    }

    private var executionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Debug: Show if execution exists but doesn't match
            if let exec = workspace.execution, exec.tool.id != tool.id {
                VStack(spacing: 8) {
                    Text("⚠️ Execution running for different tool")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Current: \(exec.tool.name)")
                        .font(.caption2)
                        .foregroundColor(.themeTextSecondary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            if let execution = workspace.execution, execution.tool.id == tool.id {
                statusHeader(for: execution)
                outputView(for: execution)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "terminal")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("No Output Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Click 'Run Module' to execute this script and see live output here.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    if !workspace.checkScriptExists(for: tool) {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Script Not Found")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                            }
                            Text("The script file doesn't exist at the expected path. Please verify your repository path is correct.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            }
        }
    }

    private func statusHeader(for execution: CommandExecution) -> some View {
        let statusText: String
        let statusColor: Color
        switch execution.state {
        case .idle:
            statusText = "Idle"
            statusColor = .themeTextSecondary
        case .running:
            statusText = "Running…"
            statusColor = .themePurple
        case .finished:
            statusText = "Completed Successfully"
            statusColor = .green
        case .failed(let message):
            statusText = "Failed – \(message)"
            statusColor = .red
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 8) {
                    if case .running = execution.state {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.themePurple)
                    }
            Label(statusText, systemImage: iconName(for: execution.state))
                .foregroundColor(statusColor)
                .font(.headline)
                }
            Spacer()
                // Real-time timer
                LiveTimer(execution: execution, currentTime: currentTime)
            }
            
            // Show last line of output as a preview when running
            if case .running = execution.state, !execution.log.isEmpty {
                let logLines = execution.log.components(separatedBy: .newlines)
                if let lastLine = logLines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.themePurple)
                        Text(lastLine.trimmingCharacters(in: .whitespaces))
                            .font(.caption.monospaced())
                            .foregroundColor(.themeTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            
            // Show output stats
            if !execution.log.isEmpty {
                HStack(spacing: 16) {
                    Label("\(execution.log.count) chars", systemImage: "text.alignleft")
                        .font(.caption2)
                        .foregroundColor(.themeTextSecondary)
                    Label("\(execution.log.components(separatedBy: .newlines).count) lines", systemImage: "list.number")
                        .font(.caption2)
                        .foregroundColor(.themeTextSecondary)
                }
            }
        }
        .onAppear {
            // Start update timer that runs continuously
            updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                currentTime = Date()
            }
            RunLoop.main.add(updateTimer!, forMode: .common)
            }
        .onDisappear {
            updateTimer?.invalidate()
            updateTimer = nil
        }
    }
    

    private func executionDuration(for execution: CommandExecution) -> String? {
        let end = execution.finishedAt ?? Date()
        let interval = end.timeIntervalSince(execution.startedAt)
        guard interval > 0 else { return nil }
        return formatDuration(interval)
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func iconName(for state: CommandExecution.State) -> String {
        switch state {
        case .idle:
            return "pause.fill"
        case .running:
            return "circle.dashed"
        case .finished:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    private func outputView(for execution: CommandExecution) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                outputContent(for: execution)
                    .id("output")
                    .onChange(of: execution.log) { _, newValue in
                        if !newValue.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    proxy.scrollTo("output", anchor: .bottom)
                                }
                            }
                        }
                    }
            }
            .frame(minHeight: 360)
        }
    }
    
    private func outputContent(for execution: CommandExecution) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if execution.log.isEmpty {
                Text("Output will appear here…")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.themeTextSecondary)
            } else {
                // Enhanced output with better formatting
                Text(execution.log)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .foregroundColor(.themePurpleLight)
                    .lineSpacing(2)
                
                // Show line count and stats
                HStack {
                    Spacer()
                    Text("\(execution.log.components(separatedBy: .newlines).count) lines • \(execution.log.count) chars")
                        .font(.caption2)
                        .foregroundColor(.themeTextSecondary)
                        .padding(.top, 4)
                }
            }
            
            // Interactive script warning
            if case .running = execution.state {
                let logLines = execution.log.components(separatedBy: .newlines)
                let recentOutput = logLines.suffix(10).joined(separator: "\n")
                let isWaiting = OutputFormatter.detectInteractivePrompt(recentOutput)
                
                if isWaiting || execution.log.count < 300 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if isWaiting {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                            } else {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.themePurple)
                            }
                            Text(isWaiting ? "Waiting for input" : "Script is running...")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(isWaiting ? .yellow : .themePurple)
                        .padding(.top, 12)
                        
                        if isWaiting {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("⚠️ Interactive Prompt Detected")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.yellow)
                                Text("This script is waiting for user input. The UI automatically added the '-y' flag for non-interactive execution, but some scripts may still require input.")
                                    .font(.caption2)
                                    .foregroundColor(.themeTextSecondary)
                            }
                            .padding(8)
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(6)
                            .padding(.top, 4)
                        } else if execution.log.count < 300 {
                            Text("💡 Output is streaming in real-time. Large scripts may take time to produce output.")
                                .font(.caption2)
                                .foregroundColor(.themeTextSecondary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .background(Color.themeBlack)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 2)
        )
    }

    private func openTerminalForTool() {
        #if os(macOS)
        let resolvedPath = workspace.resolve(path: tool.relativePath)
        let scriptDir = (resolvedPath as NSString).deletingLastPathComponent
        let scriptName = (resolvedPath as NSString).lastPathComponent
        
        var cmd = "cd '\(scriptDir)'"
        if tool.requiresSudo || tool.executionMode == .terminal {
            cmd += " && sudo ./'\(scriptName)'"
        } else {
            cmd += " && ./'\(scriptName)'"
        }
        
        if !tool.arguments.isEmpty {
            cmd += " \(tool.arguments.joined(separator: " "))"
        }
        
        // Add resume flag if checkpoint exists
        if tool.relativePath.contains("mac_guardian") {
            let checkpointFile = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.macguardian/checkpoints/mac_guardian_checkpoint.txt"
            if FileManager.default.fileExists(atPath: checkpointFile) {
                cmd += " --resume"
            }
        }
        
        let script = """
        tell application "Terminal"
            activate
            do script "\(cmd)"
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("Error opening Terminal: \(error)")
            }
        }
        #endif
    }
    
    private func revealInFinder() {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: workspace.resolve(path: tool.relativePath))
        ])
        #endif
    }
}
