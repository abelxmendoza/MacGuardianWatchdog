import Foundation

// MARK: - Threat Intelligence Models

struct ThreatIOC: Identifiable, Codable, Hashable {
    let id: UUID
    let type: IOCType
    let value: String
    let source: String
    let malicious: Bool
    let timestamp: Date
    let description: String?
    let severity: ThreatSeverity
    
    init(id: UUID = UUID(), type: IOCType, value: String, source: String, malicious: Bool = true, timestamp: Date = Date(), description: String? = nil, severity: ThreatSeverity = .medium) {
        self.id = id
        self.type = type
        self.value = value
        self.source = source
        self.malicious = malicious
        self.timestamp = timestamp
        self.description = description
        self.severity = severity
    }
}

enum IOCType: String, Codable, CaseIterable {
    case ip = "ip"
    case domain = "domain"
    case hash = "hash"
    case url = "url"
    case filePath = "file_path"
    
    var displayName: String {
        switch self {
        case .ip: return "IP Address"
        case .domain: return "Domain"
        case .hash: return "File Hash"
        case .url: return "URL"
        case .filePath: return "File Path"
        }
    }
    
    var icon: String {
        switch self {
        case .ip: return "network"
        case .domain: return "globe"
        case .hash: return "number"
        case .url: return "link"
        case .filePath: return "doc.text"
        }
    }
}

enum ThreatSeverity: String, Codable, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var color: String {
        switch self {
        case .low: return "blue"
        case .medium: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }
}

struct ThreatFeed: Identifiable, Codable {
    let id: UUID
    let name: String
    let source: String
    let url: String
    let lastUpdate: Date?
    let iocCount: Int
    let enabled: Bool
    
    init(id: UUID = UUID(), name: String, source: String, url: String, lastUpdate: Date? = nil, iocCount: Int = 0, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.source = source
        self.url = url
        self.lastUpdate = lastUpdate
        self.iocCount = iocCount
        self.enabled = enabled
    }
}

struct ThreatMatch: Identifiable, Codable {
    let id: UUID
    let ioc: ThreatIOC
    let matchedAt: Date
    let context: String?
    let systemComponent: String? // e.g., "network_connection", "process", "file"

    init(id: UUID = UUID(), ioc: ThreatIOC, matchedAt: Date = Date(), context: String? = nil, systemComponent: String? = nil) {
        self.id = id
        self.ioc = ioc
        self.matchedAt = matchedAt
        self.context = context
        self.systemComponent = systemComponent
    }
}

struct ThreatIntelligenceStats: Codable {
    let totalIOCs: Int
    let iocsByType: [String: Int]
    let iocsBySeverity: [String: Int]
    let lastUpdate: Date?
    let feedCount: Int
    let matchesToday: Int
    let matchesThisWeek: Int
    
    init(totalIOCs: Int = 0, iocsByType: [String: Int] = [:], iocsBySeverity: [String: Int] = [:], lastUpdate: Date? = nil, feedCount: Int = 0, matchesToday: Int = 0, matchesThisWeek: Int = 0) {
        self.totalIOCs = totalIOCs
        self.iocsByType = iocsByType
        self.iocsBySeverity = iocsBySeverity
        self.lastUpdate = lastUpdate
        self.feedCount = feedCount
        self.matchesToday = matchesToday
        self.matchesThisWeek = matchesThisWeek
    }
}

