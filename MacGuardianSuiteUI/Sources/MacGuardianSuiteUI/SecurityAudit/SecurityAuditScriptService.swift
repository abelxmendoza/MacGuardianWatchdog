import Foundation
#if os(macOS)
import AppKit
#endif

class SecurityAuditScriptService {
    static let shared = SecurityAuditScriptService()

    private init() {}

    /// `repositoryPath` should come from the user's configured
    /// WorkspaceState.repositoryPath, the same way every other tool in the
    /// app locates its scripts - not a hardcoded guess at where the repo lives.
    func runAudit(repositoryPath: String) async -> ([AuditCheck], AuditSummary) {
        let scriptDir = "\(repositoryPath)/MacGuardianSuite"
        let scriptPath = "\(scriptDir)/mac_security_audit.sh"

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return ([], AuditSummary())
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", "cd \(scriptDir.shellQuoted) && ./mac_security_audit.sh --json 2>&1"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    var checks: [AuditCheck] = []
                    var summary = AuditSummary()
                    
                    // Try to parse JSON
                    if let jsonData = output.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        
                        // Parse checks
                        if let checksArray = json["checks"] as? [[String: Any]] {
                            checks = self.parseAuditChecks(from: checksArray)
                        }
                        
                        // Parse summary
                        if let summaryDict = json["summary"] as? [String: Any] {
                            summary = self.parseSummary(from: summaryDict)
                        }
                    } else {
                        // Fallback: parse text output
                        (checks, summary) = self.parseAuditFromText(output)
                    }
                    
                    continuation.resume(returning: (checks, summary))
                } catch {
                    continuation.resume(returning: ([], AuditSummary()))
                }
            }
        }
    }
    
    // MARK: - Parsing Helpers
    
    private func parseAuditChecks(from jsonArray: [[String: Any]]) -> [AuditCheck] {
        var checks: [AuditCheck] = []
        
        for item in jsonArray {
            let name = item["name"] as? String ?? "Unknown Check"
            let status = item["status"] as? String ?? "unknown"
            let description = item["description"] as? String ?? ""
            let category = item["category"] as? String
            let recommendation = item["recommendation"] as? String
            let severity = item["severity"] as? String
            
            checks.append(AuditCheck(
                name: name,
                status: status,
                description: description,
                category: category,
                recommendation: recommendation,
                severity: severity
            ))
        }
        
        return checks
    }
    
    private func parseSummary(from dict: [String: Any]) -> AuditSummary {
        let score = dict["score"] as? Int ?? 0
        let passed = dict["passed"] as? Int ?? 0
        let failed = dict["failed"] as? Int ?? 0
        let warnings = dict["warnings"] as? Int ?? 0
        let total = dict["total"] as? Int ?? (passed + failed + warnings)
        
        return AuditSummary(
            score: score,
            passed: passed,
            failed: failed,
            warnings: warnings,
            total: total
        )
    }
    
    private func parseAuditFromText(_ text: String) -> ([AuditCheck], AuditSummary) {
        var checks: [AuditCheck] = []
        var passed = 0
        var failed = 0
        var warnings = 0
        
        let lines = text.components(separatedBy: .newlines)
        var currentCheck: (name: String, status: String, description: String)? = nil
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.isEmpty { continue }
            
            // Look for check indicators
            if trimmed.contains("✅") || trimmed.contains("PASS") || trimmed.contains("PASSED") {
                if let check = currentCheck {
                    checks.append(AuditCheck(
                        name: check.name,
                        status: "pass",
                        description: check.description
                    ))
                    passed += 1
                    currentCheck = nil
                } else {
                    let name = trimmed.replacingOccurrences(of: "✅", with: "").trimmingCharacters(in: .whitespaces)
                    currentCheck = (name: name, status: "pass", description: "")
                }
            } else if trimmed.contains("❌") || trimmed.contains("FAIL") || trimmed.contains("FAILED") {
                if let check = currentCheck {
                    checks.append(AuditCheck(
                        name: check.name,
                        status: "fail",
                        description: check.description
                    ))
                    failed += 1
                    currentCheck = nil
                } else {
                    let name = trimmed.replacingOccurrences(of: "❌", with: "").trimmingCharacters(in: .whitespaces)
                    currentCheck = (name: name, status: "fail", description: "")
                }
            } else if trimmed.contains("⚠️") || trimmed.contains("WARNING") {
                if let check = currentCheck {
                    checks.append(AuditCheck(
                        name: check.name,
                        status: "warning",
                        description: check.description
                    ))
                    warnings += 1
                    currentCheck = nil
                } else {
                    let name = trimmed.replacingOccurrences(of: "⚠️", with: "").trimmingCharacters(in: .whitespaces)
                    currentCheck = (name: name, status: "warning", description: "")
                }
            } else if let check = currentCheck {
                // Append to description
                currentCheck = (
                    name: check.name,
                    status: check.status,
                    description: check.description.isEmpty ? trimmed : check.description + " " + trimmed
                )
            } else if trimmed.count > 10 && !trimmed.hasPrefix("#") {
                // New check without status indicator
                currentCheck = (name: trimmed, status: "unknown", description: "")
            }
        }
        
        // Add any remaining check
        if let check = currentCheck {
            checks.append(AuditCheck(
                name: check.name,
                status: check.status,
                description: check.description
            ))
            if check.status == "pass" { passed += 1 }
            else if check.status == "fail" { failed += 1 }
            else if check.status == "warning" { warnings += 1 }
        }
        
        let total = checks.count
        let score = total > 0 ? Int((Double(passed) / Double(total)) * 100) : 0
        
        let summary = AuditSummary(
            score: score,
            passed: passed,
            failed: failed,
            warnings: warnings,
            total: total
        )
        
        return (checks, summary)
    }
}

