import Foundation
#if os(macOS)
import AppKit
#endif

class BlueTeamScriptService {
    static let shared = BlueTeamScriptService()

    private init() {}

    /// `repositoryPath` should come from the user's configured
    /// WorkspaceState.repositoryPath, not a hardcoded guess at where the
    /// repo lives.
    func runCollector(repositoryPath: String) async -> [ThreatEvent] {
        let scriptDir = "\(repositoryPath)/MacGuardianSuite"
        let scriptPath = "\(scriptDir)/mac_blueteam.sh"

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", "cd \(scriptDir.shellQuoted) && ./mac_blueteam.sh --json 2>&1"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    // Parse JSON output
                    var events: [ThreatEvent] = []
                    if let jsonData = output.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let eventsArray = json["events"] as? [[String: Any]] {
                        events = self.parseThreatEvents(from: eventsArray)
                    } else {
                        // Fallback: parse text output for threats
                        events = self.parseThreatEventsFromText(output)
                    }
                    
                    continuation.resume(returning: events)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    func getSystemStats(repositoryPath: String) async -> SystemStats {
        let scriptDir = "\(repositoryPath)/MacGuardianSuite"
        let scriptPath = "\(scriptDir)/performance_monitor.sh"

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return SystemStats()
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", "cd \(scriptDir.shellQuoted) && ./performance_monitor.sh --json 2>&1"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    var stats = SystemStats()
                    if let jsonData = output.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        stats.cpu = json["cpu"] as? Double ?? 0
                        stats.memory = json["memory"] as? Double ?? 0
                        stats.disk = json["disk"] as? Double ?? 0
                        stats.networkOut = json["networkOut"] as? Double ?? 0
                        stats.networkIn = json["networkIn"] as? Double ?? 0
                        stats.processCount = json["processCount"] as? Int
                        stats.connectionCount = json["connectionCount"] as? Int
                    } else {
                        // Fallback: parse basic stats from text
                        stats = self.parseStatsFromText(output)
                    }
                    
                    continuation.resume(returning: stats)
                } catch {
                    continuation.resume(returning: SystemStats())
                }
            }
        }
    }
    
    // MARK: - Parsing Helpers
    
    private func parseThreatEvents(from jsonArray: [[String: Any]]) -> [ThreatEvent] {
        var events: [ThreatEvent] = []
        
        for item in jsonArray {
            let timestamp = (item["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            let source = item["source"] as? String ?? "unknown"
            let severity = item["severity"] as? String ?? "medium"
            let description = item["description"] as? String ?? ""
            let category = item["category"] as? String
            let details = item["details"] as? [String: String]
            
            events.append(ThreatEvent(
                timestamp: timestamp,
                source: source,
                severity: severity,
                description: description,
                category: category,
                details: details
            ))
        }
        
        return events
    }
    
    private func parseThreatEventsFromText(_ text: String) -> [ThreatEvent] {
        var events: [ThreatEvent] = []
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("🚨") || line.contains("THREAT") || line.contains("CRITICAL") || line.contains("⚠️") {
                let severity = line.contains("CRITICAL") ? "critical" : 
                              line.contains("THREAT") ? "high" : 
                              line.contains("⚠️") ? "warning" : "medium"
                
                events.append(ThreatEvent(
                    timestamp: Date(),
                    source: "mac_blueteam",
                    severity: severity,
                    description: line.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
        
        return events
    }
    
    private func parseStatsFromText(_ text: String) -> SystemStats {
        var stats = SystemStats()
        
        // Try to extract basic stats from text output
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("CPU") || line.contains("cpu") {
                if let value = extractDouble(from: line) {
                    stats.cpu = value
                }
            } else if line.contains("Memory") || line.contains("memory") {
                if let value = extractDouble(from: line) {
                    stats.memory = value
                }
            } else if line.contains("Disk") || line.contains("disk") {
                if let value = extractDouble(from: line) {
                    stats.disk = value
                }
            }
        }
        
        return stats
    }
    
    private func extractDouble(from text: String) -> Double? {
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Double($0) }
        return numbers.first
    }
}

