import SwiftUI

/// One result line from ~/.macguardian/checkup/latest.json (written by checkup.sh).
struct CheckupStep: Decodable, Identifiable {
    let step: String
    let status: String
    let summary: String
    let fix: String
    var id: String { step }

    var title: String {
        switch step {
        case "tailscale": return "Tailscale"
        case "posture": return "Security settings"
        case "selfcheck": return "MacGuardian self-check"
        case "threats": return "Threat hunt"
        case "malware": return "Malware scan"
        case "browsers": return "Browser extensions"
        case "updates": return "Software updates"
        default: return step.capitalized
        }
    }

    var icon: String {
        switch status {
        case "pass": return "checkmark.circle.fill"
        case "warn": return "exclamationmark.triangle.fill"
        case "fail": return "xmark.octagon.fill"
        default: return "forward.circle"
        }
    }

    var color: Color {
        switch status {
        case "pass": return .green
        case "warn": return .orange
        case "fail": return .red
        default: return .themeTextSecondary
        }
    }
}

struct CheckupReport: Decodable {
    let finished: String
    let seconds: Int
    let overall: String
    let steps: [CheckupStep]

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".macguardian/checkup/latest.json")
    }

    static func load() -> CheckupReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CheckupReport.self, from: data)
    }
}

/// The dashboard's one-button checkup: Tailscale, posture, self-check, threats,
/// malware, browser extensions and updates, with a plain-language result per step.
struct CheckupCard: View {
    @EnvironmentObject var workspace: WorkspaceState
    @StateObject private var runner = ScriptRunner()
    @State private var report: CheckupReport? = CheckupReport.load()
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "bolt.shield.fill")
                    .foregroundColor(.themePurple)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("One-Click Checkup")
                        .font(.headline)
                        .foregroundColor(.themeText)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                if runner.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { runner.stop() }
                        .buttonStyle(.bordered)
                } else {
                    Button { run(["--quick"]) } label: {
                        Label("Quick", systemImage: "hare.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.themePurple)
                    .help("About a minute: everything except the malware and threat scans")

                    Button { run([]) } label: {
                        Label("Run Checkup", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.themePurple)
                    .help("Full pass, including a malware scan of recent downloads and startup folders")

                    Menu {
                        Button("Full malware scan of all Downloads") { run(["--full"]) }
                        Button("Tailscale only") { run(["--skip", "posture", "--skip", "selfcheck", "--skip", "threats", "--skip", "malware", "--skip", "browsers", "--skip", "updates"]) }
                        Button("Browser extensions only") { run(["--skip", "tailscale", "--skip", "posture", "--skip", "selfcheck", "--skip", "threats", "--skip", "malware", "--skip", "updates"]) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }
            }

            if let report, !runner.isRunning {
                VStack(spacing: 6) {
                    ForEach(report.steps) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: step.icon)
                                .foregroundColor(step.color)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(step.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.themeText)
                                    Spacer()
                                }
                                Text(step.summary)
                                    .font(.caption)
                                    .foregroundColor(.themeTextSecondary)
                                    .textSelection(.enabled)
                                if !step.fix.isEmpty {
                                    Text("Fix: \(step.fix)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.themePurpleLight)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }

            if runner.isRunning || showLog {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(runner.output.isEmpty ? "Starting…" : runner.output)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.themeText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(height: 180)
                    .background(Color.themeBlack, in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: runner.output) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                }
            }

            HStack {
                if !runner.output.isEmpty && !runner.isRunning {
                    Button(showLog ? "Hide log" : "Show log") { showLog.toggle() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                Spacer()
                Text("Terminal: macguardian checkup  •  AI tools: macguardian setup-agents")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.themePurpleLight)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var statusLine: String {
        if runner.isRunning { return "Checking your Mac… this takes a few minutes with the malware scan." }
        guard let report else { return "Tailscale, security settings, threats, malware, browser extensions and updates in one pass." }
        let verdict: String
        switch report.overall {
        case "pass": verdict = "All clear"
        case "warn": verdict = "A few things are worth a look"
        default: verdict = "Action needed"
        }
        return "\(verdict) · last run \(report.finished.replacingOccurrences(of: "T", with: " ")) (\(report.seconds)s)"
    }

    private var borderColor: Color {
        switch report?.overall {
        case "fail": return .red.opacity(0.6)
        case "warn": return .orange.opacity(0.6)
        default: return .themePurpleDark
        }
    }

    private func run(_ arguments: [String]) {
        showLog = false
        runner.run(scriptPath: "MacGuardianSuite/checkup.sh", arguments: arguments,
                   repositoryPath: workspace.repositoryPath) {
            report = CheckupReport.load()
        }
    }
}
