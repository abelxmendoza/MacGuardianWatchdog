import SwiftUI

struct BlueTeamDashboardView: View {
    @EnvironmentObject private var workspace: WorkspaceState
    @StateObject private var vm = BlueTeamViewModel()
    @State private var selectedEvent: ThreatEvent?
    @State private var showEventDetail = false
    @State private var filterSeverity: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blue Team Dashboard")
                        .font(.title.bold())
                        .foregroundColor(.themeText)
                    Text("Real-time security monitoring and threat detection")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                
                // Quick stats
                HStack(spacing: 16) {
                    if vm.criticalEventsCount > 0 {
                        BlueTeamStatBadge(
                            label: "Critical",
                            value: "\(vm.criticalEventsCount)",
                            color: .red
                        )
                    }
                    if vm.highSeverityEventsCount > 0 {
                        BlueTeamStatBadge(
                            label: "High",
                            value: "\(vm.highSeverityEventsCount)",
                            color: .orange
                        )
                    }
                }
            }
            .padding()
            .background(Color.themeDarkGray)
            
            Divider()
                .background(Color.themePurpleDark)
            
            ScrollView {
                VStack(spacing: 24) {
                    FeatureInfoCard(
                        icon: "shield.lefthalf.filled",
                        title: "Blue Team Dashboard",
                        whatItDoes: "Runs behavioral threat detection: process anomalies, suspicious network connections, filesystem anomalies, and pattern-based threat hunting, then scores each finding by severity.",
                        whyItMatters: "\"Blue team\" means playing defense the way an attacker plays offense - looking for the subtle signs of compromise (an odd parent-child process relationship, a connection to a C2-style server) rather than waiting for antivirus to recognize a known signature.",
                        checks: ["Running processes and their relationships", "Outbound network connections", "Filesystem anomalies", "Behavioral patterns matched against known attack techniques"]
                    )
                    .padding(.horizontal)

                    // System Metrics
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("System Metrics")
                                .font(.headline)
                                .foregroundColor(.themeText)
                            Spacer()
                            if vm.isLoadingStats {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        
                        BlueTeamCharts.SystemStatsGrid(stats: vm.stats)
                    }
                    .padding()
                    .background(Color.themeDarkGray)
                    .cornerRadius(12)
                    
                    // Additional stats
                    if let processCount = vm.stats.processCount {
                        HStack(spacing: 16) {
                            BlueTeamStatCard(
                                title: "Processes",
                                value: "\(processCount)",
                                icon: "cpu",
                                color: .blue
                            )
                            if let connCount = vm.stats.connectionCount {
                                BlueTeamStatCard(
                                    title: "Connections",
                                    value: "\(connCount)",
                                    icon: "network",
                                    color: .green
                                )
                            }
                        }
                    }
                    
                    // Recent Events
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Threat Events")
                                .font(.headline)
                                .foregroundColor(.themeText)
                            Spacer()
                            
                            // Filter buttons
                            HStack(spacing: 8) {
                                BlueTeamFilterButton(
                                    label: "All",
                                    isSelected: filterSeverity == nil,
                                    action: { filterSeverity = nil }
                                )
                                BlueTeamFilterButton(
                                    label: "Critical",
                                    isSelected: filterSeverity == "critical",
                                    action: { filterSeverity = filterSeverity == "critical" ? nil : "critical" },
                                    color: .red
                                )
                                BlueTeamFilterButton(
                                    label: "High",
                                    isSelected: filterSeverity == "high",
                                    action: { filterSeverity = filterSeverity == "high" ? nil : "high" },
                                    color: .orange
                                )
                            }
                            
                            if vm.isLoadingEvents {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        
                        if filteredEvents.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.green)
                                Text("No threats detected")
                                    .font(.headline)
                                    .foregroundColor(.themeText)
                                Text("All systems appear secure")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(filteredEvents) { event in
                                Button {
                                    selectedEvent = event
                                    showEventDetail = true
                                } label: {
                                    BlueTeamCharts.EventRow(event: event)
                                        .background(Color.themeDarkGray.opacity(0.5))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                    .background(Color.themeDarkGray)
                    .cornerRadius(12)
                }
                .padding()
            }
            .background(Color.themeBlack)
        }
        .background(Color.themeBlack)
        .onAppear {
            vm.repositoryPath = workspace.repositoryPath
            Task {
                await vm.refresh()
            }
            vm.startAutoRefresh()
        }
        .onDisappear {
            vm.stopAutoRefresh()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.repositoryPath = workspace.repositoryPath
                    Task {
                        await vm.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(vm.isLoadingEvents || vm.isLoadingStats)
            }
            
            ToolbarItem(placement: .automatic) {
                Button {
                    vm.clearEvents()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
        .sheet(item: $selectedEvent) { event in
            NavigationView {
                BlueTeamCharts.EventDetailView(event: event)
                    .navigationTitle("Event Details")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showEventDetail = false
                                selectedEvent = nil
                            }
                        }
                    }
            }
            .frame(minWidth: 600, minHeight: 400)
        }
    }
    
    private var filteredEvents: [ThreatEvent] {
        if let severity = filterSeverity {
            return vm.events.filter { $0.severity.lowercased() == severity.lowercased() }
        }
        return vm.events
    }
}

struct BlueTeamStatBadge: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.themeTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct BlueTeamFilterButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    var color: Color = .themePurple
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : Color.themeDarkGray)
                .foregroundColor(isSelected ? .white : .themeTextSecondary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct BlueTeamStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundColor(.themeText)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.themeDarkGray)
        .cornerRadius(12)
    }
}

