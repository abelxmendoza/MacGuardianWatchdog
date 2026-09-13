import Foundation
#if os(macOS)
import AppKit

/// Utility to launch Terminal.app with a pre-filled command
class TerminalLauncher {
    static let shared = TerminalLauncher()
    
    private init() {}
    
    /// Opens Terminal.app and executes a command
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - workingDirectory: Optional working directory (defaults to user's home)
    ///   - title: Optional window title
    ///   - copyToClipboard: If true, copies command to clipboard before opening Terminal
    func openTerminal(with command: String, workingDirectory: String? = nil, title: String? = nil, copyToClipboard: Bool = false) {
        let dir = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        // `command` is a pre-built shell snippet (its own args are already
        // quoted by the caller), so it's concatenated as-is; only the
        // directory - which can come from user-editable repositoryPath - is
        // quoted here.
        let fullCommand = "cd \(dir.shellQuoted) && \(command)"

        // Copy command to clipboard if requested (do this FIRST)
        if copyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(fullCommand, forType: .string)
        }

        let windowTitle = title ?? "MacGuardian"
        let script = """
        tell application "Terminal"
            activate
            set newTab to do script "\(fullCommand.appleScriptQuoted)"
            set custom title of newTab to "\(windowTitle.appleScriptQuoted)"
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            
            if let error = error {
                print("Error opening Terminal: \(error)")
                // Fallback: try opening Terminal and showing command
                fallbackOpenTerminal(command: fullCommand, title: windowTitle)
            }
        }
    }
    
    /// Fallback method that opens Terminal and displays command for easy copy/paste
    private func fallbackOpenTerminal(command: String, title: String) {
        let innerShellCommand = "echo '🛡️ MacGuardian Command Ready' && echo '' && echo 'Command (already copied to clipboard):' && echo \(command.shellQuoted) && echo '' && echo 'Press Cmd+V to paste, or type it manually above.' && echo ''"
        let script = """
        tell application "Terminal"
            activate
            do script "\(innerShellCommand.appleScriptQuoted)"
            set custom title of front window to "\(title.appleScriptQuoted)"
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
    
    /// Gets the simple rkhunter command for copying to clipboard
    /// - Parameter updateFirst: Whether to update rkhunter database first
    /// - Returns: The command string ready to paste
    func getRkhunterScanCommandForClipboard(updateFirst: Bool = true) -> String {
        // Find rkhunter path
        let rkhunterPaths = [
            "/usr/local/bin/rkhunter",
            "/opt/homebrew/bin/rkhunter",
            "/usr/bin/rkhunter"
        ]
        
        var rkhunterPath = ""
        for path in rkhunterPaths {
            if FileManager.default.fileExists(atPath: path) {
                rkhunterPath = path
                break
            }
        }
        
        if rkhunterPath.isEmpty {
            // Try to find via which/command
            let whichProcess = Process()
            whichProcess.launchPath = "/usr/bin/which"
            whichProcess.arguments = ["rkhunter"]
            
            let pipe = Pipe()
            whichProcess.standardOutput = pipe
            whichProcess.standardError = pipe
            
            do {
                try whichProcess.run()
                whichProcess.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty {
                    rkhunterPath = output
                }
            } catch {
                // rkhunter not found
            }
        }
        
        if rkhunterPath.isEmpty {
            return "brew install rkhunter"
        }
        
        if updateFirst {
            return "sudo \(rkhunterPath) --update && sudo \(rkhunterPath) --check --sk"
        } else {
            return "sudo \(rkhunterPath) --check --sk"
        }
    }
    
    /// Gets the rkhunter scan command as a string (for display/copying)
    /// - Parameter updateFirst: Whether to update rkhunter database first
    /// - Returns: The command string that will be executed
    func getRkhunterScanCommand(updateFirst: Bool = true) -> String {
        var command = ""
        
        // Check if rkhunter is installed
        let rkhunterPaths = [
            "/usr/local/bin/rkhunter",
            "/opt/homebrew/bin/rkhunter",
            "/usr/bin/rkhunter"
        ]
        
        var rkhunterPath = ""
        for path in rkhunterPaths {
            if FileManager.default.fileExists(atPath: path) {
                rkhunterPath = path
                break
            }
        }
        
        if rkhunterPath.isEmpty {
            // Try to find via which/command
            let whichProcess = Process()
            whichProcess.launchPath = "/usr/bin/which"
            whichProcess.arguments = ["rkhunter"]
            
            let pipe = Pipe()
            whichProcess.standardOutput = pipe
            whichProcess.standardError = pipe
            
            do {
                try whichProcess.run()
                whichProcess.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty {
                    rkhunterPath = output
                }
            } catch {
                print("Could not find rkhunter: \(error)")
            }
        }
        
        if rkhunterPath.isEmpty {
            // rkhunter not found - offer to install
            command = """
            echo "🔍 Rootkit Hunter (rkhunter) not found."
            echo ""
            echo "To install rkhunter, run:"
            echo "  brew install rkhunter"
            echo ""
            echo "After installation, you can run:"
            echo "  sudo rkhunter --update"
            echo "  sudo rkhunter --check --sk"
            echo ""
            read -p "Press Enter to continue..."
            """
        } else {
            if updateFirst {
                command = """
                echo "🛡️ MacGuardian - Rootkit Scan"
                echo "================================"
                echo ""
                echo "📥 Updating rkhunter database..."
                sudo \(rkhunterPath) --update
                echo ""
                echo "🔍 Running rootkit scan..."
                echo "⚠️  This may take a few minutes..."
                echo ""
                sudo \(rkhunterPath) --check --sk
                echo ""
                echo "✅ Scan complete!"
                echo ""
                read -p "Press Enter to close..."
                """
            } else {
                command = """
                echo "🛡️ MacGuardian - Rootkit Scan"
                echo "================================"
                echo ""
                echo "🔍 Running rootkit scan..."
                echo "⚠️  This may take a few minutes..."
                echo ""
                sudo \(rkhunterPath) --check --sk
                echo ""
                echo "✅ Scan complete!"
                echo ""
                read -p "Press Enter to close..."
                """
            }
        }
        
        return command
    }
    
    /// Opens Terminal.app and copies rkhunter scan command to clipboard
    /// - Parameter updateFirst: Whether to update rkhunter database first
    func openRkhunterScan(updateFirst: Bool = true) {
        // Get the simple command for clipboard (without echo statements)
        let clipboardCommand = getRkhunterScanCommandForClipboard(updateFirst: updateFirst)
        
        // Copy command to clipboard FIRST
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(clipboardCommand, forType: .string)
        
        // Open Terminal with clear instructions
        let instructionCommand = """
        clear
        echo "🛡️ MacGuardian - Rootkit Scan"
        echo "================================"
        echo ""
        echo "✅ Command copied to clipboard!"
        echo ""
        echo "📋 To run the scan:"
        echo "   1. Press Cmd+V (or right-click → Paste) to paste"
        echo "   2. Press Enter to execute"
        echo ""
        echo "⚠️  Note: This command requires sudo privileges"
        echo "   You will be prompted for your password"
        echo ""
        echo "────────────────────────────────────────"
        echo ""
        echo "Command (ready to paste):"
        echo "  \(clipboardCommand)"
        echo ""
        echo "────────────────────────────────────────"
        echo ""
        echo "💡 Tip: The command is already in your clipboard!"
        echo "   Just press Cmd+V and Enter to run it."
        echo ""
        """
        
        // Open Terminal and ensure command is copied
        openTerminal(with: instructionCommand, title: "MacGuardian - Rootkit Scan", copyToClipboard: true)
        
        // Ensure clipboard is set (double-check)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteboard.clearContents()
            pasteboard.setString(clipboardCommand, forType: .string)
        }
    }
    
