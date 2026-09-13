import SwiftUI

struct SSHSecurityView: View {
    @StateObject private var viewModel = SSHSecurityViewModel()
    @State private var auditResult: SSHAuditResult?
    @State private var isLoading = false
    @State private var showBaselineAlert = false
    
    // Real-time SSH events from optimized view model
    var sshEvents: [MacGuardianEvent] {
        viewModel.sshEvents
    }
    
    // Computed properties for real-time updates
    var issuesFound: Int {
        sshEvents.count
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "key.fill")
                        .font(.title)
                        .foregroundColor(.themePurple)
                    VStack(alignment: .leading) {
                        Text("SSH Security")
                            .font(.title.bold())
                        Text("Monitor SSH keys and configuration")
                            .font(.subheadline)
                            .foregroundColor(.themeTextSecondary)
                    }
                    Spacer()
                    Button {
                        runAudit()
                    } label: {
                        Label("Run Audit", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.themePurple)
                    .disabled(isLoading)
                }
                .padding()

                FeatureInfoCard(
                    icon: "key.fill",
                    title: "SSH Security",
                    whatItDoes: "Audits your SSH setup: which keys exist, whether any are weak or passphrase-less, who's allowed to log in remotely, and whether risky server settings (like password auth or root login) are enabled.",
                    whyItMatters: "SSH is the most common way a Mac gets remotely controlled once an attacker has any foothold - a leftover key, a weak passphrase, or root login left on can turn a minor compromise into full remote access.",
                    checks: ["Keys in ~/.ssh and their strength", "authorized_keys entries (who can log in as you)", "sshd_config settings like PermitRootLogin and PasswordAuthentication", "Recent SSH connection attempts"]
                )
                .padding(.horizontal)

                Divider()

                // Real-time Connection Status
                ConnectionStatusIndicator(
                    isConnected: LiveUpdateService.shared.isConnected,
                    lastUpdate: LiveUpdateService.shared.lastUpdate
                )
                
                if isLoading {
                    ProgressView("Running SSH audit...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    // Real-time Events Section
                    VStack(alignment: .leading, spacing: 16) {
                        // Summary
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Real-Time Events")
                                    .font(.headline)
                                    .foregroundColor(.themeTextSecondary)
                                Text("\(issuesFound)")
                                    .font(.title.bold())
                                    .foregroundColor(issuesFound > 0 ? Color(red: 0.9, green: 0.1, blue: 0.3) : .green)
                            }
                            Spacer()
                            Button {
                                showBaselineAlert = true
                            } label: {
                                Label("Update Baseline", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color.themeDarkGray)
                        .cornerRadius(12)
                        
                        // Real-time SSH Events
                        if !sshEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Recent SSH Events")
                                    .font(.headline.bold())
                                
                                ForEach(sshEvents.prefix(20)) { event in
                                    SSHEventRow(event: event)
                                }
                            }
                            .padding()
                            .background(Color.themeDarkGray)
                            .cornerRadius(12)
                        }
                        
                        // Static Audit Results (if available)
                        if let audit = auditResult {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Last Audit Results")
                                    .font(.headline.bold())
                                
                                // File Status
                                VStack(alignment: .leading, spacing: 8) {
                                    FileStatusRow(
                                        name: "Authorized Keys",
                                        path: audit.authorizedKeysFile,
                                        status: audit.authorizedKeysStatus
                                    )
                                    
                                    FileStatusRow(
                                        name: "SSH Config",
                                        path: audit.configFile,
                                        status: audit.configStatus
                                    )
                                    
                                    FileStatusRow(
                                        name: "Known Hosts",
                                        path: audit.knownHostsFile,
                                        status: audit.knownHostsStatus
                                    )
                                }
                                .padding()
                                .background(Color.themeBlack.opacity(0.5))
                                .cornerRadius(8)
                            }
                            .padding()
                            .background(Color.themeDarkGray)
                            .cornerRadius(12)
                        } else if sshEvents.isEmpty {
                            // Empty State
                            VStack(spacing: 16) {
                                Image(systemName: "key")
                                    .font(.system(size: 60))
                                    .foregroundColor(.themeTextSecondary)
                                Text("No SSH events detected")
                                    .font(.headline)
                                Text("SSH security events will appear here in real-time")
                                    .font(.subheadline)
                                    .foregroundColor(.themeTextSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.themeBlack)
        .onAppear {
            loadLatestAudit()
        }
        .alert("Update Baseline", isPresented: $showBaselineAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Update") {
                updateBaseline()
            }
        } message: {
            Text("This will update the SSH baseline with current configuration. Continue?")
        }
    }
    
