import SwiftUI

struct IncidentTimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()
    @State private var timelineData: TimelineData?
    @State private var selectedFilter: TimelineFilter = .all
    
    enum TimelineFilter: String, CaseIterable {
        case all = "All"
        case critical = "Critical"
        case high = "High"
        case process = "Process"
        case network = "Network"
        case filesystem = "Filesystem"
        case ids = "IDS"
    }
    
    // Real-time events from optimized view model
    var timelineEvents: [MacGuardianEvent] {
        viewModel.events
    }
    
    var filteredEvents: [MacGuardianEvent] {
        var events = timelineEvents
        
        switch selectedFilter {
        case .all:
            break
        case .critical:
            events = events.filter { $0.severity.lowercased() == "critical" }
        case .high:
            events = events.filter { $0.severity.lowercased() == "high" }
        case .process:
            events = events.filter { $0.event_type == "process_anomaly" }
        case .network:
            events = events.filter { $0.event_type == "network_connection" }
        case .filesystem:
            events = events.filter { $0.event_type == "file_integrity_change" }
        case .ids:
            events = events.filter { 
                $0.event_type == "ids_alert" || 
                $0.event_type == "incident.detected" 
            }
        }
        
        return events
    }
    
    var severityCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for event in timelineEvents {
            let severity = event.severity.lowercased()
            counts[severity, default: 0] += 1
        }
        return counts
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "clock.fill")
                    .font(.title)
                    .foregroundColor(.themePurple)
                VStack(alignment: .leading) {
                    Text("Incident Timeline")
                        .font(.title.bold())
                    Text("Chronological security events")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                Button {
                    loadTimeline()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.themePurple)
                .disabled(viewModel.isLoading)
            }
            .padding()

            FeatureInfoCard(
                icon: "clock.fill",
                title: "Incident Timeline",
                whatItDoes: "Merges every event from every monitor - process, network, filesystem, and intrusion-detection - into one chronological feed, so you can see what happened, in what order, across the whole system.",
                whyItMatters: "A real incident is rarely one isolated event; it's a sequence (a file changed, then a process spawned, then it phoned home). Looking at each monitor's log in isolation hides that sequence - the timeline reconstructs it.",
                checks: ["File integrity changes", "Process anomalies", "Network connections", "Intrusion-detection (IDS) alerts, ranked by severity"]
            )
            .padding(.horizontal)

            Divider()

            // Filter Picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(TimelineFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Real-time Connection Status
            ConnectionStatusIndicator(
                isConnected: LiveUpdateService.shared.isConnected,
                lastUpdate: LiveUpdateService.shared.lastUpdate
            )
            
            // Timeline
            if viewModel.isLoading {
                ProgressView("Loading timeline...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Statistics
                        HStack(spacing: 16) {
                            StatCard(
                                title: "Total Events",
                                value: "\(timelineEvents.count)",
                                icon: "list.bullet",
                                color: .themePurple
                            )
                            StatCard(
                                title: "Critical",
                                value: "\(severityCounts["critical"] ?? 0)",
                                icon: "exclamationmark.triangle.fill",
                                color: Color(red: 0.9, green: 0.1, blue: 0.3)
                            )
                            StatCard(
                                title: "High",
                                value: "\(severityCounts["high"] ?? 0)",
                                icon: "exclamationmark.circle.fill",
                                color: Color(red: 0.8, green: 0.3, blue: 0.5)
                            )
                        }
                        .padding()
                        
                        // Real-time Events grouped by date
                        if filteredEvents.isEmpty {
                            EmptyStateView(
                                icon: "clock",
                                title: "No events",
                                message: "Security events will appear here in real-time"
                            )
                            .padding()
                        } else {
                            ForEach(groupedRealTimeEvents, id: \.date) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.date)
                                        .font(.headline.bold())
                                        .foregroundColor(.themeTextSecondary)
                                        .padding(.horizontal)
                                    
                                    ForEach(group.events) { event in
                                        RealTimeTimelineEventRow(event: event)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.themeBlack)
        .onAppear {
            loadTimeline()
        }
    }
    
    private var groupedRealTimeEvents: [RealTimeEventGroup] {
        let events = filteredEvents
        let grouped = Dictionary(grouping: events) { event in
            event.timestamp.prefix(10) // Date part (YYYY-MM-DD)
        }
        
        return grouped.map { date, events in
            RealTimeEventGroup(date: String(date), events: events)
        }.sorted { $0.date > $1.date }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func loadTimeline() {
        viewModel.isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let timelinePath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".macguardian/timeline.json")
            
            if let data = try? Data(contentsOf: timelinePath),
               let timeline = try? JSONDecoder().decode(TimelineData.self, from: data) {
                DispatchQueue.main.async {
                    self.timelineData = timeline
                    self.viewModel.isLoading = false
                }
            } else {
                // Try to generate timeline
                let scriptPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/MacGuardianProject/MacGuardianSuite/outputs/timeline_formatter.py"
                let eventDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".macguardian/events")
                let outputPath = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".macguardian/timeline.json")
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = [scriptPath, eventDir.path, outputPath.path]
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    if let data = try? Data(contentsOf: outputPath),
                       let timeline = try? JSONDecoder().decode(TimelineData.self, from: data) {
                        DispatchQueue.main.async {
                            self.timelineData = timeline
                            self.viewModel.isLoading = false
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.viewModel.isLoading = false
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.viewModel.isLoading = false
                    }
                }
            }
        }
    }
}

