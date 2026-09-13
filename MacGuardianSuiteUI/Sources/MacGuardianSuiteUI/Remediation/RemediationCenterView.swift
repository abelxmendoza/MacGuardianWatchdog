import SwiftUI

struct RemediationCenterView: View {
    @StateObject private var vm = RemediationViewModel()
    @State private var selectedAction: RemediationAction?
    @State private var showActionDetail = false
    @State private var filterImpact: String? = nil
    @State private var showDryRunConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remediation Center")
                        .font(.title.bold())
                        .foregroundColor(.themeText)
                    Text("Automated security fixes and remediation actions")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                
                if vm.highImpactActions.count > 0 {
                    RemediationStatBadge(
                        label: "High Impact",
                        value: "\(vm.highImpactActions.count)",
                        color: .orange
                    )
                }
            }
            .padding()
            .background(Color.themeDarkGray)
            
            Divider()
                .background(Color.themePurpleDark)
            
            ScrollView {
                VStack(spacing: 24) {
                    FeatureInfoCard(
                        icon: "wrench.and.screwdriver.fill",
                        title: "Remediation Center",
                        whatItDoes: "Turns findings from the other dashboards into concrete fixes - quarantining suspicious files, removing unauthorized launch items, correcting file permissions - with a dry-run preview before anything actually changes.",
                        whyItMatters: "Finding a problem doesn't fix it. This is the difference between a report you read and a system that's actually more secure afterward - and the dry-run default means you see exactly what would happen before committing to it.",
                        checks: ["Suspicious files (quarantined, not deleted, so you can recover them)", "Unauthorized launch agents/daemons", "Incorrect file permissions", "Processes flagged as anomalous elsewhere in the suite"]
                    )
                    .padding(.horizontal)

                    // Warning Banner
                    if !vm.actions.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("⚠️ Remediation Actions")
                                    .font(.headline)
                                    .foregroundColor(.themeText)
                                Text("These actions will modify your system. Review each action carefully before applying.")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Filter buttons
                    if !vm.actions.isEmpty {
                        HStack(spacing: 8) {
                            RemediationFilterButton(
                                label: "All",
                                isSelected: filterImpact == nil,
                                action: { filterImpact = nil }
                            )
                            RemediationFilterButton(
                                label: "Critical",
                                isSelected: filterImpact == "critical",
                                action: { filterImpact = filterImpact == "critical" ? nil : "critical" },
                                color: .red
                            )
                            RemediationFilterButton(
                                label: "High",
                                isSelected: filterImpact == "high",
                                action: { filterImpact = filterImpact == "high" ? nil : "high" },
                                color: .orange
                            )
                            RemediationFilterButton(
                                label: "Low Risk",
                                isSelected: filterImpact == "low",
                                action: { filterImpact = filterImpact == "low" ? nil : "low" },
                                color: .green
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Actions List
                    if vm.loading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading remediation actions...")
                                .font(.subheadline)
                                .foregroundColor(.themeTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else if vm.actions.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text("No remediation actions available")
                                .font(.headline)
                                .foregroundColor(.themeText)
                            if let error = vm.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("All systems appear secure")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Available Actions (\(filteredActions.count))")
                                .font(.headline)
                                .foregroundColor(.themeText)
                            
                            ForEach(filteredActions) { action in
                                RemediationActionCard(action: action, viewModel: vm)
                            }
                        }
                        .padding()
                        .background(Color.themeDarkGray)
                        .cornerRadius(12)
                    }
                    
                    // Results History
                    if !vm.results.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Results")
                                .font(.headline)
                                .foregroundColor(.themeText)
                            
                            ForEach(vm.results.prefix(5)) { result in
                                RemediationResultRow(result: result)
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
            if vm.actions.isEmpty {
                await vm.load()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await vm.load()
                    }
                } label: {
                    Label("Reload Actions", systemImage: "arrow.clockwise")
                }
                .disabled(vm.loading)
            }
        }
        .alert("Confirm Remediation", isPresented: $vm.showConfirmation) {
            Button("Cancel", role: .cancel) {
                vm.selectedAction = nil
            }
            Button("Dry Run") {
                if let action = vm.selectedAction {
                    Task {
                        await vm.apply(action, dryRun: true)
                    }
                }
            }
            Button("Apply Fix", role: .destructive) {
                if let action = vm.selectedAction {
                    Task {
                        await vm.apply(action, dryRun: false)
                    }
                }
            }
        } message: {
            if let action = vm.selectedAction {
                VStack(alignment: .leading, spacing: 8) {
                    Text(action.name)
                        .font(.headline)
                    Text(action.description)
                        .font(.body)
                    Text("Impact: \(action.impact.capitalized)")
                        .font(.caption)
                        .foregroundColor(impactColor(action.impact))
                }
            }
        }
    }
    
    private var filteredActions: [RemediationAction] {
        if let impact = filterImpact {
            return vm.actions.filter { $0.impact.lowercased() == impact.lowercased() || 
                                      (impact == "low" && ($0.riskLevel?.lowercased() == "low" || $0.impact.lowercased() == "low")) }
        }
        return vm.actions
    }
    
    private func impactColor(_ impact: String) -> Color {
        switch impact.lowercased() {
        case "critical": return .red
        case "high": return .orange
        case "medium": return .yellow
        default: return .green
        }
    }
}

