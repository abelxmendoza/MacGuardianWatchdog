import SwiftUI
import Foundation

// MARK: - Omega Guardian Console View

struct OmegaGuardianView: View {
    @StateObject private var incidentStore = IncidentStore.shared
    @ObservedObject private var alertEngine = AlertEngine.shared
    @State private var selectedTab: AlertTab = .incidents
    @State private var filterSeverity: ThreatSeverity? = nil
    @State private var showAcknowledged = true
    @State private var showResolved = false
    
    enum AlertTab: String, CaseIterable {
        case incidents = "Incidents"
        case rules = "Rules"
        case stats = "Statistics"
        
        var icon: String {
            switch self {
            case .incidents: return "exclamationmark.triangle.fill"
            case .rules: return "list.bullet.rectangle"
            case .stats: return "chart.bar.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title)
                    .foregroundColor(Color(red: 0.54, green: 0.16, blue: 0.95)) // Omega Purple
                VStack(alignment: .leading, spacing: 4) {
                    Text("OMEGA GUARDIAN CONSOLE")
                        .font(.title.bold())
                        .foregroundColor(Color(red: 0.54, green: 0.16, blue: 0.95))
                    Text("Non-spam, high-signal alert system")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                
                // Quick stats
                HStack(spacing: 16) {
                    OmegaStatBadge(
                        label: "Active",
                        value: "\(incidentStore.unacknowledgedCount)",
                        color: .orange
                    )
                    OmegaStatBadge(
                        label: "Critical",
                        value: "\(incidentStore.criticalCount)",
                        color: .red
                    )
                }
            }
            .padding()
            .background(Color(red: 0.05, green: 0.05, blue: 0.07)) // Jet Black Panel
            
            Divider()
                .background(Color.themePurpleDark)

            FeatureInfoCard(
                icon: "shield.lefthalf.filled",
                title: "Omega Guardian",
                whatItDoes: "Correlates events from every other monitor against a rule set (throttled and de-duplicated) and turns the ones that matter into a single incident feed, instead of a raw stream of every event the suite sees.",
                whyItMatters: "A monitor that alerts on everything trains you to ignore it. This exists specifically to be \"non-spam, high-signal\" - fewer alerts, but ones worth actually reading, with rules you can tune in the Rules tab.",
                checks: ["Events matched against configurable alert rules", "Severity and throttling to avoid duplicate/repeat alerts", "Acknowledged vs. unresolved incidents"]
            )
            .padding(.horizontal)
            .padding(.top, 12)

            // Tab selector
            HStack(spacing: 0) {
                ForEach(AlertTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                            Text(tab.rawValue)
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(selectedTab == tab ? .white : .themeTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedTab == tab ? Color(red: 0.54, green: 0.16, blue: 0.95) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.themeDarkGray.opacity(0.5))
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch selectedTab {
                    case .incidents:
                        IncidentFeedTab(
                            incidents: filteredIncidents,
                            incidentStore: incidentStore
                        )
                    case .rules:
                        AlertRulesTab(alertEngine: alertEngine)
                    case .stats:
                        AlertStatsTab(incidentStore: incidentStore)
                    }
                }
                .padding()
            }
            .background(Color.themeBlack)
        }
        .background(Color.themeBlack)
    }
    
