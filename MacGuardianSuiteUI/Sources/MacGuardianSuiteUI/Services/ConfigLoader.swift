import Foundation
import Yams
import Combine

/// High-performance config loader with in-memory caching and dirty-bit tracking
final class ConfigLoader: ObservableObject {
    static let shared = ConfigLoader()
    
    private var cachedConfig: MacGuardianConfig?
    private var cachedDict: [String: Any]?
    private var configPath: String
    private var lastModified: Date?
    private var isDirty: Bool = false
    
    @Published var didUpdate = false
    
    private init() {
        // Use Application Support directory for config storage
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let macGuardianURL = appSupportURL.appendingPathComponent("MacGuardian")
        let configURL = macGuardianURL.appendingPathComponent("config.yaml")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: macGuardianURL, withIntermediateDirectories: true)
        
        // Migrate existing config from old location if it exists
        let oldPath = "\(RepoLocator.path)/MacGuardianSuite/config/config.yaml"
        if FileManager.default.fileExists(atPath: oldPath) && !FileManager.default.fileExists(atPath: configURL.path) {
            try? FileManager.default.copyItem(atPath: oldPath, toPath: configURL.path)
        }
        
        // Fallback to default config in project if user config doesn't exist
        if !FileManager.default.fileExists(atPath: configURL.path) {
            let defaultPath = "\(RepoLocator.path)/MacGuardianSuite/config/config.yaml"
            if FileManager.default.fileExists(atPath: defaultPath) {
                try? FileManager.default.copyItem(atPath: defaultPath, toPath: configURL.path)
            }
        }
        
        self.configPath = configURL.path
    }
    
    /// Get the current config file path (for debugging)
    var configFilePath: String {
        return configPath
    }
    
    /// Load config with caching (O(1) if cached, O(n) if file read needed)
    func load() -> MacGuardianConfig {
        // Check if file was modified
        if let lastModified = lastModified,
           let fileModified = try? FileManager.default.attributesOfItem(atPath: configPath)[.modificationDate] as? Date,
           fileModified <= lastModified,
           let cached = cachedConfig {
            return cached  // Return cached version (O(1))
        }
        
        // Load from file
        do {
            if let yamlString = try? String(contentsOfFile: configPath, encoding: .utf8),
               let dict = try Yams.load(yaml: yamlString) as? [String: Any] {
                
                let config = MacGuardianConfig.fromDict(dict)
                
                // Update cache
                cachedConfig = config
                cachedDict = dict
                lastModified = try? FileManager.default.attributesOfItem(atPath: configPath)[.modificationDate] as? Date
                isDirty = false
                
                return config
            }
        } catch {
            print("⚠️ Failed to load config: \(error)")
        }
        
        // Return default if loading fails
        return MacGuardianConfig.default
    }
    
    /// Update config in memory (O(1))
    func update(_ config: MacGuardianConfig) {
        cachedConfig = config
        cachedDict = config.toDict()
        isDirty = true
        
        DispatchQueue.main.async {
            self.didUpdate.toggle()
        }
    }
    
    /// Save config to disk (only if dirty) (O(n) where n = config size)
    func save() throws {
        guard isDirty, let config = cachedConfig else {
            return  // Nothing to save
        }
        
        let dict = config.toDict()
        let yaml = try Yams.dump(object: dict, sortKeys: true)
        
        // Ensure directory exists
        let configDir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        
        try yaml.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
        
        // Update cache state
        lastModified = try? FileManager.default.attributesOfItem(atPath: configPath)[.modificationDate] as? Date
        isDirty = false
    }
    
    /// Force reload from disk (bypass cache)
    func reload() -> MacGuardianConfig {
        cachedConfig = nil
        cachedDict = nil
        lastModified = nil
        return load()
    }
    
    /// Check if config has unsaved changes
    var hasUnsavedChanges: Bool {
        return isDirty
    }
    
    /// Get cached config (O(1))
    var currentConfig: MacGuardianConfig? {
        return cachedConfig
    }
}

