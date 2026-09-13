import SwiftUI

struct SecurityAuditView: View {
    @EnvironmentObject private var workspace: WorkspaceState
    @StateObject private var vm = SecurityAuditViewModel()
    @State private var selectedCheck: AuditCheck?
    @State private var showCheckDetail = false
    @State private var filterStatus: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title)
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Security Audit")
                        .font(.title.bold())
                        .foregroundColor(.themeText)
                    Text("Comprehensive security posture assessment")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                
                if let lastRun = vm.lastRunDate {
                    Text("Last run: \(lastRun, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
            }
            .padding()
            .background(Color.themeDarkGray)
            
            Divider()
                .background(Color.themePurpleDark)
            
            ScrollView {
                VStack(spacing: 24) {
                    FeatureInfoCard(
                        icon: "checkmark.shield.fill",
                        title: "Security Audit",
                        whatItDoes: "Runs a pass/fail check across the macOS security settings that matter most - FileVault encryption, System Integrity Protection, Gatekeeper, firewall, certificate validity, and launch items - and rolls them into one score.",
                        whyItMatters: "These settings are easy to accidentally disable (a troubleshooting step, an old installer) and easy to forget to re-enable. This is the fastest way to confirm nothing protective got turned off without you noticing.",
                        checks: ["FileVault (disk encryption)", "System Integrity Protection (SIP) and Gatekeeper", "Firewall status", "SSL/TLS certificate validity", "Launch agents and daemons"]
                    )
                    .padding(.horizontal)

                    // Summary Cards
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Audit Summary")
                            .font(.headline)
                            .foregroundColor(.themeText)
                        
                        HStack(spacing: 16) {
                            SummaryCard(
                                title: "Security Score",
                                value: "\(vm.summary.score)",
                                subtitle: "/100",
                                icon: "chart.bar.fill",
                                color: scoreColor(vm.summary.score)
                            )
                            SummaryCard(
                                title: "Passed",
                                value: "\(vm.summary.passed)",
                                subtitle: "checks",
                                icon: "checkmark.circle.fill",
                                color: .green
                            )
                            SummaryCard(
                                title: "Failed",
                                value: "\(vm.summary.failed)",
                                subtitle: "checks",
                                icon: "xmark.circle.fill",
                                color: .red
                            )
                            SummaryCard(
                                title: "Warnings",
                                value: "\(vm.summary.warnings)",
                                subtitle: "checks",
                                icon: "exclamationmark.triangle.fill",
                                color: .yellow
                            )
                        }
                    }
                    .padding()
                    .background(Color.themeDarkGray)
                    .cornerRadius(12)
                    
                    // Filter buttons
                    if !vm.checks.isEmpty {
                        HStack(spacing: 8) {
                            AuditFilterButton(
                                label: "All",
                                isSelected: filterStatus == nil,
                                action: { filterStatus = nil }
                            )
                            AuditFilterButton(
                                label: "Failed",
                                isSelected: filterStatus == "fail",
                                action: { filterStatus = filterStatus == "fail" ? nil : "fail" },
                                color: .red
                            )
                            AuditFilterButton(
                                label: "Warnings",
                                isSelected: filterStatus == "warning",
                                action: { filterStatus = filterStatus == "warning" ? nil : "warning" },
                                color: .yellow
                            )
                            AuditFilterButton(
                                label: "Passed",
                                isSelected: filterStatus == "pass",
                                action: { filterStatus = filterStatus == "pass" ? nil : "pass" },
                                color: .green
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Checks List
                    if vm.loading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Running security audit...")
                                .font(.subheadline)
                                .foregroundColor(.themeTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else if vm.checks.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.themeTextSecondary)
                            Text("No audit results")
                                .font(.headline)
                                .foregroundColor(.themeText)
                            if let error = vm.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("Click 'Run Audit' to start")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Audit Checks (\(filteredChecks.count))")
                                .font(.headline)
                                .foregroundColor(.themeText)
                            
                            ForEach(filteredChecks) { check in
                                Button {
                                    selectedCheck = check
                                    showCheckDetail = true
                                } label: {
                                    AuditCheckRow(check: check)
                                        .background(Color.themeDarkGray.opacity(0.5))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                        .background(Color.themeDarkGray)
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .background(Color.themeBlack)
        }
        .background(Color.themeBlack)
        .task {
            if vm.checks.isEmpty {
                await vm.run(repositoryPath: workspace.repositoryPath)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await vm.run(repositoryPath: workspace.repositoryPath)
                    }
                } label: {
                    Label("Run Audit", systemImage: "play.fill")
                }
                .disabled(vm.loading)
            }
        }
        .sheet(item: $selectedCheck) { check in
            NavigationView {
                AuditCheckDetailView(check: check)
                    .navigationTitle("Check Details")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showCheckDetail = false
                                selectedCheck = nil
                            }
                        }
                    }
            }
            .frame(minWidth: 600, minHeight: 400)
        }
    }
    
    private var filteredChecks: [AuditCheck] {
        if let status = filterStatus {
            return vm.checks.filter { $0.status.lowercased() == status.lowercased() }
        }
        return vm.checks
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .yellow }
        return .red
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title.bold())
                    .foregroundColor(.themeText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
            
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

struct AuditCheckRow: View {
    let check: AuditCheck
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(colorFor(check.status))
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(check.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.themeText)
                
                Text(check.description)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
                    .lineLimit(2)
                
                if let category = check.category {
                    Text(category)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.themePurple.opacity(0.2))
                        .foregroundColor(.themePurple)
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            Text(check.status.capitalized)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(colorFor(check.status).opacity(0.2))
                .foregroundColor(colorFor(check.status))
                .cornerRadius(6)
        }
        .padding(.vertical, 8)
    }
    
    func colorFor(_ status: String) -> Color {
        switch status.lowercased() {
        case "fail": return .red
        case "warning": return .yellow
        case "pass": return .green
        default: return .gray
        }
    }
}

struct AuditCheckDetailView: View {
    let check: AuditCheck
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Circle()
                        .fill(colorFor(check.status))
                        .frame(width: 12, height: 12)
                    Text(check.status.capitalized)
                        .font(.headline)
                        .foregroundColor(colorFor(check.status))
                    Spacer()
                }
                
                Text(check.name)
                    .font(.title2.bold())
                    .foregroundColor(.themeText)
                
                Text(check.description)
                    .font(.body)
                    .foregroundColor(.themeText)
                
                Divider()
                
                if let category = check.category {
                    AuditDetailRow(label: "Category", value: category)
                }
                
                if let severity = check.severity {
                    AuditDetailRow(label: "Severity", value: severity)
                }
                
                if let recommendation = check.recommendation {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommendation")
                            .font(.headline)
                            .foregroundColor(.themeText)
                        Text(recommendation)
                            .font(.body)
                            .foregroundColor(.themeText)
                            .padding()
                            .background(Color.themePurple.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
    }
    
    func colorFor(_ status: String) -> Color {
        switch status.lowercased() {
        case "fail": return .red
        case "warning": return .yellow
        case "pass": return .green
        default: return .gray
        }
    }
}

struct AuditFilterButton: View {
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

struct AuditDetailRow: View {
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

