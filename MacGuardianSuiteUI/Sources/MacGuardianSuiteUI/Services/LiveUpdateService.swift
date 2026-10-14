import Foundation
import Combine
import Network
import SwiftUI

/// Standardized event structure matching Event Spec v1.0.0
struct MacGuardianEvent: Codable, Identifiable {
    let id: String  // Maps from event_id (UUID string)
    let event_type: String  // Event Spec v1.0.0 field name
    let severity: String
    let timestamp: String
    let source: String
    let context: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case id = "event_id"
        case event_type
        case severity
        case timestamp
        case source
        case context
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.event_type = try container.decode(String.self, forKey: .event_type)
        self.severity = try container.decode(String.self, forKey: .severity)
        self.timestamp = try container.decode(String.self, forKey: .timestamp)
        self.source = try container.decode(String.self, forKey: .source)
        self.context = try container.decode([String: AnyCodable].self, forKey: .context)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(event_type, forKey: .event_type)
        try container.encode(severity, forKey: .severity)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(source, forKey: .source)
        try container.encode(context, forKey: .context)
    }
    
    // Computed property for backward compatibility
    var type: String {
        event_type
    }
    
    // Extract message from context if available
    var message: String {
        if let msg = context["message"]?.value as? String {
            return msg
        }
        // Try common message fields
        if let msg = context["raw_message"]?.value as? String {
            return msg
        }
        // Generate message from event type
        return "\(event_type) event detected"
    }
    
    var severityColor: Color {
        switch severity.lowercased() {
        case "critical": return Color(red: 0.9, green: 0.1, blue: 0.3) // Muted red-purple
        case "high": return Color(red: 0.8, green: 0.3, blue: 0.5) // Purple-red blend
        case "warning", "medium": return .themePurpleLight // Lighter purple
        default: return .themePurple // Base purple
        }
    }
    
    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }
}

extension MacGuardianEvent: Equatable {
    static func == (lhs: MacGuardianEvent, rhs: MacGuardianEvent) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Helper for decoding Any JSON values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

/// Reads the events the monitor daemon (daemons/mg_monitor.sh) writes to
/// ~/.macguardian/events, one JSON file per event, and picks up new files as
/// they appear. "Connected" means the monitor daemon is actually running.
final class EventFileWatcher {
    private let eventDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".macguardian/events")
    private let pidFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".macguardian/.monitor.pid")
    private let initialLoadLimit = 500
    private let pollInterval: UInt64 = 3_000_000_000
    private var lastSeenName = ""
    private var pollTask: Task<Void, Never>?

    /// Called with each event file's JSON text, oldest first.
    var onEvent: ((String) -> Void)?
    /// Called after each poll with whether the monitor daemon is running.
    var onStatus: ((Bool) -> Void)?

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(nanoseconds: self?.pollInterval ?? 3_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll() {
        onStatus?(monitorIsRunning())

        // File names start with the event's Unix time, so name order is time order.
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: eventDir.path) else { return }
        var fresh = names.filter { $0.hasSuffix(".json") && $0 > lastSeenName }.sorted()
        if lastSeenName.isEmpty {
            fresh = Array(fresh.suffix(initialLoadLimit))
        }
        guard let newest = fresh.last else { return }
        lastSeenName = newest

        for name in fresh {
            let url = eventDir.appendingPathComponent(name)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                onEvent?(text)
            }
        }
    }

    private func monitorIsRunning() -> Bool {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return kill(pid, 0) == 0
    }
}

/// Live update service for real-time event streaming
/// Uses high-performance RingBuffer and EventIndex with Swift Actors
/// Implements batching to reduce UI update storms
@MainActor
class LiveUpdateService: ObservableObject {
    static let shared = LiveUpdateService()
    
    // High-performance data structures
    private let ringBuffer: RingBuffer<MacGuardianEvent>
    private let eventIndex: EventIndex
    private let timelineHeap: TimelineHeap
    
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var lastUpdate: Date?
    
    private let eventWatcher = EventFileWatcher()
    private let decoder = JSONDecoder()
    
    // Batch processing
    private var pendingEvents: [MacGuardianEvent] = []
    private var batchTask: Task<Void, Never>?
    private let batchInterval: TimeInterval = 0.1 // 100ms batching
    
    // Cached events snapshot (updated in batches) - @Published for SwiftUI
    @Published private(set) var events: [MacGuardianEvent] = []
    
    // Published filtered event arrays (updated from actors on main thread)
    @Published private(set) var criticalEvents: [MacGuardianEvent] = []
    @Published private(set) var highSeverityEvents: [MacGuardianEvent] = []
    @Published private(set) var processEvents: [MacGuardianEvent] = []
    @Published private(set) var networkEvents: [MacGuardianEvent] = []
    @Published private(set) var filesystemEvents: [MacGuardianEvent] = []
    @Published private(set) var sshEvents: [MacGuardianEvent] = []
    @Published private(set) var userAccountEvents: [MacGuardianEvent] = []
    @Published private(set) var privacyEvents: [MacGuardianEvent] = []
    @Published private(set) var cronEvents: [MacGuardianEvent] = []
    @Published private(set) var idsEvents: [MacGuardianEvent] = []
    @Published private(set) var ransomwareEvents: [MacGuardianEvent] = []
    @Published private(set) var signatureEvents: [MacGuardianEvent] = []
    @Published private(set) var recentEvents: [MacGuardianEvent] = []
    @Published private(set) var reverseChronologicalEvents: [MacGuardianEvent] = []
    
