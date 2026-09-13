import Foundation
import Combine

@MainActor
class BlueTeamViewModel: ObservableObject {
    @Published var events: [ThreatEvent] = []
    @Published var stats: SystemStats = SystemStats()
    @Published var isLoadingEvents = false
    @Published var isLoadingStats = false
    @Published var lastUpdate: Date?
    @Published var errorMessage: String?

    /// Set by the view from WorkspaceState.repositoryPath before refreshing,
    /// so the auto-refresh timer (which has no view context of its own) can
    /// keep using the user's configured path instead of a hardcoded guess.
    var repositoryPath: String = ""

    private var refreshTimer: Timer?
    private let autoRefreshInterval: TimeInterval = 30.0 // 30 seconds
    
    init() {
        // Auto-refresh every 30 seconds when active
    }
    
    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: autoRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    func refresh() async {
        await loadEvents()
        await loadStats()
        lastUpdate = Date()
    }
    
    func loadEvents() async {
        isLoadingEvents = true
        errorMessage = nil
        
        let loadedEvents = await BlueTeamScriptService.shared.runCollector(repositoryPath: repositoryPath)
        
        // Merge with existing events, avoiding duplicates
        let existingIds = Set(events.map { $0.id })
        let newEvents = loadedEvents.filter { !existingIds.contains($0.id) }
        events.append(contentsOf: newEvents)
        
        // Sort by timestamp (newest first)
        events.sort { $0.timestamp > $1.timestamp }
        
        // Keep only last 100 events
        if events.count > 100 {
            events = Array(events.prefix(100))
        }
        
        isLoadingEvents = false
    }
    
    func loadStats() async {
        isLoadingStats = true
        
        let loadedStats = await BlueTeamScriptService.shared.getSystemStats(repositoryPath: repositoryPath)
        stats = loadedStats
        
        isLoadingStats = false
    }
    
    func clearEvents() {
        events = []
    }
    
    var criticalEventsCount: Int {
        events.filter { $0.severity.lowercased() == "critical" }.count
    }
    
    var highSeverityEventsCount: Int {
        events.filter { $0.severity.lowercased() == "high" }.count
    }
    
    var recentEvents: [ThreatEvent] {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return events.filter { $0.timestamp > oneHourAgo }
    }
}

