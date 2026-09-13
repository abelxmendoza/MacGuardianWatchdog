import SwiftUI

struct NetworkGraphView: View {
    @StateObject private var viewModel = NetworkGraphViewModel()
    @State private var networkGraph: NetworkGraphData?
    @State private var isLoading = false
    @State private var selectedNode: GraphNode?
    
    // High-performance graph nodes using adjacency list (O(V + E))
    var realTimeNodes: [GraphNode] {
        viewModel.nodes
    }
    
    // High-performance graph edges using adjacency list (O(E))
    var realTimeEdges: [GraphEdge] {
        viewModel.edges
    }
    
    // Statistics from graph builder
    var graphStats: GraphStatistics? {
        viewModel.statistics
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "network")
                        .font(.title)
                        .foregroundColor(.themePurple)
                    VStack(alignment: .leading) {
                        Text("Network Flow")
                            .font(.title.bold())
                        Text("Process → Port → IP connections")
                            .font(.subheadline)
                            .foregroundColor(.themeTextSecondary)
                    }
                    Spacer()
                    Button {
                        buildGraph()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.themePurple)
                    .disabled(isLoading)
                }
                .padding()

                FeatureInfoCard(
                    icon: "network",
                    title: "Network Flow",
                    whatItDoes: "Draws a live map of which process is talking to which port and IP address, so you can see the actual chain: app → port → destination.",
                    whyItMatters: "Malware often hides in plain sight as a process with a boring name, but its network behavior gives it away - talking to an unfamiliar IP on an unusual port, or a process that should never touch the network doing so anyway. Seeing the graph makes that pattern obvious in a way a text log doesn't.",
                    checks: ["Every process with an active network connection", "Destination IPs and ports", "Connections to known-suspicious hosts (cross-checked against threat intel)"]
                )
                .padding(.horizontal)

                Divider()

                // Real-time Connection Status
                HStack {
                    ConnectionStatusIndicator(
                        isConnected: LiveUpdateService.shared.isConnected,
                        lastUpdate: LiveUpdateService.shared.lastUpdate,
                        showLastUpdate: false
                    )
                    Spacer()
                    Text("\(realTimeNodes.count) node(s), \(realTimeEdges.count) connection(s)")
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                
                if isLoading {
                    ProgressView("Building network graph...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        // Statistics from high-performance graph builder
                        if let stats = graphStats {
                            HStack(spacing: 16) {
                                StatCard(
                                    title: "Nodes",
                                    value: "\(stats.processCount + stats.ipCount)",
                                    icon: "circle.grid.2x2",
                                    color: .themePurple
                                )
                                StatCard(
                                    title: "Connections",
                                    value: "\(stats.connectionCount)",
                                    icon: "arrow.triangle.branch",
                                    color: .themePurpleLight
                                )
                                StatCard(
                                    title: "Processes",
                                    value: "\(stats.processCount)",
                                    icon: "cpu",
                                    color: .themePurple
                                )
                            }
                            .padding()
                        }
                        
                        // Real-time Network Graph Visualization
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Network Connections (Real-Time)")
                                .font(.headline.bold())
                            
                            // Process nodes
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Processes")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.themeTextSecondary)
                                
                                if realTimeNodes.filter({ $0.type == "process" }).isEmpty {
                                    Text("No active processes detected")
                                        .font(.caption)
                                        .foregroundColor(.themeTextSecondary)
                                        .padding()
                                } else {
                                    ForEach(realTimeNodes.filter { $0.type == "process" }.prefix(10), id: \.id) { node in
                                        ProcessNodeRow(node: node) {
                                            selectedNode = node
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color.themeDarkGray)
                            .cornerRadius(12)
                            
                            // IP nodes
                            VStack(alignment: .leading, spacing: 8) {
                                Text("IP Addresses")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.themeTextSecondary)
                                
                                if realTimeNodes.filter({ $0.type == "ip" }).isEmpty {
                                    Text("No IP connections detected")
                                        .font(.caption)
                                        .foregroundColor(.themeTextSecondary)
                                        .padding()
                                } else {
                                    ForEach(realTimeNodes.filter { $0.type == "ip" }.prefix(10), id: \.id) { node in
                                        IPNodeRow(node: node) {
                                            selectedNode = node
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color.themeDarkGray)
                            .cornerRadius(12)
                            
                            // Recent Network Events
                            if !viewModel.networkEvents.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Recent Network Events")
                                        .font(.headline.bold())
                                    
                                    ForEach(viewModel.networkEvents.prefix(10)) { event in
                                        NetworkEventRow(event: event)
                                    }
                                }
                                .padding()
                                .background(Color.themeDarkGray)
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                        
                        // Static Graph (if available)
                        if let graph = networkGraph {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Last Snapshot")
                                    .font(.headline.bold())
                                
                                Text("Static snapshot from last refresh")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                            .padding()
                            .background(Color.themeBlack.opacity(0.5))
                            .cornerRadius(8)
                        } else if viewModel.networkEvents.isEmpty {
                            EmptyStateView(
                                icon: "network",
                                title: "No network events",
                                message: "Network connections will appear here in real-time"
                            )
                        }
                    }
                }
            }
        }
        .background(Color.themeBlack)
        .sheet(item: $selectedNode) { node in
            NodeDetailView(node: node)
        }
        .onAppear {
            loadGraph()
        }
    }
    
    private func buildGraph() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/MacGuardianProject/MacGuardianSuite/graphs/network_flow_builder.py"
            let outputPath = "/tmp/network_graph.json"
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [scriptPath, outputPath]
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if let data = try? Data(contentsOf: URL(fileURLWithPath: outputPath)),
                   let graph = try? JSONDecoder().decode(NetworkGraphData.self, from: data) {
                    DispatchQueue.main.async {
                        self.networkGraph = graph
                        self.isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadGraph() {
        let graphPath = "/tmp/network_graph.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: graphPath)),
              let graph = try? JSONDecoder().decode(NetworkGraphData.self, from: data) else {
            return
        }
        
        networkGraph = graph
    }
}

struct NetworkGraphData: Codable {
    let timestamp: String
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let connectionCount: Int
    let processCount: Int
    
    enum CodingKeys: String, CodingKey {
        case timestamp, nodes, edges
        case connectionCount = "connection_count"
        case processCount = "process_count"
    }
}

struct GraphNode: Codable, Identifiable {
    let id: Int
    let label: String
    let type: String
    let pid: Int?
    let ip: String?
    let name: String?
}

struct GraphEdge: Codable, Identifiable {
    let id: String
    let from: Int
    let to: Int
    let label: String?
    let port: Int?
    let localPort: Int?
    let remotePort: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, from, to, label, port
        case localPort = "local_port"
        case remotePort = "remote_port"
    }
    
    init(id: String = UUID().uuidString, from: Int, to: Int, label: String?, port: Int?, localPort: Int?, remotePort: Int?) {
        self.id = id
        self.from = from
        self.to = to
        self.label = label
        self.port = port
        self.localPort = localPort
        self.remotePort = remotePort
    }
}

struct ProcessNodeRow: View {
    let node: GraphNode
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.themePurple)
                VStack(alignment: .leading) {
                    Text(node.label)
                        .font(.subheadline.bold())
                    if let pid = node.pid {
                        Text("PID: \(pid)")
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.themeTextSecondary)
            }
            .padding()
            .background(Color.themeBlack.opacity(0.5))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// Real-time Network Event Row Component
struct NetworkEventRow: View {
    let event: MacGuardianEvent
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Severity indicator
            Circle()
                .fill(event.severityColor)
                .frame(width: 12, height: 12)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.event_type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline.bold())
                        .foregroundColor(.themeText)
                    Spacer()
                    if let date = event.date {
                        Text(formatTime(date))
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                    }
                }
                
                Text(event.message)
                    .font(.subheadline)
                    .foregroundColor(.themeTextSecondary)
                
                // Show connection details
                HStack(spacing: 12) {
                    if let process = event.context["process"]?.value as? String {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.caption2)
                            Text(process)
                                .font(.caption)
                        }
                        .foregroundColor(.themePurple.opacity(0.7))
                    }
                    
                    if let ip = event.context["ip"]?.value as? String ?? event.context["remote_ip"]?.value as? String {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.caption2)
                            Text(ip)
                                .font(.caption)
                        }
                        .foregroundColor(.themePurpleLight.opacity(0.7))
                    }
                    
                    if let port = event.context["port"]?.value as? Int ?? event.context["remote_port"]?.value as? Int {
                        HStack(spacing: 4) {
                            Image(systemName: "network")
                                .font(.caption2)
                            Text("\(port)")
                                .font(.caption)
                        }
                        .foregroundColor(.themePurple.opacity(0.7))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.themePurple.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding()
        .background(Color.themeBlack.opacity(0.5))
        .cornerRadius(8)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct IPNodeRow: View {
    let node: GraphNode
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.themePurpleLight)
                VStack(alignment: .leading) {
                    Text(node.label)
                        .font(.subheadline.bold())
                    if let ip = node.ip {
                        Text(ip)
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.themeTextSecondary)
            }
            .padding()
            .background(Color.themeBlack.opacity(0.5))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct NodeDetailView: View {
    let node: GraphNode
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: node.type == "process" ? "cpu" : "globe")
                            .font(.title)
                            .foregroundColor(.themePurple)
                        VStack(alignment: .leading) {
                            Text(node.label)
                                .font(.title.bold())
                            Text(node.type.uppercased())
                                .font(.subheadline)
                                .foregroundColor(.themeTextSecondary)
                        }
                    }
                    .padding()
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        if let pid = node.pid {
                            DetailRow(label: "Process ID", value: "\(pid)")
                        }
                        if let ip = node.ip {
                            DetailRow(label: "IP Address", value: ip)
                        }
                        if let name = node.name {
                            DetailRow(label: "Name", value: name)
                        }
                    }
                    .padding()
                    .background(Color.themeDarkGray)
                    .cornerRadius(12)
                }
                .padding()
            }
            .background(Color.themeBlack)
            .navigationTitle("Node Details")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text("\(label):")
                .font(.subheadline.bold())
                .foregroundColor(.themeTextSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

