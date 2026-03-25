import Foundation
#if os(macOS)
import AppKit
#endif

class ThreatIntelligenceService: ObservableObject {
    static let shared = ThreatIntelligenceService()
    
    private let threatIntelDir: URL
    private let threatIntelDB: URL
    private let threatMatchesFile: URL
    
    @Published var iocs: [ThreatIOC] = []
    @Published var threatMatches: [ThreatMatch] = []
    @Published var stats: ThreatIntelligenceStats = ThreatIntelligenceStats()
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        threatIntelDir = homeDir.appendingPathComponent(".macguardian/threat_intel")
        threatIntelDB = threatIntelDir.appendingPathComponent("iocs.json")
        threatMatchesFile = threatIntelDir.appendingPathComponent("matches.json")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: threatIntelDir, withIntermediateDirectories: true)
        
        loadIOCs()
        loadThreatMatches()
        updateStats()
    }
    
    // MARK: - IOC Management
    
    func loadIOCs() {
        guard FileManager.default.fileExists(atPath: threatIntelDB.path),
              let data = try? Data(contentsOf: threatIntelDB),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            iocs = []
            return
        }
        
        var loadedIOCs: [ThreatIOC] = []
        for json in jsonArray {
            if let ioc = parseIOC(from: json) {
                loadedIOCs.append(ioc)
            }
        }
        
        DispatchQueue.main.async {
            self.iocs = loadedIOCs
            self.updateStats()
        }
    }
    
    private func parseIOC(from json: [String: Any]) -> ThreatIOC? {
        guard let typeString = json["type"] as? String,
              let type = IOCType(rawValue: typeString),
              let value = json["value"] as? String,
              let source = json["source"] as? String else {
            return nil
        }
        
        let malicious = json["malicious"] as? Bool ?? true
        let description = json["description"] as? String
        
        // Parse timestamp
        var timestamp = Date()
        if let timestampString = json["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            timestamp = formatter.date(from: timestampString) ?? Date()
        }
        
        // Determine severity based on source and type
        let severity: ThreatSeverity = {
            if source.contains("critical") || source.contains("malware") {
                return .critical
            } else if source.contains("suspicious") {
                return .high
            } else if malicious {
                return .medium
            } else {
                return .low
            }
        }()
        
        return ThreatIOC(
            type: type,
            value: value,
            source: source,
            malicious: malicious,
            timestamp: timestamp,
            description: description,
            severity: severity
        )
    }
    
    // MARK: - IOC Checking
    
    func checkIOC(type: IOCType, value: String) -> ThreatIOC? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return iocs.first { ioc in
            ioc.type == type && ioc.value.lowercased() == normalizedValue.lowercased()
        }
    }
    
    func checkIOCAsync(type: IOCType, value: String, completion: @escaping (ThreatIOC?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let match = self.checkIOC(type: type, value: value)
            DispatchQueue.main.async {
                completion(match)
            }
        }
    }
    
    // MARK: - Threat Feed Management
    
    func updateThreatFeeds(completion: @escaping (Bool, String) -> Void) {
        isLoading = true
        lastError = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
                .appendingPathComponent("MacGuardianProject")
                .appendingPathComponent("MacGuardianSuite")
                .appendingPathComponent("threat_intel_feeds.sh")
                .path
            
            guard FileManager.default.fileExists(atPath: scriptPath) else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.lastError = "Threat intelligence script not found"
                    completion(false, "Script not found")
                }
                return
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "cd '\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/MacGuardianProject/MacGuardianSuite' && bash '\(scriptPath)' update"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if process.terminationStatus == 0 {
                        // Reload IOCs after update
                        self.loadIOCs()
                        completion(true, output.isEmpty ? "Threat feeds updated successfully" : output)
                    } else {
                        self.lastError = output.isEmpty ? "Failed to update feeds" : output
                        completion(false, output.isEmpty ? "Failed to update feeds" : output)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.lastError = error.localizedDescription
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Threat Match Tracking
    
    func recordThreatMatch(ioc: ThreatIOC, context: String? = nil, systemComponent: String? = nil) {
        let match = ThreatMatch(ioc: ioc, matchedAt: Date(), context: context, systemComponent: systemComponent)
        
        DispatchQueue.main.async {
            self.threatMatches.insert(match, at: 0) // Add to beginning
            self.saveThreatMatches()
            self.updateStats()
            
            // Send to Omega Guardian Event Pipeline
            let event = ThreatEvent(
                timestamp: Date(),
                source: ioc.source,
                severity: ioc.severity.rawValue,
                description: "IOC Match: \(ioc.type.displayName) = \(ioc.value)",
                category: ioc.type.rawValue,
                details: ["iocId": ioc.id.uuidString, "context": context ?? ""]
            )
            EventPipeline.shared.processThreatEvent(event)
        }
    }
    
    func loadThreatMatches() {
        guard FileManager.default.fileExists(atPath: threatMatchesFile.path),
              let data = try? Data(contentsOf: threatMatchesFile),
              let decoded = try? JSONDecoder().decode([ThreatMatch].self, from: data) else {
            threatMatches = []
            return
        }
        threatMatches = decoded
    }

    func saveThreatMatches() {
        guard let data = try? JSONEncoder().encode(threatMatches) else { return }
        try? data.write(to: threatMatchesFile)
    }
    
    // MARK: - Statistics
    
    func updateStats() {
        let totalIOCs = iocs.count
        
        var iocsByType: [String: Int] = [:]
        var iocsBySeverity: [String: Int] = [:]
        
        for ioc in iocs {
            iocsByType[ioc.type.rawValue, default: 0] += 1
            iocsBySeverity[ioc.severity.rawValue, default: 0] += 1
        }
        
        let lastUpdate = iocs.map { $0.timestamp }.max()
        
        let today = Calendar.current.startOfDay(for: Date())
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today
        
        let matchesToday = threatMatches.filter { $0.matchedAt >= today }.count
        let matchesThisWeek = threatMatches.filter { $0.matchedAt >= weekAgo }.count
        
        stats = ThreatIntelligenceStats(
            totalIOCs: totalIOCs,
            iocsByType: iocsByType,
            iocsBySeverity: iocsBySeverity,
            lastUpdate: lastUpdate,
            feedCount: 3, // Abuse.ch Feodo, URLhaus, Malware Domain List
            matchesToday: matchesToday,
            matchesThisWeek: matchesThisWeek
        )
    }
    
    // MARK: - Threat Feed Sources
    
    func getThreatFeeds() -> [ThreatFeed] {
        return [
            ThreatFeed(
                name: "Abuse.ch Feodo Tracker",
                source: "abuse_ch_feodo",
                url: "https://feodotracker.abuse.ch/downloads/ipblocklist_recommended.txt",
                lastUpdate: stats.lastUpdate,
                iocCount: stats.iocsByType["ip"] ?? 0,
                enabled: true
            ),
            ThreatFeed(
                name: "Abuse.ch URLhaus",
                source: "abuse_ch_urlhaus",
                url: "https://urlhaus.abuse.ch/downloads/csv_recent/",
                lastUpdate: stats.lastUpdate,
                iocCount: stats.iocsByType["url"] ?? 0,
                enabled: true
            ),
            ThreatFeed(
                name: "Malware Domain List",
                source: "malware_domain_list",
                url: "https://www.malwaredomainlist.com/hostslist/hosts.txt",
                lastUpdate: stats.lastUpdate,
                iocCount: stats.iocsByType["domain"] ?? 0,
                enabled: true
            )
        ]
    }
}

