import Foundation
#if os(macOS)
import AppKit
#endif

class RemediationScriptService {
    static let shared = RemediationScriptService()

    private init() {}

    /// `repositoryPath` should come from the user's configured
    /// WorkspaceState.repositoryPath, not a hardcoded guess at where the
    /// repo lives.
    func previewActions(repositoryPath: String) async -> [RemediationAction] {
        let scriptDir = "\(repositoryPath)/MacGuardianSuite"
        let scriptPath = "\(scriptDir)/mac_remediation.sh"

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", "cd \(scriptDir.shellQuoted) && ./mac_remediation.sh --preview-json 2>&1"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    var actions: [RemediationAction] = []
                    
                    // Try to parse JSON
                    if let jsonData = output.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let actionsArray = json["actions"] as? [[String: Any]] {
                        actions = self.parseRemediationActions(from: actionsArray)
                    } else {
                        // Fallback: parse text output
                        actions = self.parseActionsFromText(output)
                    }
                    
                    continuation.resume(returning: actions)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    func applyFix(action: RemediationAction, repositoryPath: String, dryRun: Bool = false) async -> (success: Bool, message: String) {
        let scriptDir = "\(repositoryPath)/MacGuardianSuite"
        let scriptPath = "\(scriptDir)/mac_remediation.sh"

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return (false, "Remediation script not found")
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")

                var args = ["--apply"]
                if dryRun {
                    args.append("--dry-run")
                }
                args.append(action.fixCommand)
                let quotedArgs = args.map { $0.shellQuoted }.joined(separator: " ")

                process.arguments = ["-c", "cd \(scriptDir.shellQuoted) && ./mac_remediation.sh \(quotedArgs) 2>&1"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    let success = process.terminationStatus == 0
                    let message = output.isEmpty ? (success ? "Remediation applied successfully" : "Remediation failed") : output
                    
                    continuation.resume(returning: (success, message))
                } catch {
                    continuation.resume(returning: (false, error.localizedDescription))
                }
            }
        }
    }
    
    // MARK: - Parsing Helpers
    
    private func parseRemediationActions(from jsonArray: [[String: Any]]) -> [RemediationAction] {
        var actions: [RemediationAction] = []
        
        for item in jsonArray {
            let name = item["name"] as? String ?? "Unknown Action"
            let impact = item["impact"] as? String ?? "medium"
            let description = item["description"] as? String ?? ""
            let fixCommand = item["fixCommand"] as? String ?? item["command"] as? String ?? ""
            let category = item["category"] as? String
            let requiresConfirmation = item["requiresConfirmation"] as? Bool ?? true
            let estimatedTime = item["estimatedTime"] as? String
            let riskLevel = item["riskLevel"] as? String
            
            actions.append(RemediationAction(
                name: name,
                impact: impact,
                description: description,
                fixCommand: fixCommand,
                category: category,
                requiresConfirmation: requiresConfirmation,
                estimatedTime: estimatedTime,
                riskLevel: riskLevel
            ))
        }
        
        return actions
    }
    
    private func parseActionsFromText(_ text: String) -> [RemediationAction] {
        var actions: [RemediationAction] = []
        let lines = text.components(separatedBy: .newlines)
        
        var currentAction: (name: String, description: String, command: String)? = nil
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.isEmpty { continue }
            
            // Look for action indicators
            if trimmed.contains("Action:") || trimmed.contains("Fix:") || trimmed.hasPrefix("•") {
                if let action = currentAction {
                    actions.append(RemediationAction(
                        name: action.name,
                        impact: "medium",
                        description: action.description,
                        fixCommand: action.command
                    ))
                }
                
                let name = trimmed
                    .replacingOccurrences(of: "Action:", with: "")
                    .replacingOccurrences(of: "Fix:", with: "")
                    .replacingOccurrences(of: "•", with: "")
                    .trimmingCharacters(in: .whitespaces)
                
                currentAction = (name: name, description: "", command: "")
            } else if trimmed.contains("Command:") || trimmed.contains("cmd:") {
                if let action = currentAction {
                    let command = trimmed
                        .replacingOccurrences(of: "Command:", with: "")
                        .replacingOccurrences(of: "cmd:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    currentAction = (name: action.name, description: action.description, command: command)
                }
            } else if var action = currentAction {
                // Append to description
                let desc = action.description.isEmpty ? trimmed : action.description + " " + trimmed
                currentAction = (name: action.name, description: desc, command: action.command)
            }
        }
        
        // Add last action
        if let action = currentAction {
            actions.append(RemediationAction(
                name: action.name,
                impact: "medium",
                description: action.description,
                fixCommand: action.command
            ))
        }
        
        return actions
    }
}

