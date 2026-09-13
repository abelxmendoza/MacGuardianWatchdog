import SwiftUI

struct PrivacyHeatmapView: View {
    @StateObject private var liveService = LiveUpdateService.shared
    @StateObject private var heatmapModel = PrivacyHeatmapModel()
    @State private var privacyData: TCCPrivacyData?
    @State private var isLoading = false
    
    // Real-time privacy events
    var privacyEvents: [MacGuardianEvent] {
        liveService.privacyEvents
    }
    
    // High-performance sparse matrix counts (O(1) lookups)
    var fullDiskAccessCount: Int {
        heatmapModel.totalCount(for: .fullDiskAccess)
    }
    
    var screenRecordingCount: Int {
        heatmapModel.totalCount(for: .screenRecording)
    }
    
    var microphoneCount: Int {
        heatmapModel.totalCount(for: .microphone)
    }
    
    var cameraCount: Int {
        heatmapModel.totalCount(for: .camera)
    }
    
    var inputMonitoringCount: Int {
        heatmapModel.totalCount(for: .inputMonitoring)
    }
    
    var accessibilityCount: Int {
        heatmapModel.totalCount(for: .accessibility)
    }
    
    var newPermissionsCount: Int {
        privacyEvents.filter { event in
            if let changeType = event.context["change_type"]?.value as? String {
                return changeType.lowercased() == "new"
            }
            return false
        }.count
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "hand.raised.fill")
                        .font(.title)
                        .foregroundColor(.themePurple)
                    VStack(alignment: .leading) {
                        Text("Privacy Permissions")
                            .font(.title.bold())
                        Text("TCC (Transparency, Consent, and Control) monitoring")
                            .font(.subheadline)
                            .foregroundColor(.themeTextSecondary)
                    }
                    Spacer()
                    Button {
                        runAudit()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.themePurple)
                    .disabled(isLoading)
                }
                .padding()

                FeatureInfoCard(
                    icon: "hand.raised.fill",
                    title: "Privacy Permissions",
                    whatItDoes: "Shows every app that has been granted Full Disk Access, Screen Recording, Camera, Microphone, Input Monitoring, or Accessibility - the sensitive macOS permissions tracked by TCC (Apple's permission-consent system) - and flags newly-granted ones.",
                    whyItMatters: "These are the permissions malware actually wants: Screen Recording can capture your passwords as you type them, Input Monitoring can log every keystroke, and Full Disk Access can read anything on the machine. An app you don't recognize holding one of these is worth investigating immediately.",
                    checks: ["Apps with Full Disk Access", "Apps that can record your screen or use the camera/microphone", "Apps with Input Monitoring or Accessibility access", "Permissions granted recently"]
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
                    Text("\(privacyEvents.count) real-time event(s)")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                .padding(.horizontal)
                
                if isLoading {
                    ProgressView("Loading privacy data...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        // Real-time Permission Heatmap
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Permission Overview (Real-Time)")
                                .font(.headline.bold())
                            
                            PrivacyPermissionCard(
                                title: "Full Disk Access",
                                count: fullDiskAccessCount,
                                icon: "externaldrive.fill",
                                color: heatmapColor(count: fullDiskAccessCount, isHighRisk: true)
                            )
                            
                            PrivacyPermissionCard(
                                title: "Screen Recording",
                                count: screenRecordingCount,
                                icon: "rectangle.on.rectangle",
                                color: heatmapColor(count: screenRecordingCount, isHighRisk: true)
                            )
                            
                            PrivacyPermissionCard(
                                title: "Microphone",
                                count: microphoneCount,
                                icon: "mic.fill",
                                color: heatmapColor(count: microphoneCount, isHighRisk: true)
                            )
                            
                            PrivacyPermissionCard(
                                title: "Camera",
                                count: cameraCount,
                                icon: "camera.fill",
                                color: heatmapColor(count: cameraCount, isHighRisk: true)
                            )
                            
                            PrivacyPermissionCard(
                                title: "Input Monitoring",
                                count: inputMonitoringCount,
                                icon: "keyboard",
                                color: heatmapColor(count: inputMonitoringCount, isHighRisk: true)
                            )
                            
                            PrivacyPermissionCard(
                                title: "Accessibility",
                                count: accessibilityCount,
                                icon: "figure.walk",
                                color: heatmapColor(count: accessibilityCount, isHighRisk: false)
                            )
                        }
                        .padding()
                        .background(Color.themeDarkGray)
                        .cornerRadius(12)
                        
                        // Real-time Alerts
                        if newPermissionsCount > 0 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Privacy Alerts")
                                    .font(.headline.bold())
                                
                                AlertBubble(
                                    message: "\(newPermissionsCount) new permission(s) granted",
                                    severity: .warning
                                )
                            }
                            .padding()
                            .background(Color.themeDarkGray)
                            .cornerRadius(12)
                        }
                        
                        // Recent Privacy Events
                        if !privacyEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Recent Privacy Events")
                                    .font(.headline.bold())
                                
                                ForEach(privacyEvents.prefix(10)) { event in
                                    PrivacyEventRow(event: event)
                                }
                            }
                            .padding()
                            .background(Color.themeDarkGray)
                            .cornerRadius(12)
                        }
                        
                        // Static Audit Data (if available)
                        if let data = privacyData {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Last Audit Results")
                                    .font(.headline.bold())
                                
                                Text("Baseline data from last audit")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                            .padding()
                            .background(Color.themeBlack.opacity(0.5))
                            .cornerRadius(8)
                        } else if privacyEvents.isEmpty {
                            EmptyStateView(
                                icon: "hand.raised",
                                title: "No privacy events",
                                message: "Privacy permission changes will appear here in real-time"
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.themeBlack)
        .onAppear {
            loadPrivacyData()
            updateHeatmapFromEvents()
        }
        .onChange(of: privacyEvents.count) { _, _ in
            updateHeatmapFromEvents()
        }
    }
    
    private func updateHeatmapFromEvents() {
        // Update sparse heatmap from real-time events (O(n) where n = events)
        for event in privacyEvents {
            if let permissionStr = event.context["permission"]?.value as? String,
               let appName = event.context["app"]?.value as? String ?? event.context["app_name"]?.value as? String {
                
                // Map permission string to PermissionType
                let permission: PrivacyHeatmapModel.PermissionType?
                if permissionStr.lowercased().contains("full disk") {
                    permission = .fullDiskAccess
                } else if permissionStr.lowercased().contains("screen recording") {
                    permission = .screenRecording
                } else if permissionStr.lowercased().contains("microphone") {
                    permission = .microphone
                } else if permissionStr.lowercased().contains("camera") {
                    permission = .camera
                } else if permissionStr.lowercased().contains("input monitoring") {
                    permission = .inputMonitoring
                } else if permissionStr.lowercased().contains("accessibility") {
                    permission = .accessibility
                } else {
                    permission = nil
                }
                
                if let permission = permission {
                    heatmapModel.incrementPermission(permission: permission, appName: appName)
                }
            }
        }
    }
    
    private func runAudit() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/MacGuardianProject/MacGuardianSuite/privacy/tcc_auditor.sh"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath, "audit"]
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let auditDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".macguardian/audits")
                
                if let files = try? FileManager.default.contentsOfDirectory(at: auditDir, includingPropertiesForKeys: [.creationDateKey]),
                   let latestFile = files.filter({ $0.lastPathComponent.contains("tcc_audit") })
                       .sorted(by: { 
                      let date0 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                      let date1 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                      return date0 > date1
                  })
                       .first,
                   let data = try? Data(contentsOf: latestFile),
                   let privacy = try? JSONDecoder().decode(TCCPrivacyData.self, from: data) {
                    DispatchQueue.main.async {
                        self.privacyData = privacy
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
    
    private func loadPrivacyData() {
        let auditDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".macguardian/audits")
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: auditDir, includingPropertiesForKeys: [.creationDateKey]),
              let latestFile = files.filter({ $0.lastPathComponent.contains("tcc_audit") })
                  .sorted(by: { 
                      let date0 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                      let date1 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                      return date0 > date1
                  })
                  .first,
              let data = try? Data(contentsOf: latestFile),
              let privacy = try? JSONDecoder().decode(TCCPrivacyData.self, from: data) else {
            return
        }
        
        privacyData = privacy
    }
    
    // Heatmap color function - purple-based gradient that fits Omega aesthetic
    private func heatmapColor(count: Int, isHighRisk: Bool) -> Color {
        if count == 0 {
            return .themePurple.opacity(0.3) // Very subtle purple for safe
        } else if count == 1 {
            return .themePurple // Base purple
        } else if count <= 3 {
            return .themePurpleLight // Lighter purple for moderate
        } else {
            // High count - use red but muted to fit dark theme
            return Color(red: 0.9, green: 0.1, blue: 0.3) // Muted red-purple
        }
    }
}

