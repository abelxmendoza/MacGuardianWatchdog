import SwiftUI

struct ThreatIntelligenceView: View {
    @StateObject private var threatService = ThreatIntelligenceService.shared
    @State private var selectedTab: ThreatTab = .checker
    @State private var iocType: IOCType = .ip
    @State private var iocValue: String = ""
    @State private var checkingIOC: Bool = false
    @State private var iocCheckResult: ThreatIOC?
    @State private var showIOCResult: Bool = false
    
    enum ThreatTab: String, CaseIterable {
        case checker = "IOC Checker"
        case feeds = "Threat Feeds"
        case matches = "Threat Matches"
        case stats = "Statistics"
        
        var icon: String {
            switch self {
            case .checker: return "magnifyingglass"
            case .feeds: return "antenna.radiowaves.left.and.right"
            case .matches: return "exclamationmark.triangle.fill"
            case .stats: return "chart.bar.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title)
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Threat Intelligence")
                        .font(.title.bold())
                        .foregroundColor(.themeText)
                    Text("IOC checking, threat feeds, and correlation")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                
                // Quick stats badge
                HStack(spacing: 16) {
                    StatBadge(
                        label: "IOCs",
                        value: "\(threatService.stats.totalIOCs)",
                        color: .blue
                    )
                    StatBadge(
                        label: "Matches",
                        value: "\(threatService.stats.matchesToday)",
                        color: threatService.stats.matchesToday > 0 ? .red : .green
                    )
                }
            }
            .padding()
            .background(Color.themeDarkGray)
            
            Divider()
                .background(Color.themePurpleDark)

            FeatureInfoCard(
                icon: "shield.lefthalf.filled",
                title: "Threat Intelligence",
                whatItDoes: "Lets you check any IP, domain, file hash, or URL (an \"IOC\" - Indicator of Compromise) against public threat feeds, and automatically cross-references what those feeds flag against activity elsewhere on this Mac.",
                whyItMatters: "Recognizing a bad actor by name only works if you know their names. This keeps that list current from public sources (Abuse.ch, URLhaus) instead of relying on a list that goes stale the day it ships.",
                checks: ["IPs, domains, file hashes, and URLs you look up manually", "Threat feed freshness and IOC counts", "Matches between feed data and events seen elsewhere in the suite"]
            )
            .padding(.horizontal)
            .padding(.top, 12)

            // Tab selector
            HStack(spacing: 0) {
                ForEach(ThreatTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                            Text(tab.rawValue)
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(selectedTab == tab ? .white : .themeTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedTab == tab ? Color.themePurple : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.themeDarkGray.opacity(0.5))
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch selectedTab {
                    case .checker:
                        IOCCheckerTab(
                            iocType: $iocType,
                            iocValue: $iocValue,
                            checkingIOC: $checkingIOC,
                            iocCheckResult: $iocCheckResult,
                            showIOCResult: $showIOCResult,
                            threatService: threatService
                        )
                    case .feeds:
                        ThreatFeedsTab(threatService: threatService)
                    case .matches:
                        ThreatMatchesTab(threatService: threatService)
                    case .stats:
                        ThreatStatsTab(threatService: threatService)
                    }
                }
                .padding()
            }
            .background(Color.themeBlack)
        }
        .background(Color.themeBlack)
        .onAppear {
            threatService.loadIOCs()
        }
    }
}

// MARK: - IOC Checker Tab

struct IOCCheckerTab: View {
    @Binding var iocType: IOCType
    @Binding var iocValue: String
    @Binding var checkingIOC: Bool
    @Binding var iocCheckResult: ThreatIOC?
    @Binding var showIOCResult: Bool
    @ObservedObject var threatService: ThreatIntelligenceService
    
    var body: some View {
        VStack(spacing: 24) {
            // IOC Checker Card
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.themePurple)
                    Text("IOC Checker")
                        .font(.headline)
                        .foregroundColor(.themeText)
                    Spacer()
                }
                
                Text("Check Indicators of Compromise (IOCs) against threat intelligence database")
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
                
                // IOC Type Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("IOC Type")
                        .font(.subheadline.bold())
                        .foregroundColor(.themeText)
                    
