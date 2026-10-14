import SwiftUI

/// Reusable connection status indicator component
struct ConnectionStatusIndicator: View {
    let isConnected: Bool
    let lastUpdate: Date?
    let showLastUpdate: Bool
    
    init(isConnected: Bool, lastUpdate: Date? = nil, showLastUpdate: Bool = true) {
        self.isConnected = isConnected
        self.lastUpdate = lastUpdate
        self.showLastUpdate = showLastUpdate
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(isConnected ? "Monitor running" : "Monitor not running")
                .font(.caption)
                .foregroundColor(.themeTextSecondary)
            
            if showLastUpdate, let lastUpdate = lastUpdate {
                Text("•")
                    .foregroundColor(.themeTextSecondary)
                Text("Last update: \(formatTime(lastUpdate))")
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
            
            Spacer()
        }
        .padding(.horizontal)
    }
    
    private var statusColor: Color {
        isConnected ? .green : Color(red: 0.9, green: 0.1, blue: 0.3) // Muted red-purple
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