struct TCCPrivacyData: Codable {
    let timestamp: String
    let auditType: String
    let issuesFound: Int
    let fullDiskAccess: Int
    let screenRecording: Int
    let microphone: Int
    let camera: Int
    let inputMonitoring: Int
    let accessibility: Int
    let newPermissions: Int
    
    enum CodingKeys: String, CodingKey {
        case timestamp, auditType = "audit_type", issuesFound = "issues_found"
        case fullDiskAccess = "full_disk_access", screenRecording = "screen_recording"
        case microphone, camera, inputMonitoring = "input_monitoring"
        case accessibility, newPermissions = "new_permissions"
    }
}

struct PrivacyPermissionCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text("\(count) app(s)")
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
            
            Spacer()
            
            if count > 0 {
                // Heatmap intensity indicator (purple dots)
                HStack(spacing: 4) {
                    ForEach(0..<min(count, 5), id: \.self) { _ in
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                    }
                    if count > 5 {
                        Text("+")
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                    }
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.themePurple.opacity(0.5))
            }
        }
        .padding()
        .background(
            // Subtle glow effect for high counts
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.themeBlack.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(count > 0 ? 0.3 : 0.1), lineWidth: 1)
                )
        )
    }
}

struct AlertBubble: View {
    let message: String
    let severity: AlertSeverity
    
    var body: some View {
        HStack {
            Image(systemName: severityIcon)
                .foregroundColor(severityColor)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(severityColor.opacity(0.2))
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

enum AlertSeverity {
    case critical, warning, info
}

// Real-time Privacy Event Row Component
struct PrivacyEventRow: View {
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
                
                // Show permission type if available
                if let permission = event.context["permission"]?.value as? String {
                    HStack {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                        Text(permission)
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

