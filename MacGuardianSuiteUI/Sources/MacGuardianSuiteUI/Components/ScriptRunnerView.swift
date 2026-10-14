import SwiftUI

/// Runs one suite script and streams its output. Used for the few scripts
/// that are worth a button but don't have a dedicated screen.
@MainActor
final class ScriptRunner: ObservableObject {
    @Published var output = ""
    @Published var isRunning = false
    @Published var exitCode: Int32?

    private var process: Process?

    /// `scriptPath` is relative to the repository root, e.g. "MacGuardianSuite/mac_watchdog.sh".
    func run(scriptPath: String, arguments: [String] = [], repositoryPath: String, onFinish: (() -> Void)? = nil) {
        guard !isRunning else { return }
        let suiteDir = "\(repositoryPath)/MacGuardianSuite"
        let fullPath = "\(repositoryPath)/\(scriptPath)"
        guard FileManager.default.fileExists(atPath: fullPath) else {
            output = "Script not found at \(fullPath).\nCheck the repository path in Settings."
            exitCode = 1
            return
        }

        output = ""
        exitCode = nil
        isRunning = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [fullPath] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: suiteDir)
        // No terminal attached: scripts that prompt get an empty answer
        // instead of hanging forever.
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.output += Self.stripANSI(text) }
        }
        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                self?.isRunning = false
                self?.exitCode = finished.terminationStatus
                self?.process = nil
                onFinish?()
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            isRunning = false
            output = "Could not start script: \(error.localizedDescription)"
            exitCode = 1
        }
    }

    func stop() {
        process?.terminate()
    }

    private static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
    }
}

/// A titled panel with a Run/Stop button and the script's live output.
struct ScriptRunnerView: View {
    @EnvironmentObject private var workspace: WorkspaceState
    @StateObject private var runner = ScriptRunner()

    let icon: String
    let title: String
    let subtitle: String
    let whatItDoes: String
    let whyItMatters: String
    var checks: [String] = []
    let scriptPath: String
    var arguments: [String] = []
    var runLabel = "Run"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(.themePurple)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title.bold())
                        .foregroundColor(.themeText)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()

                if runner.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { runner.stop() }
                        .buttonStyle(.bordered)
                } else {
                    Button {
                        runner.run(scriptPath: scriptPath, arguments: arguments, repositoryPath: workspace.repositoryPath)
                    } label: {
                        Label(runLabel, systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.themePurple)
                }
            }
            .padding()
            .background(Color.themeDarkGray)

            Divider()
                .background(Color.themePurpleDark)

            VStack(spacing: 16) {
                FeatureInfoCard(
                    icon: icon,
                    title: title,
                    whatItDoes: whatItDoes,
                    whyItMatters: whyItMatters,
                    checks: checks
                )

                if let code = runner.exitCode {
                    HStack(spacing: 6) {
                        Image(systemName: code == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        Text(code == 0 ? "Finished" : "Finished with exit code \(code)")
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundColor(code == 0 ? .green : .orange)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(runner.output.isEmpty ? "Output will appear here." : runner.output)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(runner.output.isEmpty ? .themeTextSecondary : .themeText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: runner.output) { _, _ in
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
            }
            .padding()
        }
        .background(Color.themeBlack)
    }
}
