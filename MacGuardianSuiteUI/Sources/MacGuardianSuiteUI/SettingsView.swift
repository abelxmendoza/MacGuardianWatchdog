import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @EnvironmentObject var workspace: WorkspaceState
    @State private var reportEmail: String = ""
    @State private var smtpUsername: String = ""
    @State private var smtpPassword: String = ""
    @State private var showPassword: Bool = false
    @State private var showSaveConfirmation: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with Logo
                HStack {
                    LogoView(size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings")
                            .font(.title.bold())
                            .foregroundColor(.themeText)
                        Text("Configure your MacGuardian Suite")
                            .font(.subheadline)
                            .foregroundColor(.themeTextSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                
                // Email Configuration
                SettingsSection(title: "Email Configuration (Optional)", icon: "envelope.fill") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Configure email settings only if you want to receive security reports via email. This is completely optional - the app works fine without email.")
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                            .padding(.bottom, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Report Email")
                                .font(.subheadline.bold())
                                .foregroundColor(.themeText)
                            TextField("your-email@example.com", text: $reportEmail)
                                .textFieldStyle(.roundedBorder)
                                .help("Email address where you want to receive security reports")
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SMTP Username")
                                .font(.subheadline.bold())
                                .foregroundColor(.themeText)
                            TextField("your-email@gmail.com", text: $smtpUsername)
                                .textFieldStyle(.roundedBorder)
                                .help("Your email address (for Gmail, use your full email address)")
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SMTP Password")
                                .font(.subheadline.bold())
                                .foregroundColor(.themeText)
                            HStack {
                                if showPassword {
                                    TextField("Enter password", text: $smtpPassword)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField("Enter password", text: $smtpPassword)
                                        .textFieldStyle(.roundedBorder)
                                }
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.themeTextSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .help("Your email account password (stored securely in macOS Keychain, not plaintext)")
                            
                            Text("💡 For Gmail: Use an App Password, not your regular password")
                                .font(.caption)
                                .foregroundColor(.themeTextSecondary)
                                .padding(.top, 4)
                        }
                        
                        Button("Save Email Settings") {
                            saveEmailSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.themePurple)
                        .controlSize(.large)
                        
                        if showSaveConfirmation {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Settings saved successfully")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                
                // Repository Settings
                SettingsSection(title: "Repository", icon: "folder.fill") {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Repository Path")
                                .font(.subheadline.bold())
                                .foregroundColor(.themeText)
                            HStack {
                                TextField("Repository Path", text: $workspace.repositoryPath)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    selectRepositoryPath()
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.bordered)
                                .tint(.themePurple)
                            }
                        }
                        
                        let validation = workspace.validateRepositoryPath()
                        if !validation.isValid {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(validation.message)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Repository path is valid")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .padding(8)
                            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                
                // About
                SettingsSection(title: "About", icon: "info.circle.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0.0")
                                .foregroundColor(.themeTextSecondary)
                        }
                        
                        Divider()
                            .background(Color.themePurpleDark)
                        
                        Link("Documentation", destination: URL(string: "https://github.com")!)
                            .foregroundColor(.themePurple)
                        
                        Link("Support", destination: URL(string: "mailto:abelxmendoza@gmail.com")!)
                            .foregroundColor(.themePurple)
                    }
                }
            }
            .padding()
        }
        .background(Color.themeBlack)
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        reportEmail = workspace.reportEmail.isEmpty ? UserDefaults.standard.string(forKey: "reportEmail") ?? "" : workspace.reportEmail
        smtpUsername = workspace.smtpUsername.isEmpty ? UserDefaults.standard.string(forKey: "smtpUsername") ?? "" : workspace.smtpUsername
        
        // Load password from Keychain (secure storage)
        if let password = SecureStorage.shared.getPassword(forKey: "smtpPassword") {
            smtpPassword = password
        }
    }
    
    private func saveEmailSettings() {
        // If all fields are empty, just clear settings (email is optional)
        if reportEmail.isEmpty && smtpUsername.isEmpty && smtpPassword.isEmpty {
            workspace.reportEmail = ""
            workspace.smtpUsername = ""
            UserDefaults.standard.removeObject(forKey: "reportEmail")
            UserDefaults.standard.removeObject(forKey: "smtpUsername")
            _ = SecureStorage.shared.deletePassword(forKey: "smtpPassword")
            showSaveConfirmation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showSaveConfirmation = false
            }
            return
        }
        
        // Validate inputs only if email is being configured
        let validation = InputValidator.shared.validateSMTPSettings(
            username: smtpUsername,
            password: smtpPassword,
            email: reportEmail
        )
        
        if !validation.isValid {
            // Show error (you might want to add an error state for this)
            return
        }
        
        workspace.reportEmail = reportEmail
        workspace.smtpUsername = smtpUsername
        
        // Store non-sensitive data in UserDefaults
        UserDefaults.standard.set(reportEmail, forKey: "reportEmail")
        UserDefaults.standard.set(smtpUsername, forKey: "smtpUsername")
        
        // Store password securely in Keychain (encrypted, not plaintext)
        if !smtpPassword.isEmpty {
            let success = SecureStorage.shared.storePassword(smtpPassword, forKey: "smtpPassword")
            if !success {
                // Could show error here if needed
                print("⚠️ Warning: Failed to store password in Keychain")
            }
        } else {
            // Clear password if field is empty
            _ = SecureStorage.shared.deletePassword(forKey: "smtpPassword")
        }
        
        showSaveConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showSaveConfirmation = false
        }
    }
    
    private func selectRepositoryPath() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Select your MacGuardian project folder"
        if panel.runModal() == .OK {
            workspace.repositoryPath = panel.url?.path ?? workspace.repositoryPath
        }
        #endif
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.themePurple)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.themeText)
            }
            
            content
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themePurpleDark, lineWidth: 1)
        )
    }
}

