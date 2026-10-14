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
    
    /// Live system figures read from macOS's own tools (ps, vm_stat, df,
    /// netstat). Network throughput is measured over one second.
    private static let statsScript = #"""
    ncpu=$(sysctl -n hw.logicalcpu)
    ps -A -o %cpu= | awk -v n="$ncpu" '{s+=$1} END {printf "cpu=%.1f\n", s/n}'
    total=$(sysctl -n hw.memsize); page=$(sysctl -n hw.pagesize)
    vm_stat | awk -v t="$total" -v p="$page" '/Pages active/ {a=$3} /Pages wired down/ {w=$4} /occupied by compressor/ {c=$5} END {printf "memory=%.1f\n", (a+w+c)*p*100/t}'
    df -k /System/Volumes/Data | awk 'NR==2 {printf "disk=%.1f\n", $3*100/$2}'
    echo "processCount=$(( $(ps -A | wc -l) - 1 ))"
    echo "connectionCount=$(netstat -an -p tcp | grep -c ESTABLISHED)"
    net() { netstat -ib | awk '$1 ~ /^en[0-9]/ && $3 ~ /^<Link/ {i+=$7; o+=$10} END {print i+0, o+0}'; }
    read -r i1 o1 <<<"$(net)"; sleep 1; read -r i2 o2 <<<"$(net)"
    awk -v a="$i1" -v b="$i2" -v c="$o1" -v d="$o2" 'BEGIN {printf "networkIn=%.3f\nnetworkOut=%.3f\n", (b-a)/1048576, (d-c)/1048576}'
    """#

    func getSystemStats(repositoryPath: String) async -> SystemStats {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", Self.statsScript]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else {
                    continuation.resume(returning: SystemStats())
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                var values: [String: String] = [:]
                for line in (String(data: data, encoding: .utf8) ?? "").split(separator: "\n") {
                    let parts = line.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
                }
                let stats = SystemStats(
                    cpu: Double(values["cpu"] ?? "") ?? 0,
                    memory: Double(values["memory"] ?? "") ?? 0,
                    disk: Double(values["disk"] ?? "") ?? 0,
                    networkOut: Double(values["networkOut"] ?? "") ?? 0,
                    networkIn: Double(values["networkIn"] ?? "") ?? 0,
                    processCount: Int(values["processCount"] ?? ""),
                    connectionCount: Int(values["connectionCount"] ?? "")
                )
                continuation.resume(returning: stats)
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
    
    private func extractDouble(from text: String) -> Double? {
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Double($0) }
        return numbers.first
    }
}

