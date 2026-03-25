import SwiftUI
#if os(macOS)
import AppKit
#endif

struct CacheCleanerView: View {
    @EnvironmentObject var workspace: WorkspaceState
    @State private var selectedBrowsers: Set<String> = ["Safari", "Chrome", "Firefox", "Edge"]
    @State private var cleanCache = true
    @State private var cleanCookies = false
    @State private var cleanHistory = false
    @State private var cleanDownloads = false
    @State private var cleanAutofill = false
    @State private var cleanSystemCache = true
    @State private var cleanHomebrewCache = true
    @State private var isLoading = false
    @State private var showConfirmation = false
    @State private var cleaningResult: CleaningResult?
    @State private var cacheSizes: [String: String] = [:]
    @State private var totalSize: String = "Calculating..."
    @State private var currentCleaningStep: String = ""
    @State private var cleaningProgress: Double = 0.0
    @State private var completedSteps: [String] = []
    
    let availableBrowsers = ["Safari", "Chrome", "Firefox", "Edge"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "trash.fill")
                    .font(.title)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cache Cleaner")
                        .font(.title.bold())
                        .foregroundColor(.themeText)
                    Text("Safely clear browser and system caches to free up disk space")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                
                Button {
                    calculateCacheSizes()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Sizes")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.themePurple)
                .disabled(isLoading)
                
                // Close/Exit Button
                Button {
                    workspace.showCacheCleaner = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.themeTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Close Cache Cleaner")
            }
            .padding()
            .background(Color.themeDarkGray)
            
            Divider()
                .background(Color.themePurpleDark)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Total size estimate
                    if !totalSize.isEmpty && totalSize != "Calculating..." {
                        HStack {
                            Image(systemName: "externaldrive.fill")
                                .foregroundColor(.themePurple)
                            Text("Estimated space to free: \(totalSize)")
                                .font(.headline)
                                .foregroundColor(.themeText)
                            Spacer()
                        }
                        .padding()
                        .background(Color.themePurple.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Browser Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Browsers")
                            .font(.headline)
                            .foregroundColor(.themeText)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                            ForEach(availableBrowsers, id: \.self) { browser in
                                BrowserToggle(
                                    browser: browser,
                                    isSelected: selectedBrowsers.contains(browser),
                                    cacheSize: cacheSizes[browser] ?? "Unknown",
                                    onToggle: {
                                        if selectedBrowsers.contains(browser) {
                                            selectedBrowsers.remove(browser)
                                        } else {
                                            selectedBrowsers.insert(browser)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color.themeDarkGray.opacity(0.5))
                    .cornerRadius(12)
                    
                    // Browser Data Options
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What to Clean")
                            .font(.headline)
                            .foregroundColor(.themeText)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            CleanOptionToggle(
                                title: "Cache",
                                description: "Temporary files and cached data",
                                icon: "externaldrive.fill",
                                isOn: $cleanCache
                            )
                            
                            CleanOptionToggle(
                                title: "Cookies",
                                description: "Website cookies and login sessions",
                                icon: "lock.fill",
                                isOn: $cleanCookies
                            )
                            
                            CleanOptionToggle(
                                title: "History",
                                description: "Browsing history",
                                icon: "clock.fill",
                                isOn: $cleanHistory
                            )
                            
                            CleanOptionToggle(
                                title: "Download History",
                                description: "List of downloaded files",
                                icon: "arrow.down.circle.fill",
                                isOn: $cleanDownloads
                            )
                            
                            CleanOptionToggle(
                                title: "Autofill Data",
                                description: "Saved form data and passwords",
                                icon: "key.fill",
                                isOn: $cleanAutofill
                            )
                        }
                    }
                    .padding()
                    .background(Color.themeDarkGray.opacity(0.5))
                    .cornerRadius(12)
                    
                    // System Cache Options
                    VStack(alignment: .leading, spacing: 16) {
                        Text("System Cache")
                            .font(.headline)
                            .foregroundColor(.themeText)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            CleanOptionToggle(
                                title: "System Cache",
                                description: "macOS system cache files (~/Library/Caches)",
                                icon: "gear.circle.fill",
                                isOn: $cleanSystemCache
                            )
                            
                            CleanOptionToggle(
                                title: "Homebrew Cache",
                                description: "Homebrew package cache (if installed)",
                                icon: "cup.and.saucer.fill",
                                isOn: $cleanHomebrewCache
                            )
                        }
                    }
                    .padding()
                    .background(Color.themeDarkGray.opacity(0.5))
                    .cornerRadius(12)
                    
                    // Safety Warning
                    if cleanCookies || cleanHistory || cleanAutofill {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("⚠️ Data Loss Warning")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.orange)
                                Text("Clearing cookies, history, or autofill data will log you out of websites and remove saved information. Make sure you have backups if needed.")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            
            Divider()
                .background(Color.themePurpleDark)
            
            // Action buttons
            HStack(spacing: 12) {
                Button {
                    // Preview what will be cleaned
                    showConfirmation = true
                } label: {
                    Label("Preview Clean", systemImage: "eye.fill")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .tint(.themePurple)
                .disabled(selectedBrowsers.isEmpty && !cleanSystemCache && !cleanHomebrewCache)
                
                Spacer()
                
                Button {
                    performClean()
                } label: {
                    Label("Clean Now", systemImage: "trash.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isLoading || (selectedBrowsers.isEmpty && !cleanSystemCache && !cleanHomebrewCache))
            }
            .padding()
            .background(Color.themeDarkGray)
        }
        .background(Color.themeBlack)
        .overlay {
            // Progress overlay
            if isLoading {
                CleaningProgressOverlay(
                    currentStep: currentCleaningStep,
                    progress: cleaningProgress,
                    completedSteps: completedSteps
                )
            }
        }
        .onAppear {
            calculateCacheSizes()
        }
        .alert("Clean Cache", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Preview", role: .none) {
                previewClean()
            }
        } message: {
            Text("This will clean selected caches. You can preview what will be cleaned first, or proceed directly.")
        }
        .alert("Cleaning Result", isPresented: .constant(cleaningResult != nil), presenting: cleaningResult) { result in
            Button("OK") {
                cleaningResult = nil
                calculateCacheSizes()
            }
        } message: { result in
            Text(result.message)
        }
    }
    
    private func calculateCacheSizes() {
        isLoading = true
        currentCleaningStep = "Calculating cache sizes..."
        cleaningProgress = 0.0
        
        DispatchQueue.global(qos: .userInitiated).async {
            var sizes: [String: String] = [:]
            var totalBytes: Int64 = 0
            let totalChecks = availableBrowsers.count + (cleanSystemCache ? 1 : 0) + (cleanHomebrewCache ? 1 : 0)
            var currentCheck = 0
            
            // Calculate browser cache sizes for all browsers (to show sizes even if not selected)
            for browser in availableBrowsers {
                currentCheck += 1
                DispatchQueue.main.async {
                    currentCleaningStep = "Scanning \(browser)..."
                    cleaningProgress = Double(currentCheck) / Double(totalChecks)
                }
                
                let size = getBrowserCacheSize(browser: browser)
                sizes[browser] = size.formatted
                // Only add to total if selected
                if selectedBrowsers.contains(browser) {
                    totalBytes += size.bytes
                }
            }
            
            // Calculate system cache size
            if cleanSystemCache {
                currentCheck += 1
                DispatchQueue.main.async {
                    currentCleaningStep = "Scanning system cache..."
                    cleaningProgress = Double(currentCheck) / Double(totalChecks)
                }
                
                let systemSize = getSystemCacheSize()
                sizes["System"] = systemSize.formatted
                totalBytes += systemSize.bytes
            }
            
            // Calculate Homebrew cache size
            if cleanHomebrewCache {
                currentCheck += 1
                DispatchQueue.main.async {
                    currentCleaningStep = "Scanning Homebrew cache..."
                    cleaningProgress = Double(currentCheck) / Double(totalChecks)
                }
                
                let brewSize = getHomebrewCacheSize()
                sizes["Homebrew"] = brewSize.formatted
                totalBytes += brewSize.bytes
            }
            
            DispatchQueue.main.async {
                cacheSizes = sizes
                totalSize = formatBytes(totalBytes)
                isLoading = false
                currentCleaningStep = ""
                cleaningProgress = 0.0
            }
        }
    }
    
    private func previewClean() {
        // Run browser_cleanup.sh with --dry-run
        let browsers = selectedBrowsers.joined(separator: ",").lowercased()
        var args: [String] = ["--dry-run"]
        
        if cleanCache && !cleanCookies && !cleanHistory && !cleanDownloads && !cleanAutofill {
            args.append("--cache-only")
        } else {
            if cleanCookies { args.append("--cookies") }
            if cleanHistory { args.append("--history") }
            if cleanDownloads { args.append("--downloads") }
            if cleanAutofill { args.append("--autofill") }
            if cleanCache && cleanCookies && cleanHistory && cleanDownloads && cleanAutofill {
                args.append("--all")
            }
        }
        
        if !browsers.isEmpty {
            args.append("--browsers")
            args.append(browsers)
        }
        
        let _ = runBrowserCleanup(args: args, isPreview: true)
    }
    
    private func performClean() {
        isLoading = true
        cleaningProgress = 0.0
        completedSteps = []
        currentCleaningStep = "Initializing..."
        
        // Calculate total steps
        var totalSteps = 0
        if !selectedBrowsers.isEmpty { totalSteps += 1 }
        if cleanSystemCache { totalSteps += 1 }
        if cleanHomebrewCache { totalSteps += 1 }
        
        guard totalSteps > 0 else {
            isLoading = false
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [String] = []
            var errors: [String] = []
            var currentStep = 0
            
            // Clean browsers
            if !selectedBrowsers.isEmpty {
                currentStep += 1
                DispatchQueue.main.async {
                    currentCleaningStep = "Cleaning browser caches..."
                    cleaningProgress = Double(currentStep) / Double(totalSteps)
                }
                
                let browsers = selectedBrowsers.joined(separator: ",").lowercased()
                var args: [String] = []
                
                if cleanCache && !cleanCookies && !cleanHistory && !cleanDownloads && !cleanAutofill {
                    args.append("--cache-only")
                } else {
                    if cleanCache { args.append("--cache-only") }
                    if cleanCookies { args.append("--cookies") }
                    if cleanHistory { args.append("--history") }
                    if cleanDownloads { args.append("--downloads") }
                    if cleanAutofill { args.append("--autofill") }
                    if cleanCache && cleanCookies && cleanHistory && cleanDownloads && cleanAutofill {
                        args = ["--all"]
                    }
                }
                
                if !browsers.isEmpty {
                    args.append("--browsers")
                    args.append(browsers)
                }
                
                let browserResult = runBrowserCleanup(args: args, isPreview: false)
                if browserResult.success {
                    results.append("Browser caches cleaned")
                    DispatchQueue.main.async {
                        completedSteps.append("Browser caches cleaned")
                    }
                } else {
                    errors.append(browserResult.message)
                }
            }
            
            // Clean system cache
            if cleanSystemCache {
                currentStep += 1
                DispatchQueue.main.async {
                    currentCleaningStep = "Cleaning system cache..."
                    cleaningProgress = Double(currentStep) / Double(totalSteps)
                }
                
                let systemResult = cleanSystemCaches()
                if systemResult.success {
                    results.append("System cache cleaned")
                    DispatchQueue.main.async {
                        completedSteps.append("System cache cleaned")
                    }
                } else {
                    errors.append(systemResult.message)
                }
            }
            
            // Clean Homebrew cache
            if cleanHomebrewCache {
                currentStep += 1
                DispatchQueue.main.async {
                    currentCleaningStep = "Cleaning Homebrew cache..."
                    cleaningProgress = Double(currentStep) / Double(totalSteps)
                }
                
                let brewResult = performHomebrewCleanup()
                if brewResult.success {
                    results.append("Homebrew cache cleaned")
                    DispatchQueue.main.async {
                        completedSteps.append("Homebrew cache cleaned")
                    }
                } else if brewResult.message == "Homebrew not installed" {
                    // Homebrew not installed is not an error, just informational
                    results.append("Homebrew: Not installed (skipped)")
                    DispatchQueue.main.async {
                        completedSteps.append("Homebrew: Not installed (skipped)")
                    }
                } else {
                    errors.append("Homebrew: \(brewResult.message)")
                }
            }
            
            DispatchQueue.main.async {
                currentCleaningStep = "Finishing up..."
                cleaningProgress = 1.0
                
                // Small delay to show completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isLoading = false
                    let message: String
                    if errors.isEmpty {
                        message = "✅ Successfully cleaned:\n\n" + results.joined(separator: "\n")
                    } else {
                        message = "⚠️ Partial success:\n\n" + results.joined(separator: "\n") + "\n\nErrors:\n" + errors.joined(separator: "\n")
                    }
                    cleaningResult = CleaningResult(success: errors.isEmpty, message: message)
                    currentCleaningStep = ""
                    cleaningProgress = 0.0
                    completedSteps = []
                }
            }
        }
    }
}

struct BrowserToggle: View {
    let browser: String
    let isSelected: Bool
    let cacheSize: String
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 8) {
                Image(systemName: browserIcon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .themeTextSecondary)
                Text(browser)
                    .font(.subheadline.bold())
                    .foregroundColor(isSelected ? .white : .themeText)
                Text(cacheSize)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .themeTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.themePurple : Color.themeDarkGray.opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.themePurple : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var browserIcon: String {
        switch browser {
        case "Safari": return "safari.fill"
        case "Chrome": return "globe"
        case "Firefox": return "flame.fill"
        case "Edge": return "e.circle.fill"
        default: return "globe"
        }
    }
}

struct CleanOptionToggle: View {
    let title: String
    let description: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.themePurple)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.themeText)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}

