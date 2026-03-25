import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject var workspace: WorkspaceState
    @State private var categories: [SuiteCategory] = SuiteCategory.defaultCategories()
    @State private var commandRunner = ShellCommandRunner()
    @FocusState private var repositoryPathFieldFocused: Bool
    @State private var showPathPicker = false
    @State private var pathValidationTimer: Timer?

    var body: some View {
        Group {
            if !workspace.hasSeenWelcome {
                WelcomeView()
                    .environmentObject(workspace)
            } else {
                NavigationSplitView(columnVisibility: Binding(
                    get: { workspace.showSidebar ? .automatic : .detailOnly },
                    set: { newValue in
                        workspace.showSidebar = (newValue != .detailOnly)
                    }
                )) {
                    sidebar
                } detail: {
                    mainContentView
                }
                .frame(minWidth: 1100, minHeight: 720)
            }
        }
        .onChange(of: workspace.repositoryPath) { _, _ in
            // Validate path when it changes
            pathValidationTimer?.invalidate()
            pathValidationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                // Path validation happens in the view
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
                
                // Sidebar Toggle Button
                Button {
                    workspace.showSidebar.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: workspace.showSidebar ? "sidebar.left" : "sidebar.squares.left")
                            .font(.system(size: 14))
                        Text(workspace.showSidebar ? "Hide Scripts" : "Show Scripts")
                            .font(.subheadline)
                    }
                    .foregroundColor(.themePurple)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.themePurple.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(workspace.showSidebar ? "Hide script sidebar" : "Show script sidebar")
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
            
            // Tab Navigation - Two Rows for Better Readability
            VStack(spacing: 0) {
                // First Row - Core Modules
                HStack(spacing: 0) {
                    ForEach(AppView.allCases.prefix(8), id: \.self) { view in
                        TabButton(
                            view: view,
                            isSelected: workspace.selectedView == view
                        ) {
                            workspace.selectedView = view
                        }
                    }
                    Spacer()
                }
                
                // Second Row - Security & Monitoring Modules
                HStack(spacing: 0) {
                    ForEach(AppView.allCases.dropFirst(8), id: \.self) { view in
                        TabButton(
                            view: view,
                            isSelected: workspace.selectedView == view
                        ) {
                            workspace.selectedView = view
                        }
                    }
                    Spacer()
                }
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
                        .environmentObject(workspace)
                case .tools:
                    detailView
                case .threatIntelligence:
                    ThreatIntelligenceView()
                case .blueTeam:
                    BlueTeamDashboardView()
                case .securityAudit:
                    SecurityAuditView()
                case .remediation:
                    RemediationCenterView()
                case .omegaGuardian:
                    OmegaGuardianView()
                case .realTimeMonitor:
                    RealTimeDashboardView()
                case .security:
                    SecurityDashboardView()
                        .environmentObject(workspace)
                case .reports:
                    ReportsView()
                        .environmentObject(workspace)
                case .history:
                    ExecutionHistoryView()
                        .environmentObject(workspace)
                case .settings:
                    SettingsView()
                        .environmentObject(workspace)
                case .sshSecurity:
                    SSHSecurityView()
                case .userAccountSecurity:
                    UserAccountSecurityView()
                case .privacyHeatmap:
                    PrivacyHeatmapView()
                case .networkGraph:
                    NetworkGraphView()
                case .incidentTimeline:
                    IncidentTimelineView()
                }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.themeBlack)
        .sheet(isPresented: $workspace.showProcessKiller) {
            ProcessKillerView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .sheet(isPresented: $workspace.showCacheCleaner) {
            CacheCleanerView()
                .frame(minWidth: 900, minHeight: 700)
                .environmentObject(workspace)
        }
        .sheet(isPresented: $workspace.showCursorCacheCleaner) {
            CursorCacheCleanerView()
                .frame(minWidth: 900, minHeight: 700)
                .environmentObject(workspace)
        }
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
                    
                    // Show badge for Omega Guardian if there are unacknowledged incidents
                    if view == .omegaGuardian && incidentStore.unacknowledgedCount > 0 {
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
                .frame(minWidth: 100)
                .background(
                    isSelected ? Color.themePurple.opacity(0.2) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var sidebar: some View {
        List(selection: $workspace.selectedTool) {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    // Logo and Title
                    HStack(spacing: 12) {
                        LogoView(size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MacGuardian")
                                .font(.headline.bold())
                                .foregroundColor(.themePurple)
                            Text("Watchdog")
                                .font(.caption)
                                .foregroundColor(.themeTextSecondary)
                        }
                    }
                    .padding(.bottom, 8)
                    
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill")
                            .foregroundColor(.themePurple)
                            .font(.title3)
                    TextField("Repository Path", text: $workspace.repositoryPath)
                        .textFieldStyle(.roundedBorder)
                        .focused($repositoryPathFieldFocused)
                        Button {
                            showPathPicker = true
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.bordered)
                        .tint(.themePurple)
                        .help("Browse for MacGuardian project folder")
                    }
                    
                    // Path validation feedback
                    let validation = workspace.validateRepositoryPath()
                    if !validation.isValid {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(validation.message)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Ready to use")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    // Safe Mode Toggle
                    HStack(spacing: 8) {
                        Image(systemName: workspace.safeMode ? "shield.checkered" : "shield.slash")
                            .foregroundColor(workspace.safeMode ? .green : .orange)
                        Toggle("Safe Mode", isOn: $workspace.safeMode)
                            .toggleStyle(.switch)
                            .help(workspace.safeMode ? "Safe Mode: Requires confirmation for caution and destructive operations" : "Safe Mode OFF: Only destructive operations require confirmation")
                    }
                    .padding(.vertical, 4)
                }
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Text("Repository")
                    Spacer()
                    Button {
                        workspace.hasSeenWelcome = false
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Show welcome screen")
                }
            }

            ForEach(categories) { category in
                Section {
                    ForEach(category.tools) { tool in
                        HStack(spacing: 8) {
                        Label(tool.name, systemImage: icon(for: tool))
                            Spacer()
                            if tool.executionMode == .terminalRecommended || tool.executionMode == .terminal {
                                Image(systemName: tool.executionMode.icon)
                                    .foregroundColor(.themePurple)
                                    .font(.caption2)
                                    .help(tool.executionMode.description)
                            }
                            if tool.safetyLevel != .safe {
                                Image(systemName: tool.safetyLevel.icon)
                                    .foregroundColor(tool.safetyLevel == .destructive ? .red : .orange)
                                    .font(.caption2)
                                    .help(tool.safetyLevel.description)
                            }
                            if !tool.relativePath.isEmpty && !workspace.checkScriptExists(for: tool) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                    .help("Script not found at expected path")
                            }
                        }
                        .contentShape(Rectangle())
                        .tag(tool)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name)
                            .font(.headline)
                        Text(category.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        .background(Color.themeBlack)
        .scrollContentBackground(.hidden)
        .fileImporter(
            isPresented: $showPathPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                workspace.repositoryPath = url.path
            }
        }
        .navigationTitle("MacGuardian Suite")
        .onChange(of: workspace.selectedTool) { _, newValue in
            guard let tool = newValue else { return }
            if !categories.contains(where: { $0.tools.contains(tool) }) {
                workspace.selectedTool = categories.first?.tools.first
            }
        }
        .onAppear {
            if workspace.selectedTool == nil {
                workspace.selectedTool = categories.first?.tools.first
            }
        }
    }

    private var detailView: some View {
        ZStack {
        Group {
            if let tool = workspace.selectedTool {
                ToolDetailView(tool: tool) { selectedTool in
                        print("🔵 Run button clicked for: \(selectedTool.name)")
                        print("🔵 Repository path: \(workspace.repositoryPath)")
                        print("🔵 Script path: \(workspace.resolve(path: selectedTool.relativePath))")
                        
                        // Clear previous execution
                        workspace.execution = nil
                        
                        // Create and start new execution
                    let execution = commandRunner.run(tool: selectedTool, workspace: workspace)
                    workspace.execution = execution
                        
                        print("🔵 Execution created: \(execution.id)")
                        print("🔵 Execution state: \(String(describing: execution.state))")
                }
                .environmentObject(workspace)
            } else {
                ContentUnavailableView("Select a module", systemImage: "square.grid.2x2", description: Text("Choose a module from the sidebar to view details and run it."))
            }
        }
        .padding()
            .background(Color.themeBlack)
            
            // Safety confirmation dialog overlay
            if workspace.showSafetyConfirmation, let tool = workspace.selectedTool {
                ZStack {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                        .onTapGesture {
                            workspace.showSafetyConfirmation = false
                            workspace.pendingExecution = nil
                        }
                    
                    SafetyConfirmationView(workspace: workspace, tool: tool)
                }
            }
        }
    }

    private func icon(for tool: SuiteTool) -> String {
        switch tool.kind {
        case .shell:
            return "terminal"
        case .python:
            return "chevron.left.forwardslash.chevron.right"
        }
    }

    private func openPathPicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Select your MacGuardian project folder"
        if panel.runModal() == .OK {
            workspace.repositoryPath = panel.url?.path ?? workspace.repositoryPath
        }
        #endif
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(WorkspaceState(defaultPath: "/Users/example/Desktop/MacGuardianProject"))
    }
}