                    Picker("IOC Type", selection: $iocType) {
                        ForEach(IOCType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // IOC Value Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("IOC Value")
                        .font(.subheadline.bold())
                        .foregroundColor(.themeText)
                    
                    HStack {
                        TextField("Enter \(iocType.displayName.lowercased())", text: $iocValue)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(Color.themeDarkGray)
                            .cornerRadius(8)
                            .foregroundColor(.themeText)
                        
                        Button {
                            checkIOC()
                        } label: {
                            if checkingIOC {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.shield.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.themePurple)
                        .disabled(iocValue.isEmpty || checkingIOC)
                    }
                }
                
                // Examples
                VStack(alignment: .leading, spacing: 8) {
                    Text("Examples:")
                        .font(.caption.bold())
                        .foregroundColor(.themeTextSecondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ExampleChip(text: "192.168.1.100", action: { iocType = .ip; iocValue = "192.168.1.100" })
                            ExampleChip(text: "example.com", action: { iocType = .domain; iocValue = "example.com" })
                            ExampleChip(text: "abc123...", action: { iocType = .hash; iocValue = "abc123def456" })
                            ExampleChip(text: "https://...", action: { iocType = .url; iocValue = "https://example.com" })
                        }
                    }
                }
            }
            .padding()
            .background(Color.themeDarkGray)
            .cornerRadius(12)
            
            // Check Result
            if showIOCResult, let result = iocCheckResult {
                IOCResultCard(ioc: result)
            } else if showIOCResult {
                CleanResultCard()
            }
        }
    }
    
    private func checkIOC() {
        guard !iocValue.isEmpty else { return }
        
        checkingIOC = true
        showIOCResult = false
        
        threatService.checkIOCAsync(type: iocType, value: iocValue) { match in
            checkingIOC = false
            iocCheckResult = match
            showIOCResult = true
            
            if let match = match {
                threatService.recordThreatMatch(ioc: match, context: "Manual check")
            }
        }
    }
}

struct ExampleChip: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.themePurple.opacity(0.2))
                .foregroundColor(.themePurple)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct IOCResultCard: View {
    let ioc: ThreatIOC
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                Text("Threat Detected")
                    .font(.headline)
                    .foregroundColor(.red)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ThreatDetailRow(label: "Type", value: ioc.type.displayName)
                ThreatDetailRow(label: "Value", value: ioc.value)
                ThreatDetailRow(label: "Source", value: ioc.source)
                ThreatDetailRow(label: "Severity", value: ioc.severity.displayName)
                if let description = ioc.description {
                    ThreatDetailRow(label: "Description", value: description)
                }
            }
            
            HStack {
                Label("Malicious", systemImage: "xmark.shield.fill")
                    .font(.caption.bold())
                    .foregroundColor(.red)
                Spacer()
                Text(ioc.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red, lineWidth: 2)
        )
        .cornerRadius(12)
    }
}

struct CleanResultCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
                .font(.system(size: 48))
            Text("No Threat Detected")
                .font(.headline)
                .foregroundColor(.green)
            Text("This IOC is not found in the threat intelligence database")
                .font(.caption)
                .foregroundColor(.themeTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.green.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green, lineWidth: 2)
        )
        .cornerRadius(12)
    }
}

struct ThreatDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption.bold())
                .foregroundColor(.themeTextSecondary)
            Text(value)
                .font(.caption)
                .foregroundColor(.themeText)
            Spacer()
        }
    }
}

// MARK: - Threat Feeds Tab

struct ThreatFeedsTab: View {
    @ObservedObject var threatService: ThreatIntelligenceService
    
    var body: some View {
        VStack(spacing: 24) {
            // Update Feeds Card
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.themePurple)
                    Text("Threat Feed Management")
                        .font(.headline)
                        .foregroundColor(.themeText)
                    Spacer()
                }
                
                Text("Update threat intelligence feeds from public sources")
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
                
                Button {
                    updateFeeds()
                } label: {
                    HStack {
                        if threatService.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text("Update Threat Feeds")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.themePurple)
                .disabled(threatService.isLoading)
                
                if let error = threatService.lastError {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
            .padding()
            .background(Color.themeDarkGray)
            .cornerRadius(12)
            
            // Feed List
            VStack(alignment: .leading, spacing: 12) {
                Text("Active Feeds")
                    .font(.headline)
                    .foregroundColor(.themeText)
                
                ForEach(threatService.getThreatFeeds()) { feed in
                    ThreatFeedRow(feed: feed)
                }
            }
        }
    }
    
    private func updateFeeds() {
        threatService.updateThreatFeeds { success, message in
            // Result handled by threatService state
        }
    }
}