struct CleaningResult: Identifiable {
    let id = UUID()
    let success: Bool
    let message: String
}

// MARK: - Cache Size Calculation

struct CacheSize {
    let bytes: Int64
    let formatted: String
}

func getBrowserCacheSize(browser: String) -> CacheSize {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    var totalBytes: Int64 = 0
    
    switch browser {
    case "Safari":
        let cacheDirs = [
            "\(homeDir)/Library/Caches/com.apple.Safari",
            "\(homeDir)/Library/Caches/com.apple.WebKit.Networking",
            "\(homeDir)/Library/Caches/com.apple.WebKit.WebContent"
        ]
        for dir in cacheDirs {
            totalBytes += getDirectorySize(dir)
        }
    case "Chrome":
        totalBytes += getDirectorySize("\(homeDir)/Library/Caches/Google/Chrome")
    case "Firefox":
        totalBytes += getDirectorySize("\(homeDir)/Library/Caches/Firefox")
    case "Edge":
        totalBytes += getDirectorySize("\(homeDir)/Library/Caches/Microsoft Edge")
    default:
        break
    }
    
    return CacheSize(bytes: totalBytes, formatted: formatBytes(totalBytes))
}

func getSystemCacheSize() -> CacheSize {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let cacheDir = "\(homeDir)/Library/Caches"
    let bytes = getDirectorySize(cacheDir)
    return CacheSize(bytes: bytes, formatted: formatBytes(bytes))
}