    private func runAudit() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/MacGuardianProject/MacGuardianSuite/auditors/ssh_auditor.sh"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath, "audit"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                // Parse audit output and find latest JSON file
                let auditDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".macguardian/audits")
                
                if let files = try? FileManager.default.contentsOfDirectory(at: auditDir, includingPropertiesForKeys: [.creationDateKey]),
                   let latestFile = files.filter({ $0.lastPathComponent.contains("ssh_audit") })
                       .sorted(by: { 
                      let date0 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                      let date1 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                      return date0 > date1
                  })
                       .first,
                   let data = try? Data(contentsOf: latestFile),
                   let audit = try? JSONDecoder().decode(SSHAuditResult.self, from: data) {
                    DispatchQueue.main.async {
                        self.auditResult = audit
                        self.isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadLatestAudit() {
        let auditDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".macguardian/audits")
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: auditDir, includingPropertiesForKeys: [.creationDateKey]),
              let latestFile = files.filter({ $0.lastPathComponent.contains("ssh_audit") })
                  .sorted(by: { 
                      let date0 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                      let date1 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                      return date0 > date1
                  })
                  .first,
              let data = try? Data(contentsOf: latestFile),
              let audit = try? JSONDecoder().decode(SSHAuditResult.self, from: data) else {
            return
        }
        
        auditResult = audit
    }
    
    private func updateBaseline() {
        let scriptPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/MacGuardianProject/MacGuardianSuite/auditors/ssh_auditor.sh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, "baseline"]
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? process.run()
            process.waitUntilExit()
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Real-time SSH Event Row Component
struct SSHEventRow: View {
    let event: MacGuardianEvent
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Severity indicator
            Circle()
                .fill(event.severityColor)
                .frame(width: 12, height: 12)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.event_type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline.bold())
                        .foregroundColor(.themeText)
                    Spacer()
                    if let date = event.date {
                        Text(formatTime(date))
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                    }
                }
                
                Text(event.message)
                    .font(.subheadline)
                    .foregroundColor(.themeTextSecondary)
                
                // Show source
                HStack {
                    Image(systemName: "tag.fill")
                        .font(.caption2)
                    Text(event.source)
                        .font(.caption)
                }
                .foregroundColor(.themePurple.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.themePurple.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding()
        .background(Color.themeBlack.opacity(0.5))
        .cornerRadius(8)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct SSHAuditResult: Codable {
    let timestamp: String
    let auditType: String
    let issuesFound: Int
    let findings: [SSHFinding]
    let authorizedKeysFile: String
    let configFile: String
    let knownHostsFile: String
    
    var authorizedKeysStatus: FileStatus {
        issuesFound > 0 ? .modified : .ok
    }
    
    var configStatus: FileStatus {
        issuesFound > 0 ? .modified : .ok
    }
    
    var knownHostsStatus: FileStatus {
        issuesFound > 0 ? .modified : .ok
    }
    
    enum CodingKeys: String, CodingKey {
        case timestamp, auditType = "audit_type", issuesFound = "issues_found"
        case findings, authorizedKeysFile = "authorized_keys_file"
        case configFile = "config_file", knownHostsFile = "known_hosts_file"
    }
}

struct SSHFinding: Codable, Identifiable {
    let id = UUID()
    let type: String
    let message: String
    let severity: String
}

enum FileStatus {
    case ok, modified, missing
}

struct FindingRow: View {
    let finding: SSHFinding
    
    var body: some View {
        HStack {
            Image(systemName: severityIcon)
                .foregroundColor(severityColor)
            VStack(alignment: .leading) {
                Text(finding.message)
                    .font(.subheadline.bold())
                Text(finding.type)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.themeBlack.opacity(0.5))
        .cornerRadius(8)
    }
    
    private var severityColor: Color {
        switch finding.severity.lowercased() {
        case "critical": return Color(red: 0.9, green: 0.1, blue: 0.3) // Muted red-purple
        case "high": return Color(red: 0.8, green: 0.3, blue: 0.5) // Purple-red blend
        default: return .themePurpleLight // Lighter purple
        }
    }
    
    private var severityIcon: String {
        switch finding.severity.lowercased() {
        case "critical": return "exclamationmark.triangle.fill"
        case "high": return "exclamationmark.circle.fill"
        default: return "info.circle.fill"
        }
    }
}

struct FileStatusRow: View {
    let name: String
    let path: String
    let status: FileStatus
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
            VStack(alignment: .leading) {
                Text(name)
                    .font(.subheadline.bold())
                Text(path)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
            Spacer()
            Text(statusText)
                .font(.caption.bold())
                .foregroundColor(statusColor)
        }
        .padding(.vertical, 4)
    }
    
    private var statusIcon: String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .modified: return "exclamationmark.triangle.fill"
        case .missing: return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .ok: return .themePurple.opacity(0.7) // Subtle purple for OK
        case .modified: return .themePurpleLight // Lighter purple for modified
        case .missing: return Color(red: 0.9, green: 0.1, blue: 0.3) // Muted red-purple for missing
        }
    }
    
    private var statusText: String {
        switch status {
        case .ok: return "OK"
        case .modified: return "Modified"
        case .missing: return "Missing"
        }
    }
}

