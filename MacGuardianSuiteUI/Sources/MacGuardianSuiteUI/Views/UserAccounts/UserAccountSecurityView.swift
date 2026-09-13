import SwiftUI

struct UserAccountSecurityView: View {
    @StateObject private var liveService = LiveUpdateService.shared
    @State private var auditResult: UserAccountAuditResult?
    @State private var isLoading = false
    
    // Real-time user account events
    var userEvents: [MacGuardianEvent] {
        liveService.userAccountEvents
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.title)
                        .foregroundColor(.themePurple)
                    VStack(alignment: .leading) {
                        Text("User Accounts")
                            .font(.title.bold())
                        Text("Monitor user accounts and privileges")
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
                    icon: "person.2.fill",
                    title: "User Accounts",
                    whatItDoes: "Lists every account on this Mac, who has admin rights, whether guest/hidden accounts are enabled, and flags accounts created or elevated to admin recently.",
                    whyItMatters: "An extra admin account is one of the quietest ways to maintain persistent access to a machine - it doesn't trigger antivirus, doesn't look like malware, and works even after a full reinstall of any app.",
                    checks: ["Every local user account and its privilege level", "Guest account and hidden account status", "Recently created or newly-elevated admin accounts", "Sudoers configuration"]
                )
                .padding(.horizontal)

                Divider()

                // Real-time Connection Status
                HStack {
                    ConnectionStatusIndicator(
                        isConnected: liveService.isConnected,
                        lastUpdate: liveService.lastUpdate,
                        showLastUpdate: false
                    )
                    Spacer()
                    Text("\(userEvents.count) real-time event(s)")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                
                if isLoading {
                    ProgressView("Running user account audit...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        // Real-time Events Section
                        if !userEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Real-Time User Account Events")
                                    .font(.headline.bold())
                                
                                ForEach(userEvents.prefix(20)) { event in
                                    UserAccountEventRow(event: event)
                                }
                            }
                            .padding()
                            .background(Color.themeDarkGray)
                            .cornerRadius(12)
                        }
                        
                        // Static Audit Results (if available)
                        if let audit = auditResult {
                            // Statistics
                            HStack(spacing: 16) {
                                UserAccountStatCard(
                                    title: "Total Users",
                                    value: "\(audit.currentUserCount)",
                                    icon: "person.3.fill",
                                    color: .themePurple
                                )
                                UserAccountStatCard(
                                    title: "Admin Accounts",
                                    value: "\(audit.adminAccounts)",
                                    icon: "key.fill",
                                    color: audit.adminAccounts > 1 ? .orange : .themePurple
                                )
                                UserAccountStatCard(
                                    title: "Root Accounts",
                                    value: "\(audit.rootAccounts)",
                                    icon: "exclamationmark.shield.fill",
                                    color: audit.rootAccounts > 0 ? Color(red: 0.9, green: 0.1, blue: 0.3) : .themePurple
                                )
                            }
                            .padding()
                            
                            // Issues
                            if audit.issuesFound > 0 {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Security Issues")
                                        .font(.headline.bold())
                                    
                                    if audit.currentUserCount != audit.baselineUserCount {
                                        IssueCard(
                                            title: "User Count Changed",
                                            message: "\(audit.baselineUserCount) → \(audit.currentUserCount)",
                                            severity: .warning
                                        )
                                    }
                                    
                                    if audit.rootAccounts > 0 {
                                        IssueCard(
                                            title: "UID 0 Accounts Detected",
                                            message: "Root-level accounts found",
                                            severity: .critical
                                        )
                                    }
                                    
                                    if audit.adminAccounts != audit.baselineAdminCount {
                                        IssueCard(
                                            title: "Admin Count Changed",
                                            message: "\(audit.baselineAdminCount) → \(audit.adminAccounts)",
                                            severity: .warning
                                        )
                                    }
                                }
                                .padding()
                                .background(Color.themeDarkGray)
                                .cornerRadius(12)
                            }
                        } else if userEvents.isEmpty {
                            EmptyStateView(
                                icon: "person.2",
                                title: "No user account events",
                                message: "User account security events will appear here in real-time"
                            )
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
    }
    
    private func runAudit() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async(execute: {
            let scriptPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/MacGuardianProject/MacGuardianSuite/auditors/user_account_auditor.sh"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath, "audit"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let auditDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".macguardian/audits")
                
                if let files = try? FileManager.default.contentsOfDirectory(at: auditDir, includingPropertiesForKeys: [.creationDateKey]),
                   let latestFile = files.filter({ $0.lastPathComponent.contains("user_accounts") })
                       .sorted(by: { 
                           let date0 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                           let date1 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                           return date0 > date1
                       })
                       .first,
                   let data = try? Data(contentsOf: latestFile),
                   let audit = try? JSONDecoder().decode(UserAccountAuditResult.self, from: data) {
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
        })
    }
    
    private func loadLatestAudit() {
        let auditDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".macguardian/audits")
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: auditDir, includingPropertiesForKeys: [.creationDateKey]),
              let latestFile = files.filter({ $0.lastPathComponent.contains("user_accounts") })
                  .sorted(by: { 
                      let date0 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                      let date1 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                      return date0 > date1
                  })
                  .first,
              let data = try? Data(contentsOf: latestFile),
              let audit = try? JSONDecoder().decode(UserAccountAuditResult.self, from: data) else {
            return
        }
        
        auditResult = audit
    }
}

struct UserAccountAuditResult: Codable {
    let timestamp: String
    let auditType: String
    let issuesFound: Int
    let currentUserCount: Int
    let baselineUserCount: Int
    let adminAccounts: Int
    let rootAccounts: Int
    let baselineAdminCount: Int
    
    enum CodingKeys: String, CodingKey {
        case timestamp, auditType = "audit_type", issuesFound = "issues_found"
        case currentUserCount = "current_user_count", baselineUserCount = "baseline_user_count"
        case adminAccounts = "admin_accounts", rootAccounts = "root_accounts"
        case baselineAdminCount = "baseline_admin_count"
    }
}

struct UserAccountStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundColor(.themeTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.themeDarkGray)
        .cornerRadius(12)
    }
}

struct IssueCard: View {
    let title: String
    let message: String
    let severity: IssueSeverity
    
    var body: some View {
        HStack {
            Image(systemName: severityIcon)
                .foregroundColor(severityColor)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline.bold())
                Text(message)
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
        switch severity {
        case .critical: return Color(red: 0.9, green: 0.1, blue: 0.3) // Muted red-purple
        case .warning: return .themePurpleLight // Lighter purple
        case .info: return .themePurple // Base purple
        }
    }
    
    private var severityIcon: String {
        switch severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

enum IssueSeverity {
    case critical, warning, info
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.themeTextSecondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.themeTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// Real-time User Account Event Row Component
struct UserAccountEventRow: View {
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
                
                // Show context details if available
                if let changeType = event.context["change_type"]?.value as? String {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .font(.caption2)
                        Text(changeType.capitalized)
                            .font(.caption)
                    }
                    .foregroundColor(.themePurple.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.themePurple.opacity(0.1))
                    .cornerRadius(4)
                }
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

