import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var workspace: WorkspaceState
    @StateObject private var threatService = ThreatIntelligenceService.shared
    @State private var securityScore: Int = 0
    @State private var lastScanDate: Date? = nil
    @State private var activeThreats: Int = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with Logo
                HStack {
                    LogoView(size: 80)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MacGuardian Suite")
                            .font(.title.bold())
                            .foregroundColor(.themeText)
                        Text("Security Dashboard")
                            .font(.subheadline)
                            .foregroundColor(.themeTextSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                
                // Security Score Card
                SecurityScoreCard(score: securityScore)
                
                // Quick Stats
                HStack(spacing: 16) {
                    StatCard(
                        title: "Active Threats",
                        value: "\(activeThreats)",
                        icon: "exclamationmark.triangle.fill",
                        color: activeThreats > 0 ? .red : .green
                    )
                    StatCard(
                        title: "Last Scan",
                        value: lastScanDate != nil ? formatDate(lastScanDate!) : "Never",
                        icon: "clock.fill",
                        color: .themePurple
                    )
                    StatCard(
                        title: "Total Scans",
                        value: "\(workspace.executionHistory.count)",
                        icon: "chart.bar.fill",
                        color: .themePurple
                    )
                }
                
                // Recent Scans
                RecentScansCard(executions: Array(workspace.executionHistory.prefix(5)))
                
                // Quick Actions
                QuickActionsCard(workspace: workspace)
                
                // System Health (live checks)
                SystemHealthCard()

                // Security Dashboards Quick Access
                SecurityDashboardsCard()
                    .environmentObject(workspace)

                // Omega Guardian Quick Access
                OmegaGuardianQuickAccess()
                    .environmentObject(workspace)

                // Threat Intelligence Quick Access
                ThreatIntelligenceQuickAccess()
                    .environmentObject(workspace)

                // Rootkit Scan Quick Access
                RootkitScanQuickAccess()
            }
            .padding()
        }
        .background(Color.themeBlack)
        .onAppear {
            loadDashboardData()
        }
    }
    
    private func loadDashboardData() {
        // Find last scan date
        lastScanDate = workspace.executionHistory
            .first { $0.finishedAt != nil }?
            .finishedAt

        // Calculate security score based on real outcomes
        let total = workspace.executionHistory.count
        if total == 0 {
            securityScore = 0
        } else {
            // Clean = exit code 0, threat found = exit code 1, error = anything else
            let cleanScans = workspace.executionHistory.filter {
                if case .finished(let code) = $0.state { return code == 0 }
                return false
            }.count
            let threatScans = workspace.executionHistory.filter {
                if case .finished(let code) = $0.state { return code == 1 }
                return false
            }.count

            var score = Int((Double(cleanScans) / Double(total)) * 100)
            // Each threat scan and each IOC match today reduces the score
            score -= threatScans * 10
            score -= threatService.stats.matchesToday * 5
            securityScore = max(0, min(100, score))
        }

        // Update active threats from threat intelligence service
        activeThreats = threatService.stats.matchesToday
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct SecurityScoreCard: View {
    let score: Int
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Security Score")
                    .font(.headline)
                    .foregroundColor(.themeText)
                Spacer()
            }
            
            ZStack {
                Circle()
                    .stroke(Color.themePurpleDark, lineWidth: 12)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(), value: score)
                
                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(scoreColor)
                    Text("%")
                        .font(.title3)
                        .foregroundColor(.themeTextSecondary)
                }
            }
            
            Text(scoreDescription)
                .font(.subheadline)
                .foregroundColor(.themeTextSecondary)
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 1)
        )
    }
    
    private var scoreColor: Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }
    
    private var scoreDescription: String {
        if score == 0 { return "Run a scan to get your score" }
        if score >= 80 { return "System is secure" }
        if score >= 60 { return "Some issues detected" }
        return "Action required"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.themeTextSecondary)
            }
            Text(value)
                .font(.title2.bold())
                .foregroundColor(.themeText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 1)
        )
    }
}

struct RecentScansCard: View {
    let executions: [CommandExecution]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Scans")
                    .font(.headline)
                    .foregroundColor(.themeText)
                Spacer()
            }
            
            if executions.isEmpty {
                Text("No scans yet")
                    .font(.subheadline)
                    .foregroundColor(.themeTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(executions) { execution in
                    ScanRow(execution: execution)
                }
            }
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 1)
        )
    }
}