    /// Opens Terminal.app with mac_guardian.sh (which includes rkhunter)
    func openMacGuardianScript() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let scriptPath = "\(homeDir)/Desktop/MacGuardianProject/MacGuardianSuite/mac_guardian.sh"
        
        // Check if script exists
        if FileManager.default.fileExists(atPath: scriptPath) {
            let command = """
            echo "🛡️ MacGuardian Security Suite"
            echo "=============================="
            echo ""
            cd \("\(homeDir)/Desktop/MacGuardianProject".shellQuoted)
            ./MacGuardianSuite/mac_guardian.sh
            echo ""
            read -p "Press Enter to close..."
            """
            
            // Copy command to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(command, forType: .string)
            
            openTerminal(with: command, workingDirectory: "\(homeDir)/Desktop/MacGuardianProject", title: "MacGuardian Suite", copyToClipboard: true)
        } else {
            // Try alternative paths
            let altPaths = [
                "\(homeDir)/MacGuardianProject/MacGuardianSuite/mac_guardian.sh",
                "\(homeDir)/Documents/MacGuardianProject/MacGuardianSuite/mac_guardian.sh"
            ]
            
            var found = false
            for altPath in altPaths {
                if FileManager.default.fileExists(atPath: altPath) {
                    let dir = (altPath as NSString).deletingLastPathComponent
                    let command = """
                    echo "🛡️ MacGuardian Security Suite"
                    echo "=============================="
                    echo ""
                    cd \(dir.shellQuoted)
                    ./mac_guardian.sh
                    echo ""
                    read -p "Press Enter to close..."
                    """
                    openTerminal(with: command, workingDirectory: dir, title: "MacGuardian Suite")
                    found = true
                    break
                }
            }
            
            if !found {
                let command = """
                echo "⚠️  MacGuardian script not found at expected location."
                echo ""
                echo "Please navigate to your MacGuardianProject directory and run:"
                echo "  ./MacGuardianSuite/mac_guardian.sh"
                echo ""
                read -p "Press Enter to close..."
                """
                openTerminal(with: command, title: "MacGuardian Suite")
            }
        }
    }
}
#endif

