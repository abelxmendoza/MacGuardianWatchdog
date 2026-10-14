import SwiftUI

struct LogoView: View {
    let size: CGFloat
    
    init(size: CGFloat = 120) {
        self.size = size
    }
    
    var body: some View {
        Group {
            if let logoImage = loadLogoImage() {
                Image(nsImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                // Minimal fallback - just show text if image not found
                Text("MacGuardian")
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundColor(.themeText)
            }
        }
    }
    
    #if os(macOS)
    private func loadLogoImage() -> NSImage? {
        // Prioritize MacGuardianlogo-brighter.jpg (brighter version for better visibility)
        let logoNames = ["MacGuardianlogo-brighter", "MacGlogo", "MacGuardianLogo"]
        let extensions = ["jpg", "jpeg", "png"]
        
        // Try to load from main bundle Resources (for app bundle)
        for logoName in logoNames {
            for ext in extensions {
                // Try bundle resource first
                if let imagePath = Bundle.main.path(forResource: logoName, ofType: ext) {
                    if let image = NSImage(contentsOfFile: imagePath) {
                        return image
                    }
                }
                
                // Try Resources/images/ path in bundle
                if let resourcePath = Bundle.main.resourcePath {
                    let imagePath = "\(resourcePath)/images/\(logoName).\(ext)"
                    if FileManager.default.fileExists(atPath: imagePath) {
                        if let image = NSImage(contentsOfFile: imagePath) {
                            return image
                        }
                    }
                }
            }
        }
        
        // Try development paths (for SwiftUI previews and development)
        let devPaths = [
            "\(FileManager.default.currentDirectoryPath)/Resources/images/MacGlogo.png",
            "\(FileManager.default.currentDirectoryPath)/MacGuardianSuiteUI/Resources/images/MacGlogo.png",
            "\(RepoLocator.path)/MacGuardianSuiteUI/Resources/images/MacGlogo.png"
        ]
        
        for path in devPaths {
            if FileManager.default.fileExists(atPath: path) {
                if let image = NSImage(contentsOfFile: path) {
                    return image
                }
            }
        }
        
        return nil
    }
    #endif
}