struct ScanRow: View {
    let execution: CommandExecution
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(execution.tool.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.themeText)
                Text(formatDate(execution.startedAt))
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundColor(statusColor)
        }
        .padding(.vertical, 4)
    }
    
    private var statusIcon: String {
        switch execution.state {
        case .finished: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath"
        default: return "circle"
        }
    }
    
    private var statusColor: Color {
        switch execution.state {
        case .finished: return .green
        case .failed: return .red
        case .running: return .themePurple
        default: return .themeTextSecondary
        }
    }
    
    private var statusText: String {
        switch execution.state {
        case .finished: return "Success"
        case .failed: return "Failed"
        case .running: return "Running"
        default: return "Idle"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct QuickActionsCard: View {
    @ObservedObject var workspace: WorkspaceState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(.themeText)
            
            HStack(spacing: 12) {
                QuickActionButton(
                    title: "Security Scan",
                    icon: "shield.checkered",
                    color: .themePurple
                ) {
                    // Navigate to tools and find security scan
                    workspace.selectedView = .tools
                }
                
                QuickActionButton(
                    title: "Generate Report",
                    icon: "doc.text.fill",
                    color: .themePurple
                ) {
                    // Navigate to reports
                    workspace.selectedView = .reports
                }
                
                QuickActionButton(
                    title: "View Reports",
                    icon: "folder.fill",
                    color: .themePurple
                ) {
                    workspace.selectedView = .reports
                }
                
                QuickActionButton(
                    title: "Kill Processes",
                    icon: "xmark.circle.fill",
                    color: .red
                ) {
                    workspace.showProcessKiller = true
                }
                
                QuickActionButton(
                    title: "Clean Cache",
                    icon: "trash.fill",
                    color: .orange
                ) {
                    workspace.showCacheCleaner = true
                }
                
                QuickActionButton(
                    title: "Cursor Cache",
                    icon: "cursorarrow.click",
                    color: .blue
                ) {
                    workspace.showCursorCacheCleaner = true
                }
            }
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 1)
        )
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.themeText)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.themeBlack, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct SystemHealthCard: View {
    @State private var firewallStatus: HealthStatus = .warning
    @State private var filevaultStatus: HealthStatus = .warning
    @State private var antivirusStatus: HealthStatus = .warning
    @State private var backupStatus: HealthStatus = .warning
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("System Health")
                    .font(.headline)
                    .foregroundColor(.themeText)
                Spacer()
                if isChecking {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button {
                        checkHealth()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.themePurple)
                }
            }

            HealthIndicator(title: "Firewall", status: firewallStatus)
            HealthIndicator(title: "FileVault", status: filevaultStatus)
            HealthIndicator(title: "Antivirus (ClamAV)", status: antivirusStatus)
            HealthIndicator(title: "Time Machine Backup", status: backupStatus)
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 1)
        )
        .onAppear { checkHealth() }
    }

    private func checkHealth() {
        isChecking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fw = runCheck("/usr/libexec/ApplicationFirewall/socketfilterfw", args: ["--getglobalstate"]) { $0.lowercased().contains("enabled") }
            let fv = runCheck("/usr/bin/fdesetup", args: ["status"]) { $0.contains("FileVault is On") }
            let av = runCheck("/usr/bin/which", args: ["clamscan"]) { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let bk = runBackupCheck()
            DispatchQueue.main.async {
                firewallStatus = fw
                filevaultStatus = fv
                antivirusStatus = av
                backupStatus = bk
                isChecking = false
            }
        }
    }

    private func runCheck(_ path: String, args: [String], isGood: (String) -> Bool) -> HealthStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return .warning }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return isGood(output) ? .good : .error
    }

    private func runBackupCheck() -> HealthStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["latestbackup"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return .warning }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus == 0 && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .good
        }
        return .warning
    }
}

struct HealthIndicator: View {
    let title: String
    let status: HealthStatus
    
    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.themeText)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundColor(statusColor)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .good: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    private var statusText: String {
        switch status {
        case .good: return "OK"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }
}

enum HealthStatus {
    case good, warning, error
}