func getHomebrewCacheSize() -> CacheSize {
    // Homebrew's download cache lives in ~/Library/Caches/Homebrew on all architectures
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let cacheDir = "\(homeDir)/Library/Caches/Homebrew"
    let bytes = getDirectorySize(cacheDir)
    return CacheSize(bytes: bytes, formatted: formatBytes(bytes))
}

func getDirectorySize(_ path: String) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(atPath: path) else {
        return 0
    }
    
    var totalSize: Int64 = 0
    for file in enumerator {
        if let filePath = file as? String {
            let fullPath = (path as NSString).appendingPathComponent(filePath)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath),
               let size = attributes[.size] as? Int64 {
                totalSize += size
            }
        }
    }
    return totalSize
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    return formatter.string(fromByteCount: bytes)
}

// MARK: - Cache Cleaning Functions

#if os(macOS)
func runBrowserCleanup(args: [String], isPreview: Bool) -> (success: Bool, message: String) {
    let scriptPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop")
        .appendingPathComponent("MacGuardianProject")
        .appendingPathComponent("MacGuardianSuite")
        .appendingPathComponent("browser_cleanup.sh")
        .path
    
    guard FileManager.default.fileExists(atPath: scriptPath) else {
        return (false, "Browser cleanup script not found")
    }
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", "cd '\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/MacGuardianProject/MacGuardianSuite' && bash '\(scriptPath)' \(args.joined(separator: " "))"]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    
    do {
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if process.terminationStatus == 0 {
            return (true, isPreview ? "Preview: \(output)" : "Cleaned successfully")
        } else {
            return (false, "Error: \(output)")
        }
    } catch {
        return (false, "Failed to run: \(error.localizedDescription)")
    }
}

