import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#endif

struct ReportsView: View {
    @EnvironmentObject var workspace: WorkspaceState
    @State private var reports: [ReportFile] = []
    @State private var selectedReport: ReportFile?
    @State private var searchText: String = ""
    @StateObject private var generator = ScriptRunner()
    
    var body: some View {
        HSplitView {
            // Reports List
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title2)
                    .foregroundColor(Color(red: 0.54, green: 0.16, blue: 0.95))
                VStack(alignment: .leading, spacing: 2) {
                    Text("🛡️ Security Reports")
                        .font(.headline.bold())
                        .foregroundColor(.themeText)
                    Text("Omega Technologies")
                        .font(.caption2)
                        .foregroundColor(Color(red: 0.54, green: 0.16, blue: 0.95))
                }
                    Spacer()
                    Button {
                        generator.run(scriptPath: "MacGuardianSuite/scheduled_reports.sh",
                                      repositoryPath: workspace.repositoryPath) {
                            selectedReport = nil
                            refreshReports()
                        }
                    } label: {
                        if generator.isRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Generate", systemImage: "doc.badge.plus")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.54, green: 0.16, blue: 0.95))
                    .disabled(generator.isRunning)
                    .help("Create a new security report now")
                    Button {
                        refreshReports()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                .tint(Color(red: 0.54, green: 0.16, blue: 0.95))
                }
                .padding()
                
                SearchField(text: $searchText, placeholder: "Search reports...")
                    .padding(.horizontal)
                
                List(selection: $selectedReport) {
                    ForEach(filteredReports) { report in
                        ReportRow(report: report)
                            .tag(report)
                    }
                }
                .listStyle(.sidebar)
                .background(Color.themeDarkGray)
            }
            .frame(minWidth: 250, idealWidth: 300)
            .background(Color.themeDarkGray)
            
            // Report Preview
            if let report = selectedReport {
                ReportPreviewView(report: report)
            } else {
                ContentUnavailableView(
                    "Select a Report",
                    systemImage: "doc.text",
                    description: Text("Choose a report from the list to view it")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.themeBlack)
            }
        }
        .background(Color.themeBlack)
        .onAppear {
            refreshReports()
        }
    }
    
    private var filteredReports: [ReportFile] {
        if searchText.isEmpty {
            return reports
        }
        return reports.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private func refreshReports() {
        reports = workspace.loadReports()
        if selectedReport == nil, let firstReport = reports.first {
            selectedReport = firstReport
        }
    }
}

