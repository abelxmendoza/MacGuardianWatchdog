import Foundation

// MARK: - Event Pipeline (Event Bus Listener)

class EventPipeline {
    static let shared = EventPipeline()
    
    private init() {
        // Subscribe to threat events from various sources
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe threat intelligence events
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ThreatIntelligenceMatch"),
            object: nil,
            queue: .main
        ) { notification in
            if let event = notification.object as? ThreatEvent {
                self.handleThreatEvent(event)
            }
        }
        
        // Observe Blue Team events
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("BlueTeamThreatEvent"),
            object: nil,
            queue: .main
        ) { notification in
            if let event = notification.object as? ThreatEvent {
                self.handleThreatEvent(event)
            }
        }
    }
    
    func handleThreatEvent(_ event: ThreatEvent) {
        for incident in AlertEngine.shared.processEvent(event) {
            IncidentStore.shared.add(incident)
        }
    }
    
    // Public method to manually trigger event processing
    func processThreatEvent(_ event: ThreatEvent) {
        handleThreatEvent(event)
    }
}