    private init() {
        // Initialize high-performance structures
        self.ringBuffer = RingBuffer<MacGuardianEvent>(capacity: 1000)
        self.eventIndex = EventIndex(maxEventsPerType: 500)
        self.timelineHeap = TimelineHeap(maxSize: 10000)
        
        eventWatcher.onEvent = { [weak self] text in
            Task { @MainActor in self?.handleEventJSON(text) }
        }
        eventWatcher.onStatus = { [weak self] running in
            Task { @MainActor in
                guard let self, self.isConnected != running else { return }
                self.isConnected = running
                self.connectionError = running ? nil : "The monitor daemon is not running"
            }
        }
        setupPerformanceObservers()
        startBatchProcessor()
    }
    
    private func setupPerformanceObservers() {
        // Observe ring buffer updates and refresh published properties
        ringBuffer.$didUpdate
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.lastUpdate = Date()
                    await self.refreshPublishedEvents()
                }
            }
            .store(in: &cancellables)
        
        // Observe event index updates
        eventIndex.$didUpdate
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.lastUpdate = Date()
                    await self.refreshPublishedEvents()
                }
            }
            .store(in: &cancellables)
        
        // Observe timeline heap updates
        timelineHeap.$didUpdate
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    await self.refreshPublishedEvents()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Refresh all published event arrays from actors (called on MainActor)
    @MainActor
    private func refreshPublishedEvents() async {
        // Update all filtered arrays from actors
        events = await ringBuffer.snapshot()
        criticalEvents = events.filter { $0.severity.lowercased() == "critical" }
        highSeverityEvents = events.filter { $0.severity.lowercased() == "high" }
        processEvents = await eventIndex.events(forType: "process_anomaly")
        networkEvents = await eventIndex.events(forType: "network_connection")
        filesystemEvents = await eventIndex.events(forType: "file_integrity_change")
        sshEvents = await eventIndex.events(forTypes: ["ssh_key_change", "ssh_config_change", "ssh_login_failure"])
        userAccountEvents = await eventIndex.events(forType: "user_account_change")
        privacyEvents = await eventIndex.events(forType: "tcc_permission_change")
        cronEvents = await eventIndex.events(forType: "cron_modification")
        idsEvents = await eventIndex.events(forTypes: ["ids_alert", "incident.detected"])
        ransomwareEvents = await eventIndex.events(forType: "ransomware_activity")
        signatureEvents = await eventIndex.events(forType: "signature_hit")
        recentEvents = await ringBuffer.recent(50)
        reverseChronologicalEvents = timelineHeap.getAllReverseChronological()
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    func start() {
        eventWatcher.start()
    }

    func stop() {
        eventWatcher.stop()
        batchTask?.cancel()
    }

    /// Decode one event and queue it for the next batch
    func handleEventJSON(_ text: String) {
        // Process decoding in detached task to avoid blocking UI
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            guard let data = text.data(using: .utf8) else {
                print("⚠️ Failed to convert message to data")
                return
            }
            
            do {
                let event = try self.decoder.decode(MacGuardianEvent.self, from: data)
                
                // Add to pending batch
                await self.addToBatch(event)
            } catch {
                print("⚠️ Failed to decode event: \(error)")
                print("⚠️ Raw message: \(text.prefix(200))")
            }
        }
    }
    
    /// Add event to batch queue
    private func addToBatch(_ event: MacGuardianEvent) async {
        await MainActor.run {
            pendingEvents.append(event)
        }
    }
    
    /// Start batch processor (flushes every 100ms)
    private func startBatchProcessor() {
        batchTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(batchInterval * 1_000_000_000))
                
                await self.flushBatch()
            }
        }
    }
    
    /// Flush pending events batch
    private func flushBatch() async {
        let batch = await MainActor.run {
            let batch = pendingEvents
            pendingEvents.removeAll()
            return batch
        }
        
        guard !batch.isEmpty else { return }
        
        // Process batch in parallel
        await withTaskGroup(of: Void.self) { group in
            for event in batch {
                group.addTask { [weak self] in
                    guard let self = self else { return }
                    
                    // High-performance insertion: O(1) operations
                    await self.ringBuffer.push(event)
                    await self.eventIndex.insert(event)
                    await self.timelineHeap.insert(event)
                }
            }
        }
        
        // Update cached snapshot and refresh all published properties
        await MainActor.run {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.refreshPublishedEvents()
            }
        }
    }
    
    // Async accessors for advanced use cases (backward compatibility)
    func events(forType type: String) async -> [MacGuardianEvent] {
        return await eventIndex.events(forType: type)  // O(1) lookup
    }
    
    func events(forSeverity severity: String) async -> [MacGuardianEvent] {
        // Filter all events by severity (could be optimized with severity index)
        let allEvents = await ringBuffer.snapshot()
        return allEvents.filter { $0.severity.lowercased() == severity.lowercased() }
    }
    
    // Direct access to performance structures (for advanced use cases)
    var index: EventIndex {
        return eventIndex
    }
    
    var buffer: RingBuffer<MacGuardianEvent> {
        return ringBuffer
    }
    
    var timeline: TimelineHeap {
        return timelineHeap
    }
    
    // Clear all events from memory
    func clearEvents() async {
        ringBuffer.clear()
        eventIndex.clear()
        timelineHeap.clear()
        await refreshPublishedEvents()
    }
}

