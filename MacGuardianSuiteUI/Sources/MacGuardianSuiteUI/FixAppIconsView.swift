import SwiftUI
#if os(macOS)
import AppKit
#endif

struct FixAppIconsView: View {
    @EnvironmentObject var workspace: WorkspaceState
    @State private var clearUserCache = true
    @State private var clearSystemCache = false
    @State private var restartDock = true
    @State private var fixMacGuardianIcon = true
    @State private var isLoading = false
    @State private var showConfirmation = false
    @State private var fixResult: FixResult?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "paintbrush.fill")
                    .font(.title)
                    .foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fix App Icons")
                        .font(.title.bold())
                        .foregroundColor(.themeText)
                    Text("Clear macOS icon cache and fix app icons")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.themeDarkGray)
            
            Divider()
                .background(Color.themePurpleDark)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Info card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("What This Does")
                                    .font(.headline)
                                    .foregroundColor(.themeText)
                                Text("Clears macOS icon cache so app icons refresh correctly. Use this if icons aren't displaying properly in Finder or Dock.")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Options
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Options")
                            .font(.headline)
                            .foregroundColor(.themeText)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            CleanOptionToggle(
                                title: "Clear User Icon Cache",
                                description: "Clear your user icon cache (~/Library/Caches/com.apple.iconservices)",
                                icon: "person.fill",
                                isOn: $clearUserCache
                            )
                            
                            CleanOptionToggle(
                                title: "Clear System Icon Cache",
                                description: "Clear system-wide icon cache (requires password)",
                                icon: "lock.fill",
                                isOn: $clearSystemCache
                            )
                            
                            CleanOptionToggle(
                                title: "Restart Dock",
                                description: "Restart Dock to refresh icons immediately",
                                icon: "dock.rectangle",
                                isOn: $restartDock
                            )
                            
                            CleanOptionToggle(
                                title: "Fix MacGuardian Suite Icon",
                                description: "Specifically fix the MacGuardian Suite app icon",
                                icon: "app.badge",
                                isOn: $fixMacGuardianIcon
                            )
                        }
                    }
                    .padding()
                    .background(Color.themeDarkGray.opacity(0.3))
                    .cornerRadius(12)
                    
                    // Warning
                    if clearSystemCache {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("⚠️ Requires Password")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.orange)
                                Text("Clearing system cache requires administrator password. You'll be prompted when you click 'Fix Icons'.")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            
            Divider()
                .background(Color.themePurpleDark)
            
            // Action buttons
            HStack(spacing: 12) {
                Button {
                    performFix()
                } label: {
                    Label("Fix Icons", systemImage: "paintbrush.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isLoading || (!clearUserCache && !clearSystemCache && !fixMacGuardianIcon))
            }
            .padding()
            .background(Color.themeDarkGray)
        }
        .background(Color.themeBlack)
        .alert("Fix Icons Result", isPresented: .constant(fixResult != nil), presenting: fixResult) { result in
            Button("OK") {
                fixResult = nil
            }
        } message: { result in
            Text(result.message)
        }
    }
    
    private func performFix() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
                .appendingPathComponent("MacGuardianProject")
                .appendingPathComponent("MacGuardianSuite")
                .appendingPathComponent("fix_app_icons.sh")
                .path
            
            guard FileManager.default.fileExists(atPath: scriptPath) else {
                DispatchQueue.main.async {
                    isLoading = false
                    fixResult = FixResult(
                        success: false,
                        message: "Fix app icons script not found at: \(scriptPath)"
                    )
                }
                return
            }
            
            // Build command arguments
            var args: [String] = []
            if !clearUserCache {
                args.append("--no-user-cache")
            }
            if clearSystemCache {
                args.append("--system-cache")
            }
            if !restartDock {
                args.append("--no-dock-restart")
            }
            
            // Fix MacGuardian icon if requested
            var appPathToFix: String? = nil
            if fixMacGuardianIcon {
                let appPath = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                    .appendingPathComponent("MacGuardianProject")
                    .appendingPathComponent("MacGuardianSuiteUI")
                    .appendingPathComponent(".build")
                    .appendingPathComponent("MacGuardian Suite.app")
                    .path
                
                if FileManager.default.fileExists(atPath: appPath) {
                    appPathToFix = appPath
                    
                    // Also run set_app_icon.sh for more comprehensive icon setting
                    let setIconScriptPath = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Desktop")
                        .appendingPathComponent("MacGuardianProject")
                        .appendingPathComponent("MacGuardianSuiteUI")
                        .appendingPathComponent("set_app_icon.sh")
                        .path
                    
                    if FileManager.default.fileExists(atPath: setIconScriptPath) {
                        let setIconResult = runSetAppIconScript(scriptPath: setIconScriptPath)
                        if !setIconResult.success {
                            // Log but don't fail - fix_app_icons.sh will still run
                            print("Warning: set_app_icon.sh failed: \(setIconResult.message)")
                        }
                    }
                }
            }
            
            let result = runFixAppIconsScript(args: args, appPath: appPathToFix)
            
            DispatchQueue.main.async {
                isLoading = false
                if result.success {
                    fixResult = FixResult(
                        success: true,
                        message: "✅ Icon cache cleared successfully!\n\n\(result.message)\n\nIcons should refresh automatically. If not, restart your Mac."
                    )
                } else {
                    fixResult = FixResult(
                        success: false,
                        message: "⚠️ \(result.message)"
                    )
                }
            }
        }
    }
}

struct FixResult: Identifiable {
    let id = UUID()
    let success: Bool
    let message: String
}

#if os(macOS)
func runFixAppIconsScript(args: [String], appPath: String?) -> (success: Bool, message: String) {
    let scriptPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop")
        .appendingPathComponent("MacGuardianProject")
        .appendingPathComponent("MacGuardianSuite")
        .appendingPathComponent("fix_app_icons.sh")
        .path
    
    guard FileManager.default.fileExists(atPath: scriptPath) else {
        return (false, "Script not found")
    }
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")

    let scriptDir = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/MacGuardianProject/MacGuardianSuite"
    var command = "cd \(scriptDir.shellQuoted) && bash \(scriptPath.shellQuoted)"

    // Add regular arguments (fixed flags from the UI, but quoted regardless)
    if !args.isEmpty {
        command += " " + args.map { $0.shellQuoted }.joined(separator: " ")
    }

    // Add app path separately with proper quoting
    if let appPath = appPath {
        command += " --app \(appPath.shellQuoted)"
    }
    
    process.arguments = ["-c", command]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    
    do {
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if process.terminationStatus == 0 {
            return (true, output.isEmpty ? "Icon cache cleared" : output)
        } else {
            return (false, "Error: \(output.isEmpty ? "Script failed" : output)")
        }
    } catch {
        return (false, "Failed to run: \(error.localizedDescription)")
    }
}

func runSetAppIconScript(scriptPath: String) -> (success: Bool, message: String) {
    guard FileManager.default.fileExists(atPath: scriptPath) else {
        return (false, "set_app_icon.sh not found")
    }
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    
    let scriptDir = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/MacGuardianProject/MacGuardianSuiteUI"
    let command = "cd \(scriptDir.shellQuoted) && bash \(scriptPath.shellQuoted)"
    process.arguments = ["-c", command]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    
    do {
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if process.terminationStatus == 0 {
            return (true, output.isEmpty ? "Icon set successfully" : output)
        } else {
            return (false, "Error: \(output.isEmpty ? "Script failed" : output)")
        }
    } catch {
        return (false, "Failed to run: \(error.localizedDescription)")
    }
}
#endif