struct RootkitScanQuickAccess: View {
    @State private var isOpening = false
    @State private var showCommand = false
    @State private var commandText = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.themePurple)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rootkit Scan")
                        .font(.headline)
                        .foregroundColor(.themeText)
                    Text("Scan for hidden rootkits and malware")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("⚠️ Rootkit scan requires Terminal and administrator privileges.")
                    .font(.caption)
                    .foregroundColor(.orange)
                
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.caption2)
                    Text("Command will be copied to clipboard automatically")
                        .font(.caption2)
                }
                .foregroundColor(.themeTextSecondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            
            if showCommand && !commandText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Command to run:")
                            .font(.caption.bold())
                            .foregroundColor(.themeText)
                        Spacer()
                        Button {
                            #if os(macOS)
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(commandText, forType: .string)
                            #endif
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.clipboard")
                                Text("Copy")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.themePurple)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(commandText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.themeText)
                            .padding(8)
                            .background(Color.themeBlack)
                            .cornerRadius(6)
                    }
                    .frame(maxHeight: 100)
                }
                .padding()
                .background(Color.themeDarkGray.opacity(0.5))
                .cornerRadius(8)
            }
            
            HStack(spacing: 12) {
                Button {
                    isOpening = true
                    #if os(macOS)
                    // Get command and copy to clipboard, then open Terminal
                    let command = TerminalLauncher.shared.getRkhunterScanCommandForClipboard(updateFirst: true)
                    commandText = command
                    showCommand = true
                    
                    // Copy to clipboard
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(command, forType: .string)
                    
                    // Open Terminal with instructions
                    TerminalLauncher.shared.openRkhunterScan(updateFirst: true)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isOpening = false
                    }
                    #endif
                } label: {
                    HStack {
                        if isOpening {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "terminal.fill")
                        }
                        Text("Open Terminal & Copy Command")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.themePurple)
                .disabled(isOpening)
                
                Button {
                    #if os(macOS)
                    TerminalLauncher.shared.openMacGuardianScript()
                    #endif
                } label: {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("Full Security Scan")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.themePurple)
            }
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 1)
        )
    }
}

struct OmegaGuardianQuickAccess: View {
    @EnvironmentObject var workspace: WorkspaceState
    @StateObject private var incidentStore = IncidentStore.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(Color(red: 0.54, green: 0.16, blue: 0.95))
                    .font(.title2)
                Text("Omega Guardian Alerts")
                    .font(.headline)
                    .foregroundColor(.themeText)
                Spacer()
                
                if incidentStore.unacknowledgedCount > 0 {
                    Text("\(incidentStore.unacknowledgedCount)")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(incidentStore.incidents.count)")
                        .font(.title2.bold())
                        .foregroundColor(.themePurple)
                    Text("Total Incidents")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                
                Spacer()
                
                Button {
                    workspace.selectedView = .omegaGuardian
                } label: {
                    Label("Open Console", systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.54, green: 0.16, blue: 0.95))
            }
            
            if incidentStore.criticalCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundColor(Color(red: 1, green: 0.18, blue: 0.39))
                    Text("\(incidentStore.criticalCount) critical incident(s) require attention")
                        .font(.caption)
                        .foregroundColor(Color(red: 1, green: 0.18, blue: 0.39))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            } else if incidentStore.unacknowledgedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.orange)
                    Text("\(incidentStore.unacknowledgedCount) unacknowledged incident(s)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("No active incidents")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 1)
        )
    }
}

struct SecurityDashboardsCard: View {
    @EnvironmentObject var workspace: WorkspaceState
    
    init() {}
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Security Dashboards")
                .font(.headline)
                .foregroundColor(.themeText)
            
            HStack(spacing: 12) {
                QuickActionButton(
                    title: "SSH Security",
                    icon: "key.fill",
                    color: .themePurple
                ) {
                    workspace.selectedView = .sshSecurity
                }
                
                QuickActionButton(
                    title: "User Accounts",
                    icon: "person.2.fill",
                    color: .themePurple
                ) {
                    workspace.selectedView = .userAccountSecurity
                }
                
                QuickActionButton(
                    title: "Privacy",
                    icon: "hand.raised.fill",
                    color: .themePurple
                ) {
                    workspace.selectedView = .privacyHeatmap
                }
                
                QuickActionButton(
                    title: "Network",
                    icon: "network",
                    color: .themePurple
                ) {
                    workspace.selectedView = .networkGraph
                }
                
                QuickActionButton(
                    title: "Timeline",
                    icon: "clock.fill",
                    color: .themePurple
                ) {
                    workspace.selectedView = .incidentTimeline
                }
            }
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 1)
        )
    }
}

struct ThreatIntelligenceQuickAccess: View {
    @EnvironmentObject var workspace: WorkspaceState
    @StateObject private var threatService = ThreatIntelligenceService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.red)
                    .font(.title2)
                Text("Threat Intelligence")
                    .font(.headline)
                    .foregroundColor(.themeText)
                Spacer()
                
                if threatService.stats.matchesToday > 0 {
                    Text("\(threatService.stats.matchesToday) threat(s) today")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(6)
                }
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(threatService.stats.totalIOCs)")
                        .font(.title2.bold())
                        .foregroundColor(.themePurple)
                    Text("Total IOCs")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                
                Spacer()
                
                Button {
                    workspace.selectedView = .threatIntelligence
                } label: {
                    Label("Open Threat Intel", systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            
            if threatService.stats.matchesToday > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("\(threatService.stats.matchesToday) threat match(es) detected today")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("No threats detected today")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 1)
        )
        .onAppear {
            threatService.loadIOCs()
        }
    }
}

