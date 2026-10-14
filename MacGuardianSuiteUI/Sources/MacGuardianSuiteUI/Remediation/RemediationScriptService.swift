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
                process.arguments = ["-c", "cd \(scriptDir.shellQuoted) && ./mac_remediation.sh --preview-all 2>&1"]
                
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

                // Each action is one fix category; --only runs exactly that
                // category, and --execute -y applies it (the app already asked
                // for confirmation). Without --execute it stays a dry run.
                guard let category = action.category, Self.categories.contains(category) else {
                    continuation.resume(returning: (false, "Unknown remediation action"))
                    return
                }
                var args = ["--only", category]
                if !dryRun {
                    args = ["--execute", "-y"] + args
                }
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
                    
                    // Only report success when the script says it actually ran
                    // in execution mode, never for a preview.
                    let ran = dryRun ? output.contains("Remediation Preview Complete")
                                     : output.contains("Remediation Complete") && !output.contains("DRY-RUN MODE")
                    let success = process.terminationStatus == 0 && ran
                    let message = output.isEmpty ? (success ? "Remediation applied" : "Remediation failed") : output
                    
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
    
    static let categories: Set<String> = ["permissions", "disk", "processes", "launch"]

    /// Groups the dry run's "Would ..." lines into one action per fix category.
    private func parseActionsFromText(_ text: String) -> [RemediationAction] {
        var found: [String: [String]] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.replacingOccurrences(of: "ℹ️", with: "").trimmingCharacters(in: .whitespaces)
            let rules: [(prefix: String, category: String)] = [
                ("Would fix:", "permissions"), ("Would clean:", "disk"), ("Would run: brew cleanup", "disk"),
                ("Would kill:", "processes"), ("Would remove:", "launch")
            ]
            for rule in rules where trimmed.hasPrefix(rule.prefix) {
                let detail = trimmed.dropFirst(rule.prefix.hasPrefix("Would run") ? 6 : rule.prefix.count)
                found[rule.category, default: []].append(detail.trimmingCharacters(in: .whitespaces))
            }
        }

        func make(_ category: String, name: String, impact: String, risk: String, intro: String) -> RemediationAction? {
            guard let items = found[category], !items.isEmpty else { return nil }
            let list = items.prefix(8).map { "• \($0)" }.joined(separator: "\n")
            let more = items.count > 8 ? "\n…and \(items.count - 8) more" : ""
            return RemediationAction(
                name: name.replacingOccurrences(of: "{n}", with: "\(items.count)"),
                impact: impact,
                description: intro + "\n" + list + more,
                fixCommand: "mac_remediation.sh --execute --only \(category)",
                category: category,
                requiresConfirmation: true,
                riskLevel: risk
            )
        }

        return [
            make("permissions", name: "Fix {n} file(s) anyone can modify", impact: "medium", risk: "low",
                 intro: "Removes world-write permission from these files in Documents, Desktop and ~/.ssh (original permissions are backed up):"),
            make("disk", name: "Clean old cache files", impact: "low", risk: "low",
                 intro: "Deletes cache files older than 30 days from these locations and runs brew cleanup:"),
            make("processes", name: "Stop {n} suspicious process(es)", impact: "high", risk: "high",
                 intro: "Ends these unsigned processes whose names match known malware patterns. Check each one first:"),
            make("launch", name: "Quarantine {n} suspicious startup item(s)", impact: "high", risk: "medium",
                 intro: "Moves these launch agents to quarantine so they no longer start at login (restorable):")
        ].compactMap { $0 }
    }
}

