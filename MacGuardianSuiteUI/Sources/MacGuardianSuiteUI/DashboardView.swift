import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var workspace: WorkspaceState
    @StateObject private var incidentStore = IncidentStore.shared
    @State private var lastAudit: LastAudit? = nil

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

                // MacGuardian's check on itself
                SelfCheckCard()

                // Security Score Card (from the last posture audit)
                SecurityScoreCard(score: lastAudit?.score ?? 0)

                // Quick Stats
                HStack(spacing: 16) {
                    StatCard(
                        title: "Open Incidents",
                        value: "\(incidentStore.unacknowledgedCount)",
                        icon: "exclamationmark.triangle.fill",
                        color: incidentStore.unacknowledgedCount > 0 ? .red : .green
                    )
                    StatCard(
                        title: "Last Audit",
                        value: lastAudit.map { formatDate($0.date) } ?? "Never",
                        icon: "clock.fill",
                        color: .themePurple
                    )
                    StatCard(
                        title: "Failed Checks",
                        value: lastAudit.map { "\($0.failed)" } ?? "-",
                        icon: "checkmark.shield.fill",
                        color: (lastAudit?.failed ?? 0) > 0 ? .orange : .themePurple
                    )
                }

                // Quick Actions
                QuickActionsCard(workspace: workspace)

                // Package and application maintenance
                SoftwareUpdatesCard()

                // System Health (live checks)
                SystemHealthCard()

                // Incidents Quick Access
                OmegaGuardianQuickAccess()
                    .environmentObject(workspace)

                // Rootkit Scan Quick Access
                RootkitScanQuickAccess()
            }
            .padding()
        }
        .background(Color.themeBlack)
        .onAppear {
            lastAudit = LastAudit.load()
        }
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
        if score == 0 { return "Run a Security Audit to get your score" }
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

struct QuickActionsCard: View {
    @ObservedObject var workspace: WorkspaceState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(.themeText)
            
            HStack(spacing: 12) {
                QuickActionButton(
                    title: "Security Audit",
                    icon: "shield.checkered",
                    color: .themePurple
                ) {
                    workspace.auditSection = .posture
                    workspace.selectedView = .audit
                }

                QuickActionButton(
                    title: "Threat Scan",
                    icon: "shield.lefthalf.filled",
                    color: .themePurple
                ) {
                    workspace.selectedView = .threats
                }

                QuickActionButton(
                    title: "Reports",
                    icon: "doc.text.fill",
                    color: .themePurple
                ) {
                    workspace.selectedView = .reports
                }

                QuickActionButton(
                    title: "Kill Processes",
                    icon: "xmark.circle.fill",
                    color: .red
                ) {
                    workspace.selectedView = .processes
                }

                QuickActionButton(
                    title: "Clean Cache",
                    icon: "trash.fill",
                    color: .orange
                ) {
                    workspace.cleanerSection = .caches
                    workspace.selectedView = .cleaner
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

struct SoftwareUpdatesCard: View {
    @State private var confirmUpgrade = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundColor(.themePurple)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Software Updates")
                        .font(.headline)
                        .foregroundColor(.themeText)
                    Text("Homebrew tools, Homebrew apps, and Mac App Store apps")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
            }

            Text("Update refreshes catalogs and shows what is outdated. Upgrade Everything installs each available formula and cask update—including auto-update/latest casks—and uses the App Store helper when available.")
                .font(.caption)
                .foregroundColor(.themeTextSecondary)

            HStack(spacing: 12) {
                Button {
                    #if os(macOS)
                    TerminalLauncher.shared.openPackageMaintenance(upgrade: false)
                    #endif
                } label: {
                    Label("Check Updates", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.themePurple)

                Button {
                    confirmUpgrade = true
                } label: {
                    Label("Upgrade Everything", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.themePurple)
            }

            Text("Apps installed directly from vendor websites remain with their own built-in updater.")
                .font(.caption2)
                .foregroundColor(.themeTextSecondary)
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 1)
        )
        .alert("Upgrade all managed software?", isPresented: $confirmUpgrade) {
            Button("Cancel", role: .cancel) {}
            Button("Upgrade All", role: .destructive) {
                #if os(macOS)
                TerminalLauncher.shared.openPackageMaintenance(upgrade: true)
                #endif
            }
        } message: {
            Text("Homebrew may quit managed apps while replacing them. Mac App Store coverage may install the small 'mas' helper first.")
        }
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
                    workspace.incidentsSection = .incidents
                    workspace.selectedView = .incidents
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


/// Shows whether MacGuardian's own scripts, app and jobs passed the self-check.
struct SelfCheckCard: View {
    @EnvironmentObject var workspace: WorkspaceState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.themeText)
                if let result = workspace.selfCheck {
                    Text(result.summary)
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                    ForEach(result.problems.prefix(3), id: \.self) { problem in
                        Text("• \(problem)")
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                            .lineLimit(2)
                    }
                }
            }
            Spacer()
            Button("Details") {
                workspace.auditSection = .selfCheck
                workspace.selectedView = .audit
            }
            .buttonStyle(.bordered)
            Button {
                workspace.selfCheck = nil
                workspace.runSelfCheck()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Run the self-check again")
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.6), lineWidth: 1)
        )
    }

    private var title: String {
        guard let result = workspace.selfCheck else { return "Checking MacGuardian itself..." }
        if !result.passed { return "MacGuardian self-check found problems" }
        return result.problems.isEmpty ? "MacGuardian is intact" : "MacGuardian is intact, with warnings"
    }

    private var icon: String {
        guard let result = workspace.selfCheck else { return "hourglass" }
        return result.passed ? "checkmark.seal.fill" : "exclamationmark.octagon.fill"
    }

    private var color: Color {
        guard let result = workspace.selfCheck else { return .themePurple }
        if !result.passed { return .red }
        return result.problems.isEmpty ? .green : .orange
    }
}