    private var filteredIncidents: [Incident] {
        var filtered = incidentStore.incidents
        
        if let severity = filterSeverity {
            filtered = filtered.filter { $0.severity == severity }
        }
        
        if !showAcknowledged {
            filtered = filtered.filter { !$0.acknowledged }
        }
        
        if !showResolved {
            filtered = filtered.filter { !$0.resolved }
        }
        
        return filtered
    }
}

// MARK: - Incident Feed Tab

struct IncidentFeedTab: View {
    let incidents: [Incident]
    @ObservedObject var incidentStore: IncidentStore
    @State private var selectedIncident: Incident?
    @State private var showDetail = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Filters
            HStack(spacing: 12) {
                FilterChip(
                    label: "All",
                    isSelected: true,
                    action: {}
                )
                FilterChip(
                    label: "Critical",
                    isSelected: false,
                    action: {},
                    color: .red
                )
                FilterChip(
                    label: "High",
                    isSelected: false,
                    action: {},
                    color: .orange
                )
                
                Spacer()
                
                Button {
                    incidentStore.clearResolved()
                } label: {
                    Label("Clear Resolved", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            
            if incidents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("No Active Incidents")
                        .font(.headline)
                        .foregroundColor(.themeText)
                    Text("All systems secure")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ForEach(incidents) { incident in
                    Button {
                        selectedIncident = incident
                        showDetail = true
                    } label: {
                        IncidentRow(incident: incident)
                            .background(Color.themeDarkGray.opacity(0.5))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selectedIncident) { incident in
            IncidentDetailView(incident: incident, incidentStore: incidentStore)
        }
    }
}

struct IncidentRow: View {
    let incident: Incident
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(colorFor(incident.severity))
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(incident.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.themeText)
                    
                    if incident.acknowledged {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    
                    if incident.resolved {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
                
                Text(incident.message)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Label(incident.sourceModule, systemImage: "tag.fill")
                        .font(.caption2)
                        .foregroundColor(.themePurple)
                    
                    Text(incident.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.themeTextSecondary)
                }
            }
            
            Spacer()
            
            Text(incident.severity.displayName)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(colorFor(incident.severity).opacity(0.2))
                .foregroundColor(colorFor(incident.severity))
                .cornerRadius(6)
        }
        .padding(.vertical, 8)
    }
    
    func colorFor(_ severity: ThreatSeverity) -> Color {
        switch severity {
        case .critical: return Color(red: 1, green: 0.18, blue: 0.39) // Omega Critical Red-Pink
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }
}

struct IncidentDetailView: View {
    let incident: Incident
    @ObservedObject var incidentStore: IncidentStore
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Circle()
                            .fill(colorFor(incident.severity))
                            .frame(width: 12, height: 12)
                        Text(incident.severity.displayName)
                            .font(.headline)
                            .foregroundColor(colorFor(incident.severity))
                        Spacer()
                    }
                    
                    Text(incident.title)
                        .font(.title2.bold())
                        .foregroundColor(.themeText)
                    
                    Text(incident.message)
                        .font(.body)
                        .foregroundColor(.themeText)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        OmegaDetailRow(label: "Source Module", value: incident.sourceModule)
                        OmegaDetailRow(label: "Timestamp", value: incident.timestamp.formatted(date: .abbreviated, time: .shortened))
                        OmegaDetailRow(label: "Status", value: incident.resolved ? "Resolved" : (incident.acknowledged ? "Acknowledged" : "Active"))
                    }
                    
                    if !incident.metadata.isEmpty {
                        Divider()
                        Text("Metadata")
                            .font(.headline)
                            .foregroundColor(.themeText)
                        
                        ForEach(Array(incident.metadata.keys.sorted()), id: \.self) { key in
                            if let value = incident.metadata[key] {
                                OmegaDetailRow(label: key, value: value)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        if !incident.acknowledged {
                            Button {
                                incidentStore.acknowledge(incident)
                                dismiss()
                            } label: {
                                Label("Acknowledge", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                        
                        if !incident.resolved {
                            Button {
                                incidentStore.resolve(incident)
                                dismiss()
                            } label: {
                                Label("Resolve", systemImage: "checkmark.seal")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Incident Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    func colorFor(_ severity: ThreatSeverity) -> Color {
        switch severity {
        case .critical: return Color(red: 1, green: 0.18, blue: 0.39)
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }
}

// MARK: - Alert Rules Tab

struct AlertRulesTab: View {
    @ObservedObject var alertEngine: AlertEngine
    @State private var rules: [AlertRule] = []
    @State private var showAddRule = false
    @State private var editingRule: AlertRule?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Alert Rules")
                    .font(.headline)
                    .foregroundColor(.themeText)
                Spacer()
                Button {
                    showAddRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.54, green: 0.16, blue: 0.95))
            }
            
            if rules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.themeTextSecondary)
                    Text("No Alert Rules")
                        .font(.headline)
                        .foregroundColor(.themeText)
                    Text("Add rules to start monitoring")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ForEach(rules) { rule in
                    AlertRuleRow(rule: rule, alertEngine: alertEngine)
                        .background(Color.themeDarkGray.opacity(0.5))
                        .cornerRadius(8)
                }
            }
        }
        .onAppear {
            rules = alertEngine.getAllRules()
        }
        .sheet(isPresented: $showAddRule) {
            AddAlertRuleView(alertEngine: alertEngine) {
                rules = alertEngine.getAllRules()
            }
        }
    }
}

struct AlertRuleRow: View {
    let rule: AlertRule
    @ObservedObject var alertEngine: AlertEngine
    
    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { newValue in
                    var updated = rule
                    updated.enabled = newValue
                    alertEngine.updateRule(updated)
                }
            ))
            .toggleStyle(.switch)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.themeText)
                
                if let description = rule.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                
                HStack(spacing: 8) {
                    Text(rule.condition.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.themePurple.opacity(0.2))
                        .foregroundColor(.themePurple)
                        .cornerRadius(4)
                    
                    Text(rule.severity.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(severityColor(rule.severity).opacity(0.2))
                        .foregroundColor(severityColor(rule.severity))
                        .cornerRadius(4)
                    
                    Text("Throttle: \(rule.throttleMinutes)m")
                        .font(.caption2)
                        .foregroundColor(.themeTextSecondary)
                }
            }
            
