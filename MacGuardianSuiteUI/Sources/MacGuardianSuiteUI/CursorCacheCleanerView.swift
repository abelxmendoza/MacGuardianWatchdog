import SwiftUI
#if os(macOS)
import AppKit
#endif

struct CursorCacheCleanerView: View {
    @EnvironmentObject var workspace: WorkspaceState
    @State private var cursorProjects: [CursorProject] = []
    @State private var globalCacheSize: CacheSize = CacheSize(bytes: 0, formatted: "0 B")
    @State private var selectedProjects: Set<String> = []
    @State private var cleanGlobalCache = false
    @State private var cleanProjectCache = true
    @State private var cleanNodeModules = false
    @State private var reinstallNodeModules = false
    @State private var isLoading = false
    @State private var showConfirmation = false
    @State private var cleaningResult: CleaningResult?
    @State private var totalSize: String = "Calculating..."
    @State private var manualPath: String = ""
    @State private var showManualPathInput = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cursorarrow.click")
                    .font(.title)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cursor Cache Cleaner")
                        .font(.title.bold())
                        .foregroundColor(.themeText)
                    Text("Clear Cursor editor cache for projects and global settings")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                
                Button {
                    scanCursorProjects()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan Projects")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.themePurple)
                .disabled(isLoading)
                
                // Close/Exit Button
                Button {
                    workspace.showCursorCacheCleaner = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.themeTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Close Cursor Cache Cleaner")
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
                                .foregroundColor(.blue)
                            Text("Estimated space to free: \(totalSize)")
                                .font(.headline)
                                .foregroundColor(.themeText)
                            Spacer()
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Global Cache Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Global Cursor Cache")
                                .font(.headline)
                                .foregroundColor(.themeText)
                            Spacer()
                            Text(globalCacheSize.formatted)
                                .font(.subheadline.bold())
                                .foregroundColor(.themePurple)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cursor Application Cache")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.themeText)
                                Text("Global cache files, extensions cache, and application data")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $cleanGlobalCache)
                                .toggleStyle(.switch)
                        }
                        .padding()
                        .background(Color.themeDarkGray.opacity(0.5))
                        .cornerRadius(8)
                    }
                    .padding()
                    .background(Color.themeDarkGray.opacity(0.3))
                    .cornerRadius(12)
                    
                    // Node Modules Options
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Node Modules")
                            .font(.headline)
                            .foregroundColor(.themeText)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            CleanOptionToggle(
                                title: "Remove node_modules",
                                description: "Delete node_modules folders to free space and fix dependency issues",
                                icon: "folder.badge.minus",
                                isOn: $cleanNodeModules
                            )
                            
                            if cleanNodeModules {
                                CleanOptionToggle(
                                    title: "Reinstall after cleanup",
                                    description: "Automatically run npm/yarn/pnpm install after removing node_modules",
                                    icon: "arrow.clockwise.circle.fill",
                                    isOn: $reinstallNodeModules
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color.themeDarkGray.opacity(0.3))
                    .cornerRadius(12)
                    
                    // Projects Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Cursor Projects")
                                .font(.headline)
                                .foregroundColor(.themeText)
                            Spacer()
                            if !cursorProjects.isEmpty {
                                Text("\(cursorProjects.count) project(s) found")
                                    .font(.subheadline)
                                    .foregroundColor(.themeTextSecondary)
                            }
                        }
                        
                        if cursorProjects.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "folder.badge.questionmark")
                                    .font(.system(size: 50))
                                    .foregroundColor(.themeTextSecondary)
                                Text("No Cursor projects found")
                                    .font(.headline)
                                    .foregroundColor(.themeText)
                                Text("Click 'Scan Projects' to search for projects with Cursor cache, or add a project manually")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                                    .multilineTextAlignment(.center)
                                
                                // Manual path input
                                VStack(spacing: 8) {
                                    HStack {
                                        TextField("Enter project path manually", text: $manualPath)
                                            .textFieldStyle(.roundedBorder)
                                        Button("Add") {
                                            addManualProject()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.blue)
                                        .disabled(manualPath.isEmpty)
                                    }
                                    Text("Example: /Users/yourname/Documents/MyProject")
                                        .font(.caption2)
                                        .foregroundColor(.themeTextSecondary)
                                }
                                .padding()
                                .background(Color.themeDarkGray.opacity(0.5))
                                .cornerRadius(8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(40)
                        } else {
                            VStack(spacing: 8) {
                                // Select All / Deselect All
                                HStack {
                                    Button("Select All") {
                                        selectedProjects = Set(cursorProjects.map { $0.id })
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                    
                                    Button("Deselect All") {
                                        selectedProjects.removeAll()
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                    
                                    Spacer()
                                    
                                    Toggle("Clean Project Cache", isOn: $cleanProjectCache)
                                        .toggleStyle(.switch)
                                        .font(.caption)
                                }
                                
                                ForEach(cursorProjects) { project in
                                    ProjectRow(
                                        project: project,
                                        isSelected: selectedProjects.contains(project.id),
                                        cleanCache: cleanProjectCache,
                                        onToggle: {
                                            if selectedProjects.contains(project.id) {
                                                selectedProjects.remove(project.id)
                                            } else {
                                                selectedProjects.insert(project.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.themeDarkGray.opacity(0.3))
                    .cornerRadius(12)
                    
                    // Safety Warning
                    if cleanGlobalCache || cleanProjectCache {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ℹ️ Cache Clearing Info")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.blue)
                                Text("Clearing Cursor cache will remove temporary files, indexes, and cached data. Your code and settings will not be affected. Cursor will rebuild cache on next use.")
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                            }
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
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
                    showConfirmation = true
                } label: {
                    Label("Preview Clean", systemImage: "eye.fill")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .tint(.themePurple)
                .disabled((!cleanGlobalCache && selectedProjects.isEmpty && !cleanNodeModules) || isLoading)
                
                Spacer()
                
                Button {
                    performClean()
                } label: {
                    Label("Clean Now", systemImage: "trash.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isLoading || (!cleanGlobalCache && selectedProjects.isEmpty && !cleanNodeModules))
            }
            .padding()
            .background(Color.themeDarkGray)
        }
        .background(Color.themeBlack)
        .onAppear {
            scanCursorProjects()
        }
        .alert("Clean Cursor Cache", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Preview", role: .none) {
                previewClean()
            }
        } message: {
            Text("This will clean selected Cursor caches. You can preview what will be cleaned first, or proceed directly.")
        }
        .alert("Cleaning Result", isPresented: .constant(cleaningResult != nil), presenting: cleaningResult) { result in
            Button("OK") {
                cleaningResult = nil
                scanCursorProjects()
            }
        } message: { result in
            Text(result.message)
        }
    }
    
    private func scanCursorProjects() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var projects = findCursorProjects()
            let globalSize = getCursorGlobalCacheSize()
            
            // Also check for projects in current workspace path if set
            if !workspace.repositoryPath.isEmpty {
                let repoPath = workspace.repositoryPath
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: repoPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                    let cacheSize = getCursorProjectCacheSize(projectPath: repoPath)
                    if cacheSize.bytes > 0 {
                        let projectName = (repoPath as NSString).lastPathComponent
                        let project = CursorProject(
                            id: repoPath,
                            name: projectName + " (Current Workspace)",
                            path: repoPath,
                            cacheSize: cacheSize
                        )
                        if !projects.contains(where: { $0.id == repoPath }) {
                            projects.append(project)
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                cursorProjects = projects
                globalCacheSize = globalSize
                calculateTotalSize()
                isLoading = false
            }
        }
    }
    
    private func addManualProject() {
        let path = manualPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }
        
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue {
            let cacheSize = getCursorProjectCacheSize(projectPath: path)
            let projectName = (path as NSString).lastPathComponent
            let project = CursorProject(
                id: path,
                name: projectName + " (Manual)",
                path: path,
                cacheSize: cacheSize
            )
            
            if !cursorProjects.contains(where: { $0.id == path }) {
                cursorProjects.append(project)
                selectedProjects.insert(path)
                manualPath = ""
                calculateTotalSize()
            }
        } else {
            cleaningResult = CleaningResult(
                success: false,
                message: "Path not found or is not a directory: \(path)"
            )
        }
    }
    
    private func calculateTotalSize() {
        var totalBytes: Int64 = 0
        
        if cleanGlobalCache {
            totalBytes += globalCacheSize.bytes
        }
        
        if cleanProjectCache {
            for project in cursorProjects where selectedProjects.contains(project.id) {
                totalBytes += project.cacheSize.bytes
            }
        }
        
        if cleanNodeModules {
            for project in cursorProjects where selectedProjects.contains(project.id) {
                let nodeModulesPath = (project.path as NSString).appendingPathComponent("node_modules")
                totalBytes += getDirectorySize(nodeModulesPath)
            }
        }
        
        totalSize = formatBytes(totalBytes)
    }
    
    private func previewClean() {
        // Show what will be cleaned
        var items: [String] = []
        
        if cleanGlobalCache {
            items.append("Global Cursor cache (\(globalCacheSize.formatted))")
        }
        
        if cleanProjectCache {
            for project in cursorProjects where selectedProjects.contains(project.id) {
                items.append("\(project.name) cache (\(project.cacheSize.formatted))")
            }
        }
        
        if cleanNodeModules {
            for project in cursorProjects where selectedProjects.contains(project.id) {
                let nodeModulesPath = (project.path as NSString).appendingPathComponent("node_modules")
                let size = getDirectorySize(nodeModulesPath)
                if size > 0 {
                    let sizeStr = formatBytes(size)
                    let reinstallStr = reinstallNodeModules ? " (will reinstall)" : ""
                    items.append("\(project.name) node_modules (\(sizeStr))\(reinstallStr)")
                }
            }
        }
        
        if items.isEmpty {
            cleaningResult = CleaningResult(success: false, message: "Nothing selected to clean")
        } else {
            let message = "Will clean:\n\n" + items.joined(separator: "\n")
            cleaningResult = CleaningResult(success: true, message: message)
        }
    }
    
    private func performClean() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [String] = []
            var errors: [String] = []
            
            // Clean global cache
            if cleanGlobalCache {
                let result = cleanCursorGlobalCache()
                if result.success {
                    results.append("Global cache cleaned")
                } else {
                    errors.append(result.message)
                }
            }
            
            // Clean project caches
            if cleanProjectCache {
                for project in cursorProjects where selectedProjects.contains(project.id) {
                    let result = cleanCursorProjectCache(project: project)
                    if result.success {
                        results.append("\(project.name) cache cleaned")
                    } else {
                        // Don't add error if cache just doesn't exist - that's okay
                        if !result.message.contains("not found") {
                            errors.append("\(project.name): \(result.message)")
                        }
                    }
                }
            }
            
            // Clean node_modules
            if cleanNodeModules {
                for project in cursorProjects where selectedProjects.contains(project.id) {
                    let result = cleanNodeModulesForProject(project: project, reinstall: reinstallNodeModules)
                    if result.success {
                        results.append("\(project.name): \(result.message)")
                    } else {
                        errors.append("\(project.name): \(result.message)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                isLoading = false
                let message: String
                if errors.isEmpty {
                    message = "✅ Successfully cleaned:\n\n" + results.joined(separator: "\n")
                } else {
                    message = "⚠️ Partial success:\n\n" + results.joined(separator: "\n") + "\n\nErrors:\n" + errors.joined(separator: "\n")
                }
                cleaningResult = CleaningResult(success: errors.isEmpty, message: message)
                // Rescan to update sizes
                scanCursorProjects()
            }
        }
    }
}

struct CursorProject: Identifiable {
    let id: String
    let name: String
    let path: String
    let cacheSize: CacheSize
}

struct ProjectRow: View {
    let project: CursorProject
    let isSelected: Bool
    let cleanCache: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .themeTextSecondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.themeText)
                Text(project.path)
                    .font(.caption)
                    .foregroundColor(.themeTextSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(project.cacheSize.formatted)
                .font(.subheadline.bold())
                .foregroundColor(.themePurple)
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.2) : Color.themeDarkGray.opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Cursor Cache Detection and Cleaning

#if os(macOS)
func findCursorProjects() -> [CursorProject] {
    var projects: [CursorProject] = []
    var foundPaths = Set<String>() // Track found paths to avoid duplicates
    let fileManager = FileManager.default
    let homeDir = fileManager.homeDirectoryForCurrentUser.path
    
    // First, try to get open Cursor windows/projects
    if let openProjects = getOpenCursorProjects() {
        for projectPath in openProjects {
            if !foundPaths.contains(projectPath) && fileManager.fileExists(atPath: projectPath) {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: projectPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                    let projectName = (projectPath as NSString).lastPathComponent
                    let cacheSize = getCursorProjectCacheSize(projectPath: projectPath)
                    
                    projects.append(CursorProject(
                        id: projectPath,
                        name: projectName + " (Open)",
                        path: projectPath,
                        cacheSize: cacheSize
                    ))
                    foundPaths.insert(projectPath)
                }
            }
        }
    }
    
    // Common project locations - search deeper
    let searchPaths = [
        "\(homeDir)/Desktop",
        "\(homeDir)/Documents",
        "\(homeDir)/Projects",
        "\(homeDir)/Code",
        "\(homeDir)/Developer",
        "\(homeDir)/workspace",
        "\(homeDir)/workspaces",
        "\(homeDir)/workspace",
        "\(homeDir)/src",
        "\(homeDir)/repos",
        "\(homeDir)/repositories"
    ]
    
    for searchPath in searchPaths {
        guard fileManager.fileExists(atPath: searchPath) else {
            continue
        }
        
        // Search up to 3 levels deep
        if let enumerator = fileManager.enumerator(atPath: searchPath) {
            for case let path as String in enumerator {
                let fullPath = (searchPath as NSString).appendingPathComponent(path)
                
                // Limit depth to avoid scanning too deep
                let pathComponents = path.components(separatedBy: "/")
                if pathComponents.count > 3 {
                    enumerator.skipDescendants()
                    continue
                }
                
                // Check for .cursor directory OR package.json (Node.js project)
                let cursorDir = (fullPath as NSString).appendingPathComponent(".cursor")
                let packageJson = (fullPath as NSString).appendingPathComponent("package.json")
                let hasCursorCache = fileManager.fileExists(atPath: cursorDir)
                let hasPackageJson = fileManager.fileExists(atPath: packageJson)
                
                if (hasCursorCache || hasPackageJson) && fileManager.fileExists(atPath: fullPath) {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                        // Avoid duplicates
                        if !foundPaths.contains(fullPath) {
                            let projectName = (path as NSString).lastPathComponent
                            let cacheSize = getCursorProjectCacheSize(projectPath: fullPath)
                            
                            // Only add if it has cache or node_modules
                            if cacheSize.bytes > 0 || hasPackageJson {
                                projects.append(CursorProject(
                                    id: fullPath,
                                    name: projectName,
                                    path: fullPath,
                                    cacheSize: cacheSize
                                ))
                                foundPaths.insert(fullPath)
                                
                                // Skip descendants since we found a project here
                                enumerator.skipDescendants()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Also check for projects in common workspace locations
    let workspacePaths = [
        "\(homeDir)/Library/Application Support/Cursor/User/workspaceStorage",
        "\(homeDir)/Library/Application Support/Cursor/User/History"
    ]
    
    for workspacePath in workspacePaths {
        if let workspaceProjects = findProjectsInWorkspaceStorage(path: workspacePath) {
            for projectPath in workspaceProjects {
                if !foundPaths.contains(projectPath) && fileManager.fileExists(atPath: projectPath) {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: projectPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                        let projectName = (projectPath as NSString).lastPathComponent
                        let cacheSize = getCursorProjectCacheSize(projectPath: projectPath)
                        
                        projects.append(CursorProject(
                            id: projectPath,
                            name: projectName + " (Recent)",
                            path: projectPath,
                            cacheSize: cacheSize
                        ))
                        foundPaths.insert(projectPath)
                    }
                }
            }
        }
    }
    
    return projects.sorted { $0.name < $1.name }
}

// Get open Cursor projects by checking running Cursor instances
func getOpenCursorProjects() -> [String]? {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications
    
    // Find Cursor app
    guard runningApps.contains(where: { app in
        app.bundleIdentifier?.contains("cursor") == true || 
        app.localizedName?.lowercased().contains("cursor") == true
    }) else {
        return nil
    }
    
    // Try to get open windows/documents from Cursor
    // Note: This is limited by macOS sandboxing, but we can try
    var openProjects: [String] = []
    
    // Method 1: Check recent files in Cursor's workspace storage
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let workspaceStorage = "\(homeDir)/Library/Application Support/Cursor/User/workspaceStorage"
    
    if let recentProjects = getRecentCursorProjects(from: workspaceStorage) {
        openProjects.append(contentsOf: recentProjects)
    }
    
    // Method 2: Check if we can access Cursor's open documents via AppleScript
    if let scriptProjects = getCursorProjectsViaScript() {
        openProjects.append(contentsOf: scriptProjects)
    }
    
    return openProjects.isEmpty ? nil : Array(Set(openProjects)) // Remove duplicates
}

// Get recent projects from Cursor's workspace storage
func getRecentCursorProjects(from storagePath: String) -> [String]? {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: storagePath) else {
        return nil
    }
    
    var projects: [String] = []
    
    // Cursor stores workspace info in JSON files
    if let contents = try? fileManager.contentsOfDirectory(atPath: storagePath) {
        for item in contents.prefix(20) { // Limit to recent 20
            let itemPath = (storagePath as NSString).appendingPathComponent(item)
            let workspaceFile = (itemPath as NSString).appendingPathComponent("workspace.json")
            
            if fileManager.fileExists(atPath: workspaceFile),
               let data = try? Data(contentsOf: URL(fileURLWithPath: workspaceFile)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let folder = json["folder"] as? String {
                // Decode URI format (file://...)
                if folder.hasPrefix("file://") {
                    let decoded = folder.replacingOccurrences(of: "file://", with: "")
                    let projectPath = decoded.removingPercentEncoding ?? decoded
                    if fileManager.fileExists(atPath: projectPath) {
                        projects.append(projectPath)
                    }
                }
            }
        }
    }
    
    return projects.isEmpty ? nil : projects
}

// Try to get open projects via AppleScript
func getCursorProjectsViaScript() -> [String]? {
    // AppleScript to get open projects (currently unused due to macOS sandboxing limitations)
    _ = """
    tell application "System Events"
        tell process "Cursor"
            try
                set windowList to windows
                set projectPaths to {}
                repeat with aWindow in windowList
                    try
                        set windowTitle to title of aWindow
                        -- Try to extract path from window title or other means
                        -- This is limited but worth trying
                    end try
                end repeat
                return projectPaths
            on error
                return {}
            end try
        end tell
    end tell
    """
    
    // For now, return nil as AppleScript access is limited
    // We'll rely on workspace storage method
    return nil
}

// Find projects referenced in Cursor's workspace storage
func findProjectsInWorkspaceStorage(path: String) -> [String]? {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: path) else {
        return nil
    }
    
    var projects: [String] = []
    
    if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
        for item in contents {
            let itemPath = (path as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            
            if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                // Check for workspace.json
                let workspaceFile = (itemPath as NSString).appendingPathComponent("workspace.json")
                if fileManager.fileExists(atPath: workspaceFile) {
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: workspaceFile)),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Try to extract folder path
                        if let folder = json["folder"] as? String {
                            let decoded = folder.replacingOccurrences(of: "file://", with: "")
                            let projectPath = decoded.removingPercentEncoding ?? decoded
                            if fileManager.fileExists(atPath: projectPath) {
                                projects.append(projectPath)
                            }
                        }
                    }
                }
            }
        }
    }
    
    return projects.isEmpty ? nil : projects
}

func getCursorGlobalCacheSize() -> CacheSize {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    var totalBytes: Int64 = 0
    
    // Cursor cache locations
    let cachePaths = [
        "\(homeDir)/.cursor",
        "\(homeDir)/.cursor-server",
        "\(homeDir)/Library/Application Support/Cursor",
        "\(homeDir)/Library/Caches/com.todesktop.230313mzl4w4u92",
        "\(homeDir)/Library/Caches/Cursor"
    ]
    
    for path in cachePaths {
        totalBytes += getDirectorySize(path)
    }
    
    return CacheSize(bytes: totalBytes, formatted: formatBytes(totalBytes))
}

func getCursorProjectCacheSize(projectPath: String) -> CacheSize {
    var totalBytes: Int64 = 0
    
    // Check multiple possible cache locations
    let cacheLocations = [
        (projectPath as NSString).appendingPathComponent(".cursor"),
        (projectPath as NSString).appendingPathComponent(".vscode"),
        (projectPath as NSString).appendingPathComponent("node_modules/.cache"),
        (projectPath as NSString).appendingPathComponent(".next"),
        (projectPath as NSString).appendingPathComponent(".turbo"),
        (projectPath as NSString).appendingPathComponent("dist"),
        (projectPath as NSString).appendingPathComponent("build")
    ]
    
    for location in cacheLocations {
        totalBytes += getDirectorySize(location)
    }
    
    return CacheSize(bytes: totalBytes, formatted: formatBytes(totalBytes))
}

func cleanCursorGlobalCache() -> (success: Bool, message: String) {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    var cleaned = 0
    var errors: [String] = []
    
    let cachePaths = [
        "\(homeDir)/.cursor",
        "\(homeDir)/.cursor-server",
        "\(homeDir)/Library/Application Support/Cursor/Cache",
        "\(homeDir)/Library/Caches/com.todesktop.230313mzl4w4u92",
        "\(homeDir)/Library/Caches/Cursor"
    ]
    
    for path in cachePaths {
        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
                cleaned += 1
            } catch {
                errors.append("Failed to clean \(path): \(error.localizedDescription)")
            }
        }
    }
    
    if errors.isEmpty {
        return (true, "Cleaned \(cleaned) cache location(s)")
    } else {
        return (false, errors.joined(separator: "; "))
    }
}

func cleanCursorProjectCache(project: CursorProject) -> (success: Bool, message: String) {
    var cleaned: [String] = []
    var errors: [String] = []
    
    // Clean multiple possible cache locations
    let cacheLocations = [
        (".cursor", "Cursor cache"),
        (".vscode", "VS Code cache"),
        ("node_modules/.cache", "Node cache"),
        (".next", "Next.js cache"),
        (".turbo", "Turborepo cache"),
        ("dist", "Build output"),
        ("build", "Build output")
    ]
    
    for (relativePath, description) in cacheLocations {
        let cachePath = (project.path as NSString).appendingPathComponent(relativePath)
        
        if FileManager.default.fileExists(atPath: cachePath) {
            do {
                try FileManager.default.removeItem(atPath: cachePath)
                cleaned.append(description)
            } catch {
                errors.append("\(description): \(error.localizedDescription)")
            }
        }
    }
    
    if cleaned.isEmpty && errors.isEmpty {
        return (true, "No cache found (already clean)")
    }
    
    if errors.isEmpty {
        return (true, "Cleaned: \(cleaned.joined(separator: ", "))")
    } else {
        return (false, "Cleaned: \(cleaned.joined(separator: ", ")). Errors: \(errors.joined(separator: "; "))")
    }
}

func cleanNodeModulesForProject(project: CursorProject, reinstall: Bool) -> (success: Bool, message: String) {
    let nodeModulesPath = (project.path as NSString).appendingPathComponent("node_modules")
    let packageJsonPath = (project.path as NSString).appendingPathComponent("package.json")
    
    // Check if package.json exists
    guard FileManager.default.fileExists(atPath: packageJsonPath) else {
        return (true, "No package.json found (not a Node.js project)")
    }
    
    // Remove node_modules
    if FileManager.default.fileExists(atPath: nodeModulesPath) {
        do {
            try FileManager.default.removeItem(atPath: nodeModulesPath)
            
            if reinstall {
                // Determine package manager
                let packageManager = detectPackageManager(projectPath: project.path)
                
                // Run install command
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.currentDirectoryURL = URL(fileURLWithPath: project.path)
                
                let installCommand: String
                switch packageManager {
                case "yarn":
                    installCommand = "yarn install"
                case "pnpm":
                    installCommand = "pnpm install"
                default:
                    installCommand = "npm install"
                }
                
                process.arguments = ["-c", "cd '\(project.path)' && \(installCommand)"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        return (true, "Removed node_modules and reinstalled dependencies (\(packageManager))")
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? ""
                        return (false, "Removed node_modules but reinstall failed: \(output)")
                    }
                } catch {
                    return (false, "Removed node_modules but failed to reinstall: \(error.localizedDescription)")
                }
            } else {
                return (true, "Removed node_modules")
            }
        } catch {
            return (false, "Failed to remove node_modules: \(error.localizedDescription)")
        }
    } else {
        if reinstall {
            // No node_modules but reinstall requested
            let packageManager = detectPackageManager(projectPath: project.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.currentDirectoryURL = URL(fileURLWithPath: project.path)
            
            let installCommand: String
            switch packageManager {
            case "yarn":
                installCommand = "yarn install"
            case "pnpm":
                installCommand = "pnpm install"
            default:
                installCommand = "npm install"
            }
            
            process.arguments = ["-c", "cd '\(project.path)' && \(installCommand)"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    return (true, "Installed dependencies (\(packageManager))")
                } else {
                    return (false, "Install failed")
                }
            } catch {
                return (false, "Failed to install: \(error.localizedDescription)")
            }
        }
        return (true, "No node_modules found (already clean)")
    }
}

func detectPackageManager(projectPath: String) -> String {
    let fileManager = FileManager.default
    
    // Check for lock files
    if fileManager.fileExists(atPath: (projectPath as NSString).appendingPathComponent("yarn.lock")) {
        return "yarn"
    }
    if fileManager.fileExists(atPath: (projectPath as NSString).appendingPathComponent("pnpm-lock.yaml")) {
        return "pnpm"
    }
    if fileManager.fileExists(atPath: (projectPath as NSString).appendingPathComponent("package-lock.json")) {
        return "npm"
    }
    
    // Default to npm
    return "npm"
}
#endif