func cleanSystemCaches() -> (success: Bool, message: String) {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let cacheDir = "\(homeDir)/Library/Caches"
    
    // Clean old cache files (older than 30 days)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
    process.arguments = [cacheDir, "-type", "f", "-mtime", "+30", "-delete"]
    
    do {
        try process.run()
        process.waitUntilExit()
        return (true, "System cache cleaned")
    } catch {
        return (false, "Failed to clean system cache: \(error.localizedDescription)")
    }
}

func performHomebrewCleanup() -> (success: Bool, message: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["brew"]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    
    do {
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            // Homebrew is installed, clean it
            let brewProcess = Process()
            brewProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
            if !FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
                brewProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")
            }
            brewProcess.arguments = ["cleanup"]
            
            try brewProcess.run()
            brewProcess.waitUntilExit()
            return (true, "Homebrew cache cleaned")
        } else {
            return (false, "Homebrew not installed")
        }
    } catch {
        return (false, "Failed to clean Homebrew cache: \(error.localizedDescription)")
    }
}
#endif

// MARK: - Cleaning Progress Overlay
struct CleaningProgressOverlay: View {
    let currentStep: String
    let progress: Double
    let completedSteps: [String]
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .blur(radius: 2)
            
            // Progress card
            VStack(spacing: 24) {
                // Animated icon
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.themePurple.opacity(0.3), .themePurpleLight.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "trash.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.themePurple, .themePurpleLight],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolEffect(.pulse, options: .repeating)
                }
                