            Spacer()
            
            Button {
                alertEngine.deleteRule(rule)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    func severityColor(_ severity: ThreatSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }
}

// MARK: - Alert Statistics Tab

struct AlertStatsTab: View {
    @ObservedObject var incidentStore: IncidentStore
    @ObservedObject var alertEngine = AlertEngine.shared
    
    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 16) {
                OmegaStatCard(
                    title: "Total Incidents",
                    value: "\(incidentStore.incidents.count)",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange
                )
                OmegaStatCard(
                    title: "Active",
                    value: "\(incidentStore.unacknowledgedCount)",
                    icon: "bell.fill",
                    color: .red
                )
                OmegaStatCard(
                    title: "Critical",
                    value: "\(incidentStore.criticalCount)",
                    icon: "exclamationmark.octagon.fill",
                    color: Color(red: 1, green: 0.18, blue: 0.39)
                )
                OmegaStatCard(
                    title: "Rules Enabled",
                    value: "\(alertEngine.enabledCount)",
                    icon: "list.bullet.rectangle",
                    color: Color(red: 0.54, green: 0.16, blue: 0.95)
                )
            }
            
            // Incidents by severity
            VStack(alignment: .leading, spacing: 12) {
                Text("Incidents by Severity")
                    .font(.headline)
                    .foregroundColor(.themeText)
                
                ForEach(ThreatSeverity.allCases, id: \.self) { severity in
                    let count = incidentStore.incidents.filter { $0.severity == severity && !$0.resolved }.count
                    if count > 0 {
                        HStack {
                            Circle()
                                .fill(severityColor(severity))
                                .frame(width: 12, height: 12)
                            Text(severity.displayName)
                            Spacer()
                            Text("\(count)")
                                .font(.headline)
                                .foregroundColor(.themePurple)
                        }
                        .padding()
                        .background(Color.themeDarkGray)
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    func severityColor(_ severity: ThreatSeverity) -> Color {
        switch severity {
        case .critical: return Color(red: 1, green: 0.18, blue: 0.39)
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }
}

// MARK: - Supporting Views

struct OmegaStatBadge: View {
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

struct OmegaStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            Text(value)
                .font(.title.bold())
                .foregroundColor(.themeText)
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

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    var color: Color = Color(red: 0.54, green: 0.16, blue: 0.95)
    
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

struct OmegaDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption.bold())
                .foregroundColor(.themeTextSecondary)
            Text(value)
                .font(.caption)
                .foregroundColor(.themeText)
            Spacer()
        }
    }
}

// MARK: - Add Alert Rule View

struct AddAlertRuleView: View {
    @ObservedObject var alertEngine: AlertEngine
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String = ""
    @State private var selectedSeverity: ThreatSeverity = .medium
    @State private var selectedCondition: AlertCondition = .iocMatch
    @State private var throttleMinutes: Int = 5
    @State private var description: String = ""
    @State private var customPattern: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Rule Configuration") {
                    TextField("Rule Name", text: $name)
                    
                    Picker("Severity", selection: $selectedSeverity) {
                        ForEach(ThreatSeverity.allCases, id: \.self) { severity in
                            Text(severity.displayName).tag(severity)
                        }
                    }
                    
                    Picker("Condition", selection: $selectedCondition) {
                        Text("IOC Match").tag(AlertCondition.iocMatch)
                        Text("Process Behavior").tag(AlertCondition.processBehavior)
                        Text("Network Anomaly").tag(AlertCondition.networkAnomaly)
                        Text("File Modification").tag(AlertCondition.fileModification)
                        Text("Custom Pattern").tag(AlertCondition.custom(pattern: ""))
                    }
                    
                    if case .custom = selectedCondition {
                        TextField("Custom Pattern", text: $customPattern)
                    }
                    
                    Stepper("Throttle: \(throttleMinutes) minutes", value: $throttleMinutes, in: 0...60)
                    
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Alert Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let condition: AlertCondition
                        if case .custom = selectedCondition {
                            condition = .custom(pattern: customPattern)
                        } else {
                            condition = selectedCondition
                        }
                        
                        let rule = AlertRule(
                            name: name,
                            severity: selectedSeverity,
                            condition: condition,
                            enabled: true,
                            throttleMinutes: throttleMinutes,
                            description: description.isEmpty ? nil : description
                        )
                        
                        alertEngine.addRule(rule)
                        onSave()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

