import Foundation
import Combine

// MARK: - Alert Engine (Core Logic)

class AlertEngine: ObservableObject {
    static let shared = AlertEngine()
    
    private var rules: [AlertRule] = []
    private var lastTriggered: [UUID: Date] = [:]
    private let rulesStorageURL: URL
    
    var enabledCount: Int { rules.filter { $0.enabled }.count }
    var totalRulesCount: Int { rules.count }
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let omegaDir = homeDir.appendingPathComponent(".macguardian/omega_guardian")
        rulesStorageURL = omegaDir.appendingPathComponent("alert_rules.json")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: omegaDir, withIntermediateDirectories: true)
        
        loadRules()
        
        // Load default rules if none exist
        if rules.isEmpty {
            setupDefaultRules()
        }
    }
    
    func configure(rules: [AlertRule]) {
        self.rules = rules
        saveRules()
    }
    
    func addRule(_ rule: AlertRule) {
        rules.append(rule)
        saveRules()
    }
    
    func updateRule(_ rule: AlertRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            saveRules()
        }
    }
    
    func deleteRule(_ rule: AlertRule) {
        rules.removeAll { $0.id == rule.id }
        lastTriggered.removeValue(forKey: rule.id)
        saveRules()
    }
    
    func getAllRules() -> [AlertRule] {
        return rules
    }
    
    // Main evaluation method — returns all incidents triggered by this event
    func processEvent(_ event: ThreatEvent) -> [Incident] {
        let enabledRules = rules.filter { $0.enabled }
        var triggered: [Incident] = []

        for rule in enabledRules {
            guard matches(rule, event: event) else { continue }
            guard !isThrottled(rule) else { continue }

            updateThrottle(rule)

            triggered.append(Incident(
                timestamp: event.timestamp,
                severity: rule.severity,
                title: rule.name,
                message: "\(event.description)\nSource: \(event.source)",
                sourceModule: "OmegaGuardian",
                metadata: [
                    "eventId": event.id.uuidString,
                    "eventSource": event.source,
                    "eventSeverity": event.severity,
                    "ruleId": rule.id.uuidString,
                    "ruleName": rule.name
                ]
            ))
        }
        return triggered
    }
    
    // MARK: - Matching Logic
    
    func matches(_ rule: AlertRule, event: ThreatEvent) -> Bool {
        switch rule.condition {
        case .iocMatch:
            // Only fire when the event category is an actual IOC type set by ThreatIntelligenceService
            let iocCategories: Set<String> = ["ip", "domain", "hash", "url", "file_path"]
            return iocCategories.contains(event.category?.lowercased() ?? "")
            
        case .networkAnomaly:
            return event.description.lowercased().contains("network") ||
                   event.description.lowercased().contains("connection") ||
                   event.description.lowercased().contains("anomaly") ||
                   event.category?.lowercased() == "network"
            
        case .processBehavior:
            return event.description.lowercased().contains("process") ||
                   event.description.lowercased().contains("behavior") ||
                   event.description.lowercased().contains("suspicious") ||
                   event.category?.lowercased() == "process"
            
        case .fileModification:
            return event.description.lowercased().contains("file") ||
                   event.description.lowercased().contains("modification") ||
                   event.description.lowercased().contains("integrity") ||
                   event.category?.lowercased() == "filesystem"
            
        case .custom(let pattern):
            return event.description.lowercased().contains(pattern.lowercased()) ||
                   event.source.lowercased().contains(pattern.lowercased())
        }
    }
    
    func isThrottled(_ rule: AlertRule) -> Bool {
        guard let last = lastTriggered[rule.id] else { return false }
        let interval = Date().timeIntervalSince(last)
        return interval < Double(rule.throttleMinutes * 60)
    }
    
    func updateThrottle(_ rule: AlertRule) {
        lastTriggered[rule.id] = Date()
    }
    
    // MARK: - Default Rules Setup
    
    private func setupDefaultRules() {
        let defaultRules = [
            AlertRule(
                name: "Critical IOC Match",
                severity: .critical,
                condition: .iocMatch,
                enabled: true,
                throttleMinutes: 0,
                description: "Triggers when a critical IOC is matched"
            ),
            AlertRule(
                name: "Suspicious Process Behavior",
                severity: .high,
                condition: .processBehavior,
                enabled: true,
                throttleMinutes: 5,
                description: "Detects suspicious process activity"
            ),
            AlertRule(
                name: "Network Anomaly Detection",
                severity: .medium,
                condition: .networkAnomaly,
                enabled: true,
                throttleMinutes: 10,
                description: "Alerts on network anomalies"
            ),
            AlertRule(
                name: "File Integrity Violation",
                severity: .high,
                condition: .fileModification,
                enabled: true,
                throttleMinutes: 5,
                description: "Detects unauthorized file modifications"
            )
        ]
        
        rules = defaultRules
        saveRules()
    }
    
    // MARK: - Persistence
    
    private func loadRules() {
        guard FileManager.default.fileExists(atPath: rulesStorageURL.path),
              let data = try? Data(contentsOf: rulesStorageURL),
              let decoded = try? JSONDecoder().decode([AlertRule].self, from: data) else {
            rules = []
            return
        }
        rules = decoded
    }
    
    private func saveRules() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: rulesStorageURL)
    }
}