                // Title
                Text("Cleaning Cache")
                    .font(.title.bold())
                    .foregroundColor(.themeText)
                
                // Current step
                if !currentStep.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .tint(.themePurple)
                        
                        Text(currentStep)
                            .font(.headline)
                            .foregroundColor(.themeText)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.themeDarkGray.opacity(0.8))
                    )
                }
                
                // Progress bar
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Progress")
                            .font(.subheadline)
                            .foregroundColor(.themeTextSecondary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.subheadline.bold())
                            .foregroundColor(.themePurple)
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.themeDarkGray.opacity(0.5))
                                .frame(height: 12)
                            
                            // Progress fill
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [.themePurple, .themePurpleLight],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress, height: 12)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress)
                        }
                    }
                    .frame(height: 12)
                }
                .padding(.horizontal, 24)
                
                // Completed steps list
                if !completedSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Completed:")
                            .font(.caption.bold())
                            .foregroundColor(.themeTextSecondary)
                            .textCase(.uppercase)
                        
                        ForEach(completedSteps, id: \.self) { step in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text(step)
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.themeDarkGray.opacity(0.5))
                    )
                }
                
                // Info text
                Text("Please wait while we clean your caches...")
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary.opacity(0.7))
            }
            .padding(32)
            .frame(maxWidth: 500)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.themeDarkGray)
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.themePurple.opacity(0.5), .themePurpleDark.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
        }
    }
}