struct ThreatFeedRow: View {
    let feed: ThreatFeed
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feed.enabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(feed.enabled ? .green : .gray)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(feed.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.themeText)
                Text(feed.source)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(feed.iocCount) IOCs")
                    .font(.caption.bold())
                    .foregroundColor(.themePurple)
                if let lastUpdate = feed.lastUpdate {
                    Text(lastUpdate, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.themeTextSecondary)
                } else {
                    Text("Never updated")
                        .font(.caption2)
                        .foregroundColor(.themeTextSecondary)
                }
            }
        }
        .padding()
        .background(Color.themeDarkGray.opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Threat Matches Tab

struct ThreatMatchesTab: View {
    @ObservedObject var threatService: ThreatIntelligenceService
    
    var body: some View {
        VStack(spacing: 24) {
            if threatService.threatMatches.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 48))
                    Text("No Threat Matches")
                        .font(.headline)
                        .foregroundColor(.themeText)
                    Text("No threats have been detected recently")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Threat Matches")
                        .font(.headline)
                        .foregroundColor(.themeText)
                    
                    ForEach(threatService.threatMatches.prefix(20)) { match in
                        ThreatMatchRow(match: match)
                    }
                }
            }
        }
    }
}

struct ThreatMatchRow: View {
    let match: ThreatMatch
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(match.ioc.type.displayName)
                    .font(.subheadline.bold())
                    .foregroundColor(.themeText)
                Spacer()
                Text(match.matchedAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
            
            Text(match.ioc.value)
                .font(.caption)
                .foregroundColor(.themeTextSecondary)
                .lineLimit(1)
            
            HStack {
                Label(match.ioc.source, systemImage: "tag.fill")
                    .font(.caption2)
                    .foregroundColor(.themePurple)
                if let component = match.systemComponent {
                    Label(component, systemImage: "gearshape.fill")
                        .font(.caption2)
                        .foregroundColor(.themeTextSecondary)
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Threat Statistics Tab

struct ThreatStatsTab: View {
    @ObservedObject var threatService: ThreatIntelligenceService
    
    var body: some View {
        VStack(spacing: 24) {
            // Overview Stats
            HStack(spacing: 16) {
                ThreatStatCard(
                    title: "Total IOCs",
                    value: "\(threatService.stats.totalIOCs)",
                    icon: "shield.fill",
                    color: .blue
                )
                ThreatStatCard(
                    title: "Matches Today",
                    value: "\(threatService.stats.matchesToday)",
                    icon: "exclamationmark.triangle.fill",
                    color: threatService.stats.matchesToday > 0 ? .red : .green
                )
                ThreatStatCard(
                    title: "Matches This Week",
                    value: "\(threatService.stats.matchesThisWeek)",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .orange
                )
            }
            
            // IOCs by Type
            VStack(alignment: .leading, spacing: 12) {
                Text("IOCs by Type")
                    .font(.headline)
                    .foregroundColor(.themeText)
                
                ForEach(Array(threatService.stats.iocsByType.keys.sorted()), id: \.self) { type in
                    if let count = threatService.stats.iocsByType[type],
                       let iocType = IOCType(rawValue: type) {
                        HStack {
                            Image(systemName: iocType.icon)
                            Text(iocType.displayName)
                            Spacer()
                            Text("\(count)")
                                .font(.headline)
                                .foregroundColor(.themePurple)
                        }
                        .padding()
                        .background(Color.themeDarkGray)
                        .cornerRadius(8)
                    }
                }
            }
            
            // IOCs by Severity
            VStack(alignment: .leading, spacing: 12) {
                Text("IOCs by Severity")
                    .font(.headline)
                    .foregroundColor(.themeText)
                
                ForEach(ThreatSeverity.allCases, id: \.self) { severity in
                    if let count = threatService.stats.iocsBySeverity[severity.rawValue] {
                        HStack {
                            Circle()
                                .fill(Color(severity.color))
                                .frame(width: 12, height: 12)
                            Text(severity.displayName)
                            Spacer()
                            Text("\(count)")
                                .font(.headline)
                                .foregroundColor(.themePurple)
                        }
                        .padding()
                        .background(Color.themeDarkGray)
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
}

struct ThreatStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            Text(value)
                .font(.title.bold())
                .foregroundColor(.themeText)
            Text(title)
                .font(.caption)
                .foregroundColor(.themeTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.themeDarkGray)
        .cornerRadius(12)
    }
}

struct StatBadge: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.themeTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

