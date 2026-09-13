import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ProcessKillerView: View {
    @State private var runningApps: [RunningApp] = []
    @State private var selectedApps: Set<String> = []
    @State private var searchText: String = ""
    @State private var isLoading = false
    @State private var showForceQuitConfirmation = false
    @State private var showKillAllConfirmation = false
    @State private var appsToKill: [RunningApp] = []
    @State private var killResult: KillResult?
    @State private var refreshTimer: Timer?
    
    // MacGuardian app bundle identifier - must not be killed
    private var macGuardianBundleID: String {
        #if os(macOS)
        return Bundle.main.bundleIdentifier ?? "com.macguardian.suite.ui"
        #else
        return "com.macguardian.suite.ui"
        #endif
    }
    
    // Common problematic apps that users want to kill
    private let commonApps = ["Cursor", "Firefox", "Slack", "Discord", "Chrome", "Safari", "Code", "Xcode"]
    
    var filteredApps: [RunningApp] {
        let apps = runningApps.sorted { app1, app2 in
            // Sort common apps first, then alphabetically
            let app1IsCommon = commonApps.contains(app1.name)
            let app2IsCommon = commonApps.contains(app2.name)
            
            if app1IsCommon && !app2IsCommon {
                return true
            } else if !app1IsCommon && app2IsCommon {
                return false
            }
            
            return app1.name < app2.name
        }
        
        if searchText.isEmpty {
            return apps
        }
        
        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Process Killer")
                        .font(.title.bold())
                        .foregroundColor(.themeText)
                    Text("Safely close applications that won't quit")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                
                Button {
                    refreshApps(showLoading: true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.themePurple)
                .disabled(isLoading)
            }
            .padding()
            .background(Color.themeDarkGray)
            
            Divider()
                .background(Color.themePurpleDark)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.themeTextSecondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding()
            .background(Color.themeBlack)
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Quick kill buttons for common apps
            if !searchText.isEmpty || runningApps.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(commonApps.filter { name in
                            runningApps.contains { $0.name == name }
                        }, id: \.self) { appName in
                            QuickKillButton(appName: appName) {
                                if let app = runningApps.first(where: { $0.name == appName }) {
                                    killApp(app, force: false)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
            }
            
            // App list
            if isLoading {
                ProgressView("Loading applications...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else if filteredApps.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "app.badge")
                        .font(.system(size: 60))
                        .foregroundColor(.themeTextSecondary)
                    Text(searchText.isEmpty ? "No running applications" : "No apps found")
                        .font(.headline)
                        .foregroundColor(.themeText)
                    Text(searchText.isEmpty ? "All applications are closed" : "Try a different search term")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredApps) { app in
                            AppRow(
                                app: app,
                                isSelected: selectedApps.contains(app.id),
                                onToggle: {
                                    if selectedApps.contains(app.id) {
                                        selectedApps.remove(app.id)
                                    } else {
                                        selectedApps.insert(app.id)
                                    }
                                },
                                onKill: {
                                    killApp(app, force: false)
                                },
                                onForceQuit: {
                                    killApp(app, force: true)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            
            Divider()
                .background(Color.themePurpleDark)
            
            // Action buttons
            HStack(spacing: 12) {
                if !selectedApps.isEmpty {
                    Button {
                        let apps = runningApps.filter { selectedApps.contains($0.id) }
                        killMultipleApps(apps, force: false)
                    } label: {
                        Label("Kill Selected (\(selectedApps.count))", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    
                    Button {
                        let apps = runningApps.filter { selectedApps.contains($0.id) }
                        appsToKill = apps
                        showForceQuitConfirmation = true
                    } label: {
                        Label("Force Quit Selected", systemImage: "exclamationmark.triangle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                
                Spacer()
                
                // Kill All button (excludes MacGuardian app)
                Button {
                    showKillAllConfirmation = true
                } label: {
                    Label("Kill All Processes", systemImage: "exclamationmark.octagon.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(runningApps.isEmpty)
                
                Button("Select All") {
                    selectedApps = Set(filteredApps.map { $0.id })
                }
                .buttonStyle(.bordered)
                .disabled(filteredApps.isEmpty)
                
                Button("Deselect All") {
                    selectedApps.removeAll()
                }
                .buttonStyle(.bordered)
                .disabled(selectedApps.isEmpty)
            }
            .padding()
            .background(Color.themeDarkGray)
        }
        .background(Color.themeBlack)
        .onAppear {
            refreshApps(showLoading: true) // Show loading on initial load
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .alert("Force Quit Confirmation", isPresented: $showForceQuitConfirmation) {
            Button("Cancel", role: .cancel) {
                appsToKill = []
            }
            Button("Force Quit", role: .destructive) {
                killMultipleApps(appsToKill, force: true)
                appsToKill = []
            }
        } message: {
            Text("Are you sure you want to force quit \(appsToKill.count) application(s)? This will immediately terminate them without saving:\n\n\(appsToKill.map { $0.name }.joined(separator: ", "))")
        }
        .alert("Kill All Processes", isPresented: $showKillAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Kill All", role: .destructive) {
                killAllProcesses()
            }
        } message: {
            let killableApps = runningApps.filter { $0.bundleIdentifier != macGuardianBundleID }
            Text("⚠️ WARNING: This will kill ALL running applications (\(killableApps.count) apps) except MacGuardian Suite.\n\nThis action cannot be undone. Make sure you have saved your work in all other applications.\n\nMacGuardian Suite will be protected and will not be terminated.")
        }
        .alert("Kill Result", isPresented: .constant(killResult != nil), presenting: killResult) { result in
            Button("OK") {
                killResult = nil
                refreshApps(showLoading: false)
            }
        } message: { result in
            Text(result.message)
        }
    }
    
    private func refreshApps(showLoading: Bool = false) {
        if showLoading {
            isLoading = true
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = getRunningApplications()
            DispatchQueue.main.async {
                runningApps = apps
                isLoading = false
                // Remove selected apps that are no longer running
                selectedApps = selectedApps.filter { id in
                    apps.contains { $0.id == id }
                }
            }
        }
    }
    
    private func startAutoRefresh() {
        stopAutoRefresh() // always invalidate any prior timer first - a bare reassignment here would leak it
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            refreshApps(showLoading: false) // Don't show loading indicator during auto-refresh
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func killApp(_ app: RunningApp, force: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let success = killProcess(app: app, force: force)
            DispatchQueue.main.async {
                if success {
                    killResult = KillResult(
                        success: true,
                        message: "Successfully \(force ? "force quit" : "closed") \(app.name)"
                    )
                    selectedApps.remove(app.id)
                } else {
                    killResult = KillResult(
                        success: false,
                        message: "Failed to \(force ? "force quit" : "close") \(app.name). It may require administrator privileges."
                    )
                }
            }
        }
    }
    
    private func killMultipleApps(_ apps: [RunningApp], force: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            var failedApps: [String] = []
            
            for app in apps {
                if killProcess(app: app, force: force) {
                    successCount += 1
                } else {
                    failedApps.append(app.name)
                }
            }
            
            DispatchQueue.main.async {
                let message: String
                if failedApps.isEmpty {
                    message = "Successfully \(force ? "force quit" : "closed") \(successCount) application(s)."
                } else {
                    message = "\(successCount) application(s) \(force ? "force quit" : "closed"). Failed: \(failedApps.joined(separator: ", "))"
                }
                
                killResult = KillResult(
                    success: failedApps.isEmpty,
                    message: message
                )
                
                // Remove killed apps from selection
                for app in apps {
                    selectedApps.remove(app.id)
                }
            }
        }
    }
    
    private func killAllProcesses() {
        // Filter out MacGuardian app - it must survive!
        let appsToKill = runningApps.filter { app in
            app.bundleIdentifier != macGuardianBundleID
        }
        
        guard !appsToKill.isEmpty else {
            killResult = KillResult(
                success: true,
                message: "No applications to kill (MacGuardian Suite is protected)."
            )
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            var failedApps: [String] = []
            
            for app in appsToKill {
                // Double-check: never kill MacGuardian
                if app.bundleIdentifier == macGuardianBundleID {
                    continue
                }
                
                // Force kill all processes
                if killProcess(app: app, force: true) {
                    successCount += 1
                } else {
                    failedApps.append(app.name)
                }
            }
            
            DispatchQueue.main.async {
                let message: String
                if failedApps.isEmpty {
                    message = "Successfully killed \(successCount) application(s). MacGuardian Suite is still running."
                } else {
                    message = "Killed \(successCount) application(s). Failed: \(failedApps.joined(separator: ", ")). MacGuardian Suite is still running."
                }
                
                killResult = KillResult(
                    success: failedApps.isEmpty,
                    message: message
                )
                
                // Clear selection
                selectedApps.removeAll()
                
                // Refresh app list
                refreshApps(showLoading: false)
            }
        }
    }
}

struct RunningApp: Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let pid: Int32
    let icon: NSImage?
    
    init(from app: NSRunningApplication) {
        self.id = app.bundleIdentifier ?? "\(app.processIdentifier)"
        self.name = app.localizedName ?? "Unknown"
        self.bundleIdentifier = app.bundleIdentifier ?? "unknown"
        self.pid = app.processIdentifier
        self.icon = app.icon
    }
}

struct KillResult: Identifiable {
    let id = UUID()
    let success: Bool
    let message: String
}

struct QuickKillButton: View {
    let appName: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                Text(appName)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.8))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct AppRow: View {
    let app: RunningApp
    let isSelected: Bool
    let onToggle: () -> Void
    let onKill: () -> Void
    let onForceQuit: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button {
                onToggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .themePurple : .themeTextSecondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            
            // App icon
            #if os(macOS)
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app")
                    .foregroundColor(.themeTextSecondary)
                    .frame(width: 32, height: 32)
            }
            #else
            Image(systemName: "app")
                .foregroundColor(.themeTextSecondary)
                .frame(width: 32, height: 32)
            #endif
            
            // App info
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                    .foregroundColor(.themeText)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
                Text("PID: \(app.pid)")
                    .font(.caption2)
                    .foregroundColor(.themeTextSecondary)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 8) {
                Button {
                    onKill()
                } label: {
                    Label("Kill", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                
                Button {
                    onForceQuit()
                } label: {
                    Label("Force", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
        .background(isSelected ? Color.themePurple.opacity(0.2) : Color.themeDarkGray.opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.themePurple : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Process Management Functions

#if os(macOS)
func getRunningApplications() -> [RunningApp] {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications.filter { app in
        // Filter out system processes and background apps
        !app.isHidden && app.activationPolicy == .regular
    }
    
    return runningApps.map { RunningApp(from: $0) }
}

// Get current app's bundle identifier for protection
func getCurrentAppBundleID() -> String? {
    #if os(macOS)
    return Bundle.main.bundleIdentifier
    #else
    return nil
    #endif
}

func killProcess(app: RunningApp, force: Bool) -> Bool {
    guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
        $0.processIdentifier == app.pid
    }) else {
        return false
    }
    
    if force {
        // Force quit - send SIGKILL
        let result = kill(app.pid, SIGKILL)
        return result == 0
    } else {
        // Normal quit - try to terminate gracefully
        runningApp.terminate()
        
        // Give it a moment to terminate gracefully
        var terminated = false
        let semaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Wait up to 2 seconds for graceful termination
            for _ in 0..<20 {
                if runningApp.isTerminated {
                    terminated = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            semaphore.signal()
        }
        
        // Wait for termination check
        _ = semaphore.wait(timeout: .now() + 2.0)
        
        // If still running after 2 seconds, force quit
        if !terminated && !runningApp.isTerminated {
            let result = kill(app.pid, SIGKILL)
            return result == 0
        }
        
        return terminated || runningApp.isTerminated
    }
}
#endif