struct ReportRow: View {
    let report: ReportFile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.name)
                .font(.subheadline.bold())
                .foregroundColor(.themeText)
                .lineLimit(1)
            
            HStack {
                Text(formatDate(report.date))
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
                Spacer()
                Text(report.formattedSize)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ReportPreviewView: View {
    let report: ReportFile
    @State private var htmlContent: String = ""
    @State private var textContent: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Omega Technologies Branding
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    LogoView(size: 60)
                VStack(alignment: .leading, spacing: 4) {
                        Text("🛡️ MacGuardian Security Report")
                            .font(.title2.bold())
                            .foregroundColor(.themeText)
                    Text(report.name)
                            .font(.subheadline)
                            .foregroundColor(.themeTextSecondary)
                    Text(formatDate(report.date))
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("OMEGA TECHNOLOGIES")
                            .font(.caption.bold())
                            .foregroundColor(Color(red: 0.54, green: 0.16, blue: 0.95))
                        Text("Security Intelligence Platform")
                            .font(.caption2)
                            .foregroundColor(.themeTextSecondary)
                    }
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.05, blue: 0.07), Color.themeDarkGray],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                HStack(spacing: 12) {
                    Button {
                        openInFinder()
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.54, green: 0.16, blue: 0.95))
                    
                    #if os(macOS)
                    Button {
                        shareReport()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.54, green: 0.16, blue: 0.95))
                    #endif
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(Color.themeDarkGray)
            }
            
            Divider()
                .background(Color.themePurpleDark)
            
            // Content
            if report.url.pathExtension == "html" {
                WebView(htmlContent: htmlContent)
                    .onAppear {
                        loadHTML()
                    }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Omega Technologies Header for Text Reports
                        HStack(spacing: 16) {
                            LogoView(size: 60)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("🛡️ MacGuardian Security Report")
                                    .font(.title.bold())
                                    .foregroundColor(Color(red: 0.54, green: 0.16, blue: 0.95))
                                Text(report.name)
                                    .font(.headline)
                                    .foregroundColor(.themeText)
                                Text("Generated: \(formatDate(report.date))")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                                Divider()
                                    .background(Color(red: 0.54, green: 0.16, blue: 0.95))
                                Text("OMEGA TECHNOLOGIES")
                                    .font(.caption.bold())
                                    .foregroundColor(Color(red: 0.54, green: 0.16, blue: 0.95))
                                    .tracking(2)
                                Text("Security Intelligence Platform")
                                    .font(.caption2)
                                    .foregroundColor(.themeTextSecondary)
                            }
                        }
                        .padding()
                        .background(Color.themeDarkGray.opacity(0.5))
                        .cornerRadius(8)
                        
                    Text(textContent.isEmpty ? "Loading..." : textContent)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.themeText)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Omega Technologies Footer
                        VStack(spacing: 8) {
                            Divider()
                                .background(Color(red: 0.54, green: 0.16, blue: 0.95))
                            Text("🛡️ MacGuardian Security Suite")
                                .font(.caption.bold())
                                .foregroundColor(.themeTextSecondary)
                            Text("Powered by OMEGA TECHNOLOGIES")
                                .font(.caption2)
                                .foregroundColor(Color(red: 0.54, green: 0.16, blue: 0.95))
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
                .background(Color.themeBlack)
                .onAppear {
                    loadText()
                }
            }
        }
        .background(Color.themeBlack)
    }
    
    private func loadHTML() {
        if let data = try? Data(contentsOf: report.url),
           let content = String(data: data, encoding: .utf8) {
            // Inject Omega Technologies branding if not already present
            htmlContent = injectOmegaBranding(content)
        } else {
            htmlContent = generateOmegaBrandedErrorPage()
        }
    }
    
    private func injectOmegaBranding(_ html: String) -> String {
        // Check if Omega branding already exists
        if html.contains("OMEGA TECHNOLOGIES") || html.contains("Omega Technologies") {
            return html
        }
        
        // Load logo as base64
        let logoBase64 = loadLogoAsBase64()
        
        // Inject Omega branding CSS and header
        let omegaCSS = """
        <style>
            .omega-header {
                background: linear-gradient(135deg, #0D0D12 0%, #1a1a24 100%);
                padding: 30px;
                border-bottom: 3px solid #8A29F0;
                margin-bottom: 30px;
                display: flex;
                align-items: center;
                gap: 20px;
            }
            .omega-logo-img {
                width: 80px;
                height: 80px;
                object-fit: contain;
            }
            .omega-header-content {
                flex: 1;
            }
            .omega-logo {
                color: #8A29F0;
                font-size: 32px;
                font-weight: bold;
                margin-bottom: 10px;
            }
            .omega-title {
                color: #FFFFFF;
                font-size: 28px;
                font-weight: bold;
                margin-bottom: 5px;
            }
            .omega-subtitle {
                color: #8A29F0;
                font-size: 14px;
                letter-spacing: 2px;
                margin-top: 10px;
            }
            .omega-footer {
                background: #0D0D12;
                padding: 20px;
                border-top: 2px solid #8A29F0;
                margin-top: 40px;
                text-align: center;
                color: #888;
                font-size: 12px;
            }
            .omega-footer-logo {
                width: 40px;
                height: 40px;
                margin: 10px auto;
                object-fit: contain;
            }
            body {
                background: #0D0D12;
                color: #E0E0E0;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            }
        </style>
        """
        
        let logoImgTag = logoBase64.isEmpty ? "" : "<img src=\"\(logoBase64)\" alt=\"MacGuardian Logo\" class=\"omega-logo-img\" />"
        
        let omegaHeader = """
        <div class="omega-header">
            \(logoImgTag)
            <div class="omega-header-content">
                <div class="omega-logo">🛡️ MacGuardian Security Report</div>
                <div class="omega-title">\(report.name)</div>
                <div style="color: #888; font-size: 12px; margin-top: 10px;">Generated: \(formatDate(report.date))</div>
                <div class="omega-subtitle">OMEGA TECHNOLOGIES</div>
            </div>
        </div>
        """
        
        let footerLogoTag = logoBase64.isEmpty ? "" : "<img src=\"\(logoBase64)\" alt=\"MacGuardian Logo\" class=\"omega-footer-logo\" />"
        
        let omegaFooter = """
        <div class="omega-footer">
            \(footerLogoTag)
            <div>🛡️ MacGuardian Security Suite</div>
            <div style="margin-top: 5px;">Powered by <strong style="color: #8A29F0;">OMEGA TECHNOLOGIES</strong></div>
            <div style="margin-top: 5px; font-size: 10px;">Security Intelligence Platform</div>
        </div>
        """
        
        // Inject CSS in head, header after body tag, footer before closing body tag
        var modifiedHTML = html
        
        // Add CSS to head
        if let headEndIndex = modifiedHTML.range(of: "</head>", options: .caseInsensitive)?.lowerBound {
            modifiedHTML.insert(contentsOf: omegaCSS, at: headEndIndex)
        } else if let bodyStartIndex = modifiedHTML.range(of: "<body", options: .caseInsensitive)?.lowerBound {
            modifiedHTML.insert(contentsOf: "<head>\(omegaCSS)</head>", at: bodyStartIndex)
        }
        
        // Add header after body tag
        if let bodyTagEndIndex = modifiedHTML.range(of: ">", range: modifiedHTML.range(of: "<body", options: .caseInsensitive))?.upperBound {
            modifiedHTML.insert(contentsOf: omegaHeader, at: bodyTagEndIndex)
        }
        
        // Add footer before closing body tag
        if let bodyEndIndex = modifiedHTML.range(of: "</body>", options: .caseInsensitive)?.lowerBound {
            modifiedHTML.insert(contentsOf: omegaFooter, at: bodyEndIndex)
        }
        
        return modifiedHTML
    }
    
    private func loadLogoAsBase64() -> String {
        #if os(macOS)
        let logoNames = ["MacGuardianLogo", "MacGlogo"]
        let extensions = ["png", "jpg", "jpeg"]
        
        // Try to load from bundle
        for logoName in logoNames {
            for ext in extensions {
                if let imagePath = Bundle.main.path(forResource: logoName, ofType: ext),
                   let image = NSImage(contentsOfFile: imagePath),
                   let tiffData = image.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                    let base64 = pngData.base64EncodedString()
                    return "data:image/png;base64,\(base64)"
                }
            }
        }
        
        // Try alternative paths
        var possiblePaths: [String] = []
        for logoName in logoNames {
            for ext in extensions {
                possiblePaths.append("\(Bundle.main.resourcePath ?? "")/\(logoName).\(ext)")
                possiblePaths.append("\(Bundle.main.resourcePath ?? "")/images/\(logoName).\(ext)")
            }
        }
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               let image = NSImage(contentsOfFile: path),
               let tiffData = image.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                let base64 = pngData.base64EncodedString()
                return "data:image/png;base64,\(base64)"
            }
        }
        #endif
        
        return ""
    }
    
    private func generateOmegaBrandedErrorPage() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {
                    background: #0D0D12;
                    color: #E0E0E0;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    padding: 40px;
                    text-align: center;
                }
                .omega-header {
                    background: linear-gradient(135deg, #0D0D12 0%, #1a1a24 100%);
                    padding: 30px;
                    border-bottom: 3px solid #8A29F0;
                    margin-bottom: 30px;
                }
                .omega-logo {
                    color: #8A29F0;
                    font-size: 32px;
                    font-weight: bold;
                    margin-bottom: 10px;
                }
                .omega-title {
                    color: #FFFFFF;
                    font-size: 28px;
                    font-weight: bold;
                    margin-bottom: 5px;
                }
                .omega-subtitle {
                    color: #8A29F0;
                    font-size: 14px;
                    letter-spacing: 2px;
                    margin-top: 10px;
                }
                .error-message {
                    color: #FF2E63;
                    font-size: 18px;
                    margin-top: 40px;
                }
            </style>
        </head>
        <body>
            <div class="omega-header">
                <div class="omega-logo">🛡️ MacGuardian Security Report</div>
                <div class="omega-title">\(report.name)</div>
                <div class="omega-subtitle">OMEGA TECHNOLOGIES</div>
            </div>
            <div class="error-message">
                ⚠️ Error loading report content
            </div>
            <div style="margin-top: 40px; color: #888;">
                <div>🛡️ MacGuardian Security Suite</div>
                <div style="margin-top: 10px;">Powered by <strong style="color: #8A29F0;">OMEGA TECHNOLOGIES</strong></div>
            </div>
        </body>
        </html>
        """
    }
    
    private func loadText() {
        if let data = try? Data(contentsOf: report.url),
           let content = String(data: data, encoding: .utf8) {
            textContent = content
        } else {
            textContent = "Error loading report"
        }
    }
    
    private func openInFinder() {
        #if os(macOS)
        NSWorkspace.shared.selectFile(report.url.path, inFileViewerRootedAtPath: "")
        #endif
    }
    
    private func shareReport() {
        #if os(macOS)
        let picker = NSSharingServicePicker(items: [report.url])
        if let window = NSApplication.shared.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
        #endif
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct WebView: NSViewRepresentable {
    let htmlContent: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        // Enable Web Inspector for debugging (always enabled for developer access)
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        // Allow right-click context menu for "Inspect Element"
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Ensure developer extras stay enabled
        nsView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        if htmlContent != "" {
            nsView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.themeTextSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(.themeText)
        }
        .padding(8)
        .background(Color.themeBlack, in: RoundedRectangle(cornerRadius: 8))
    }
}