struct RemediationActionCard: View {
    let action: RemediationAction
    @ObservedObject var viewModel: RemediationViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.name)
                        .font(.headline)
                        .foregroundColor(.themeText)
                    
                    if let category = action.category {
                        Text(category)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.themePurple.opacity(0.2))
                            .foregroundColor(.themePurple)
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    ImpactBadge(impact: action.impact)
                    if let risk = action.riskLevel {
                        RemediationRiskBadge(risk: risk)
                    }
                }
            }
            
            Text(action.description)
                .font(.subheadline)
                .foregroundColor(.themeTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            
            if !action.fixCommand.isEmpty {
                HStack {
                    Text("Command:")
                        .font(.caption.bold())
                        .foregroundColor(.themeTextSecondary)
                    Text(action.fixCommand)
                        .font(.caption)
                        .foregroundColor(.themeText)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(8)
                .background(Color.themeBlack)
                .cornerRadius(6)
            }
            
            HStack(spacing: 12) {
                Button {
                    viewModel.requestApply(action)
                } label: {
                    Label("Apply Fix", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(viewModel.applying)
                
                Button {
                    Task {
                        await viewModel.apply(action, dryRun: true)
                    }
                } label: {
                    Label("Dry Run", systemImage: "eye.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.applying)
                
                if let time = action.estimatedTime {
                    Text("⏱ \(time)")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color.themeDarkGray.opacity(0.5))
        .cornerRadius(8)
    }
}

struct ImpactBadge: View {
    let impact: String
    
    var body: some View {
        Text(impact.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(impactColor.opacity(0.2))
            .foregroundColor(impactColor)
            .cornerRadius(6)
    }
    
    private var impactColor: Color {
        switch impact.lowercased() {
        case "critical": return .red
        case "high": return .orange
        case "medium": return .yellow
        default: return .green
        }
    }
}

struct RemediationRiskBadge: View {
    let risk: String
    
    var body: some View {
        Text("Risk: \(risk.capitalized)")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(riskColor.opacity(0.2))
            .foregroundColor(riskColor)
            .cornerRadius(4)
    }
    
    private var riskColor: Color {
        switch risk.lowercased() {
        case "high": return .red
        case "medium": return .yellow
        default: return .green
        }
    }
}

struct RemediationResultRow: View {
    let result: RemediationResult
    
    var body: some View {
        HStack {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.success ? .green : .red)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.action.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.themeText)
                Text(result.message)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Text(result.timestamp, style: .relative)
                .font(.caption2)
                .foregroundColor(.themeTextSecondary)
        }
        .padding(.vertical, 8)
    }
}

struct RemediationFilterButton: View {
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

struct RemediationStatBadge: View {
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

