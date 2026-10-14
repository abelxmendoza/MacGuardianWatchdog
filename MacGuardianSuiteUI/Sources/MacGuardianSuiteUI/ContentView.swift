import SwiftUI

struct ContentView: View {
    @EnvironmentObject var workspace: WorkspaceState

    var body: some View {
        Group {
            if !workspace.hasSeenWelcome {
                WelcomeView()
                    .environmentObject(workspace)
            } else {
                mainContentView
                    .frame(minWidth: 1000, minHeight: 720)
            }
        }
    }

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Main Header with Logo
            HStack(spacing: 16) {
                LogoView(size: 48)
                    .shadow(color: .themePurple.opacity(0.3), radius: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MacGuardian")
                        .font(.title.bold())
                        .foregroundColor(.themePurple)
                    Text("Watchdog Security Suite")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }

                Spacer()

                Button {
                    workspace.hasSeenWelcome = false
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.themePurple)
                }
                .buttonStyle(.plain)
                .help("Show welcome screen")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.themeDarkGray, Color.themeBlack],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Rectangle()
                    .frame(height: 2)
                    .foregroundColor(Color.themePurpleDark),
                alignment: .bottom
            )

            // Tab Navigation
            HStack(spacing: 0) {
                ForEach(AppView.allCases, id: \.self) { view in
                    TabButton(
                        view: view,
                        isSelected: workspace.selectedView == view
                    ) {
                        workspace.selectedView = view
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.themeDarkGray)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.themePurpleDark),
                alignment: .bottom
            )

            // Content View
            Group {
                switch workspace.selectedView {
                case .dashboard:
                    DashboardView()
                case .audit:
                    SectionedTab(selection: $workspace.auditSection) { section in
                        switch section {
                        case .posture: SecurityAuditView()
                        case .integrity:
                            ScriptRunnerView(
                                icon: "doc.badge.gearshape.fill",
                                title: "File Integrity",
                                subtitle: "Compare important files against a known-good baseline",
                                whatItDoes: "Checksums the folders you care about and compares them with the baseline taken on the first run, and checks whether the decoy credentials file was opened. The first run only creates the baseline.",
                                whyItMatters: "Tampering often shows up first as a file that changed when nothing should have touched it - a modified login item, a swapped binary, a new file in a quiet folder.",
                                checks: ["Monitored folders vs. the saved baseline", "Decoy (honeypot) credentials file", "Recent system log changes"],
                                scriptPath: "MacGuardianSuite/mac_watchdog.sh",
                                runLabel: "Check Files"
                            )
                        case .selfCheck:
                            ScriptRunnerView(
                                icon: "checkmark.seal.fill",
                                title: "Self-Check",
                                subtitle: "Is MacGuardian itself still trustworthy?",
                                whatItDoes: "Checks MacGuardian's own scripts against the fingerprints recorded when you installed it, makes sure no other user can modify them, verifies the installed app's code signature, and confirms its background jobs run the right, up-to-date scripts.",
                                whyItMatters: "A security tool that has been quietly modified - to hide findings or run something extra with your permissions - is worse than none. This is how MacGuardian proves it is still the copy you installed.",
                                checks: ["Script fingerprints vs. install-time baseline", "File ownership and permissions", "App code signature", "Background jobs and the copy they run", "Data folder privacy"],
                                scriptPath: "MacGuardianSuite/self_check.sh",
                                runLabel: "Run Self-Check"
                            )
                        case .ssh: SSHSecurityView()
                        case .users: UserAccountSecurityView()
                        case .privacy: PrivacyHeatmapView()
                        }
                    }
                case .threats:
                    BlueTeamDashboardView()
                case .incidents:
                    SectionedTab(selection: $workspace.incidentsSection) { section in
                        switch section {
                        case .incidents: OmegaGuardianView()
                        case .timeline: IncidentTimelineView()
                        }
                    }
                case .fix:
                    SectionedTab(selection: $workspace.fixSection) { section in
                        switch section {
                        case .remediation: RemediationCenterView()
                        case .panicKill: PanicKillerView()
                        }
                    }
                case .processes:
                    ProcessKillerView()
                case .cleaner:
                    SectionedTab(selection: $workspace.cleanerSection) { section in
                        switch section {
                        case .caches: CacheCleanerView()
                        case .cursor: CursorCacheCleanerView()
                        case .appIcons: FixAppIconsView()
                        }
                    }
                case .reports:
                    ReportsView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.themeBlack)
    }

    private struct TabButton: View {
        let view: AppView
        let isSelected: Bool
        let action: () -> Void
        @StateObject private var incidentStore = IncidentStore.shared

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: view.icon)
                        .font(.system(size: 13))
                        .frame(width: 16)
                    Text(view.rawValue)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    // Show badge for Incidents if there are unacknowledged incidents
                    if view == .incidents && incidentStore.unacknowledgedCount > 0 {
                        Text("\(incidentStore.unacknowledgedCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
                .foregroundColor(isSelected ? .themePurple : .themeTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    isSelected ? Color.themePurple.opacity(0.2) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

/// A tab that holds several related screens behind a segmented picker.
private struct SectionedTab<Item: TabSection, Content: View>: View {
    @Binding var selection: Item
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                ForEach(Item.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 680)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.themeBlack)

            content(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(WorkspaceState(defaultPath: "/Users/example/Desktop/MacGuardianProject"))
    }
}
