import SwiftUI
#if os(macOS)
import AppKit
#endif

struct TerminalCommandView: View {
    let tool: SuiteTool
    @EnvironmentObject var workspace: WorkspaceState
    @State private var showCommand = false
    @State private var copied = false
    @State private var showInstructions = false
    
    var terminalCommand: String {
        let resolvedPath = workspace.resolve(path: tool.relativePath)
        let scriptDir = (resolvedPath as NSString).deletingLastPathComponent
        let scriptName = (resolvedPath as NSString).lastPathComponent
        
        var cmd = "cd \(scriptDir.shellQuoted)"
        if tool.requiresSudo || tool.executionMode == .terminal {
            cmd += " && sudo ./\(scriptName.shellQuoted)"
        } else {
            cmd += " && ./\(scriptName.shellQuoted)"
        }
        
        if !tool.arguments.isEmpty {
            cmd += " \(tool.arguments.joined(separator: " "))"
        }
        
        // Add resume flag if checkpoint exists
        if tool.relativePath.contains("mac_guardian") {
            let checkpointFile = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.macguardian/checkpoints/mac_guardian_checkpoint.txt"
            if FileManager.default.fileExists(atPath: checkpointFile) {
                cmd += " --resume"
            }
        }
        
        return cmd
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main action button - always visible
            Button {
                openTerminal()
            } label: {
                HStack {
                    Image(systemName: "terminal.fill")
                    Text("Open Terminal & Run")
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.themePurple)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .help("Click to open Terminal with the command ready - just press Enter!")
            
            // Simple instructions - always visible
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("📋 What happens:")
                        .font(.subheadline.bold())
                        .foregroundColor(.themeText)
                    Spacer()
                    #if os(macOS)
                    Button {
                        if let url = URL(string: "file://\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/MacGuardianProject/TERMINAL_GUIDE.md") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "questionmark.circle")
                            Text("Help")
                        }
                        .font(.caption)
                        .foregroundColor(.themePurple)
                    }
                    .buttonStyle(.plain)
                    .help("Open Terminal Guide")
                    #endif
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    InstructionStep(number: 1, text: "Click the purple button above")
                    InstructionStep(number: 2, text: "Terminal opens automatically with the command ready")
                    InstructionStep(number: 3, text: "Press Enter (or Return) on your keyboard to run")
                    if tool.requiresSudo || tool.executionMode == .terminal {
                        InstructionStep(number: 4, text: "Type your Mac password when asked (you won't see it as you type - that's normal and safe!)")
                    }
                    InstructionStep(number: tool.requiresSudo || tool.executionMode == .terminal ? 5 : 4, text: "Wait for it to finish - you'll see progress in Terminal")
                }
                .padding(.leading, 8)
            }
            .padding()
            .background(Color.themeDarkGray.opacity(0.5))
            .cornerRadius(8)
            
            // Expandable command view
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showCommand.toggle()
                } label: {
                    HStack {
                        Image(systemName: "info.circle")
                        Text(showCommand ? "Hide Command Details" : "Show Command Details")
                        Spacer()
                        Image(systemName: showCommand ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
                }
                .buttonStyle(.plain)
                
                if showCommand {
                    VStack(alignment: .leading, spacing: 12) {
                        // Command display
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("The command that will run:")
                                    .font(.caption.bold())
                                    .foregroundColor(.themeText)
                                Spacer()
                                Button {
                                    #if os(macOS)
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(terminalCommand, forType: .string)
                                    #endif
                                    copied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        copied = false
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                        Text(copied ? "Copied!" : "Copy")
                                    }
                                    .font(.caption)
                                    .foregroundColor(copied ? .green : .themePurple)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Text(terminalCommand)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.themeText)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.themeBlack)
                                .cornerRadius(6)
                                .textSelection(.enabled)
                            
                            Text("💡 Don't worry about understanding this - just click the button above and Terminal will run it for you!")
                                .font(.caption2)
                                .foregroundColor(.themeTextSecondary)
                                .italic()
                        }
                        
                        if tool.executionMode == .terminalRecommended {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("💡 Why use Terminal?")
                                    .font(.caption.bold())
                                    .foregroundColor(.themeText)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    BenefitRow(icon: "lock.shield.fill", text: "Full security access (can enter password)")
                                    BenefitRow(icon: "eye.fill", text: "See all output and errors")
                                    BenefitRow(icon: "checkmark.seal.fill", text: "Complete functionality")
                                }
                            }
                            .padding()
                            .background(Color.themeDarkGray.opacity(0.5))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color.themeDarkGray.opacity(0.3))
                    .cornerRadius(8)
                }
            }
        }
        .padding(.top, 8)
    }
    
    private func openTerminal() {
        #if os(macOS)
        let escapedCommand = terminalCommand.appleScriptQuoted

        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("Error opening Terminal: \(error)")
                // Fallback: copy to clipboard and show alert
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(terminalCommand, forType: .string)
                
                // Show alert with instructions
                let alert = NSAlert()
                alert.messageText = "Terminal Command Copied"
                alert.informativeText = "The command has been copied to your clipboard.\n\n1. Open Terminal (Command+Space, type 'Terminal')\n2. Paste the command (Command+V)\n3. Press Enter"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
        #endif
    }
}

struct TerminalInstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption.bold())
                .foregroundColor(.themePurple)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(.themeTextSecondary)
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(.themePurple)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .foregroundColor(.themeTextSecondary)
        }
    }
}

