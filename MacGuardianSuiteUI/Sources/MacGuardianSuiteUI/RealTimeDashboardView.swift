import SwiftUI

struct RealTimeDashboardView: View {
    @StateObject private var liveService = LiveUpdateService.shared
    @State private var selectedFilter: EventFilter = .all
    @State private var showClearConfirmation = false
    
    enum EventFilter: String, CaseIterable {
        case all = "All Events"
        case critical = "Critical"
        case high = "High"
        case medium = "Medium"
        case filesystem = "Filesystem"
        case process = "Process"
        case network = "Network"
    }
    
    var filteredEvents: [MacGuardianEvent] {
        let events = liveService.events
        
        switch selectedFilter {
        case .all:
            return events
        case .critical:
            return liveService.criticalEvents
        case .high:
            return liveService.highSeverityEvents
        case .medium:
            return events.filter { $0.severity.lowercased() == "medium" }
        case .filesystem:
            return liveService.filesystemEvents
        case .process:
            return liveService.processEvents
        case .network:
            return liveService.networkEvents
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    LogoView(size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Real-Time Threat Monitor")
                            .font(.title.bold())
                            .foregroundColor(.themeText)
                        Text("Live security event feed from monitoring daemon")
                            .font(.subheadline)
                            .foregroundColor(.themeTextSecondary)
                    }
                    Spacer()
                    
                    // Connection status
                    HStack(spacing: 8) {
                        Circle()
                            .fill(liveService.isConnected ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                        Text(liveService.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                    }
                }
                .padding(.horizontal)

                FeatureInfoCard(
                    icon: "dot.radiowaves.left.and.right",
                    title: "Real-Time Threat Monitor",
                    whatItDoes: "Streams events the moment the background monitoring daemon sees them - a file change, a new process, a network connection - over a local WebSocket, instead of waiting for a scheduled scan.",
                    whyItMatters: "Some attacks unfold in seconds. A daily scan can miss a process that started and quit in that window; this catches it as it happens. \"Disconnected\" here means the daemon isn't running, so nothing is being watched live - the other dashboards fall back to their own on-demand scans.",
                    checks: ["File integrity changes as they happen", "New or terminated processes", "New network connections", "Whether the monitoring daemon is currently running"]
                )
                .padding(.horizontal)

                // Stats cards
                HStack(spacing: 16) {
                    StatCard(
                        title: "Total Events",
                        value: "\(liveService.events.count)",
                        icon: "bell.fill",
                        color: .themePurple
                    )
                    StatCard(
                        title: "Critical",
                        value: "\(liveService.criticalEvents.count)",
                        icon: "exclamationmark.octagon.fill",
                        color: Color(red: 0.9, green: 0.1, blue: 0.3) // Muted red-purple
                    )
                    StatCard(
                        title: "High Severity",
                        value: "\(liveService.highSeverityEvents.count)",
                        icon: "exclamationmark.triangle.fill",
                        color: Color(red: 0.8, green: 0.3, blue: 0.5) // Purple-red blend
                    )
                    StatCard(
                        title: "Last Update",
                        value: liveService.lastUpdate != nil ? formatTime(liveService.lastUpdate!) : "Never",
                        icon: "clock.fill",
                        color: .themePurple
                    )
                }
                .padding(.horizontal)
                
                // Controls
                HStack(spacing: 12) {
                    // Filter picker
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(EventFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    
                    Spacer()
                    
                    // Clear events
                    Button {
                        showClearConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                            Text("Clear")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.horizontal)
                
                // Event list
                if filteredEvents.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green.opacity(0.5))
                        Text("No events found")
                            .font(.headline)
                            .foregroundColor(.themeTextSecondary)
                        Text("Security events will appear here when detected by the monitoring daemon")
                            .font(.subheadline)
                            .foregroundColor(.themeTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredEvents.prefix(100)) { event in
                            EventRowView(event: event)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Color.themeBlack)
        .alert("Clear All Events?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    await liveService.clearEvents()
                }
            }
        } message: {
            Text("This will permanently delete all events. This action cannot be undone.")
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct MonitorDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text("\(label):")
                .font(.caption.bold())
                .foregroundColor(.themeTextSecondary)
            Text(value)
                .font(.caption)
                .foregroundColor(.themeText)
            Spacer()
        }
    }
}

#Preview {
    RealTimeDashboardView()
}