struct TimelineData: Codable {
    let timestamp: String
    let totalEvents: Int
    let eventTypes: [String: Int]
    let severityCounts: [String: Int]
    let timeline: [TimelineEventItem]
    
    enum CodingKeys: String, CodingKey {
        case timestamp, totalEvents = "total_events"
        case eventTypes = "event_types"
        case severityCounts = "severity_counts"
        case timeline
    }
}

struct TimelineEventItem: Codable, Identifiable {
    let id: String
    let time: String
    let type: String
    let severity: String
    let message: String
    let details: [String: AnyCodable]
    
    init(id: String = UUID().uuidString, time: String, type: String, severity: String, message: String, details: [String: AnyCodable] = [:]) {
        self.id = id
        self.time = time
        self.type = type
        self.severity = severity
        self.message = message
        self.details = details
    }
}

struct EventGroup {
    let date: String
    let events: [TimelineEventItem]
}

struct TimelineEventRow: View {
    let event: TimelineEventItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Severity indicator
            Circle()
                .fill(severityColor)
                .frame(width: 12, height: 12)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.type.uppercased())
                        .font(.caption.bold())
                        .foregroundColor(.themeTextSecondary)
                    Spacer()
                    Text(formatTime(event.time))
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                
                Text(event.message)
                    .font(.subheadline)
                    .foregroundColor(.themeText)
                
                if event.severity.lowercased() != "info" {
                    HStack {
                        Image(systemName: severityIcon)
                            .font(.caption2)
                        Text(event.severity.uppercased())
                            .font(.caption2.bold())
                    }
                    .foregroundColor(severityColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(severityColor.opacity(0.2))
                    .cornerRadius(4)
                }
            }
        }
        .padding()
        .background(Color.themeDarkGray)
        .cornerRadius(10)
    }
    
    private var severityColor: Color {
        switch event.severity.lowercased() {
        case "critical": return Color(red: 0.9, green: 0.1, blue: 0.3) // Muted red-purple
        case "high": return Color(red: 0.8, green: 0.3, blue: 0.5) // Purple-red blend
        case "warning", "medium": return .themePurpleLight // Lighter purple
        default: return .themePurple // Base purple
        }
    }
    
    private var severityIcon: String {
        switch event.severity.lowercased() {
        case "critical": return "exclamationmark.triangle.fill"
        case "high": return "exclamationmark.circle.fill"
        default: return "info.circle.fill"
        }
    }
    
    private func formatTime(_ time: String) -> String {
        // Extract time from ISO8601 timestamp
        if time.count > 10 {
            return String(time.dropFirst(11).prefix(5)) // HH:MM
        }
        return time
    }
}

// Real-time Timeline Event Row Component
struct RealTimeTimelineEventRow: View {
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
                    Text(event.event_type.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.caption.bold())
                        .foregroundColor(.themeTextSecondary)
                    Spacer()
                    if let date = event.date {
                        Text(formatTime(date))
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                    } else {
                        Text(formatTime(event.timestamp))
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                    }
                }
                
                Text(event.message)
                    .font(.subheadline)
                    .foregroundColor(.themeText)
                
                if event.severity.lowercased() != "info" && event.severity.lowercased() != "low" {
                    HStack {
                        Image(systemName: severityIcon)
                            .font(.caption2)
                        Text(event.severity.uppercased())
                            .font(.caption2.bold())
                    }
                    .foregroundColor(event.severityColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(event.severityColor.opacity(0.2))
                    .cornerRadius(4)
                }
                
                // Show source
                HStack {
                    Image(systemName: "tag.fill")
                        .font(.caption2)
                    Text(event.source)
                        .font(.caption)
                }
                .foregroundColor(.themePurple.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.themePurple.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding()
        .background(Color.themeDarkGray)
        .cornerRadius(10)
    }
    
    private var severityIcon: String {
        switch event.severity.lowercased() {
        case "critical": return "exclamationmark.triangle.fill"
        case "high": return "exclamationmark.circle.fill"
        default: return "info.circle.fill"
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatTime(_ timestamp: String) -> String {
        // Extract time from ISO8601 timestamp
        if timestamp.count > 10 {
            return String(timestamp.dropFirst(11).prefix(5)) // HH:MM
        }
        return timestamp
    }
}

struct RealTimeEventGroup {
    let date: String
    let events: [MacGuardianEvent]
}

