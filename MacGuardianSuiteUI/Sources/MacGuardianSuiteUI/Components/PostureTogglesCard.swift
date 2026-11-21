import SwiftUI
#if os(macOS)
import AppKit
#endif

/// One control from `posture_toggles.sh status --json`.
struct PostureControl: Decodable, Identifiable {
    let control: String
    let label: String
    let state: String
    let safe_state: String
    let safe: Bool
    var id: String { control }
    var isOn: Bool { state == "on" }

    var icon: String {
        switch control {
        case "ssh": return "terminal"
        case "screenlock": return "lock.fill"
        case "airplay": return "airplayvideo"
        case "powernap": return "moon.zzz.fill"
        case "netwake": return "wifi"
        case "extensions": return "doc.text"
        default: return "switch.2"
        }
    }
}

/// Dashboard card: see six hardening controls and switch them on or off.
/// Reading state needs no privileges; changes run in Terminal so macOS can
/// ask for your password where it requires one.
struct PostureTogglesCard: View {
    @EnvironmentObject var workspace: WorkspaceState
    @State private var controls: [PostureControl] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "switch.2")
                    .foregroundColor(.themePurple)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hardening Toggles")
                        .font(.headline)
                        .foregroundColor(.themeText)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundColor(.themeTextSecondary)
                }
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                Button { refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Re-read the current settings")
                Button { openInTerminal("harden") } label: {
                    Label("Harden all", systemImage: "shield.lefthalf.filled")
                }
                .buttonStyle(.borderedProminent)
                .tint(.themePurple)
                .disabled(controls.isEmpty || unsafeCount == 0)
                .help("Put every control in its recommended state (asks before each change)")
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            VStack(spacing: 8) {
                ForEach(controls) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .foregroundColor(.themeTextSecondary)
                            .frame(width: 18)
                        Image(systemName: item.safe ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundColor(item.safe ? .green : .orange)
                            .help(item.safe ? "Recommended setting" : "Recommended: \(item.safe_state)")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                                .font(.subheadline)
                                .foregroundColor(.themeText)
                            if !item.safe {
                                Text("Recommended: \(item.safe_state)")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { item.isOn },
                            set: { newValue in openInTerminal("\(newValue ? "on" : "off") \(item.control)") }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help("Opens Terminal to switch \(item.label) \(item.isOn ? "off" : "on")")
                    }
                }
            }

            HStack {
                Spacer()
                Text("Terminal: macguardian posture  •  posture harden  •  posture on|off <control>")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.themePurpleLight)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .background(Color.themeDarkGray, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(unsafeCount > 0 ? Color.orange.opacity(0.6) : Color.themePurpleDark, lineWidth: 1)
        )
        .onAppear { refresh() }
        #if os(macOS)
        // Coming back from Terminal: pick up whatever changed there.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        #endif
    }

    private var unsafeCount: Int { controls.filter { !$0.safe }.count }

    private var statusLine: String {
        if controls.isEmpty { return isLoading ? "Reading your settings…" : "SSH, screen lock, AirPlay, Power Nap, network wake and file extensions." }
        if unsafeCount == 0 { return "All \(controls.count) controls are in the recommended state." }
        return "\(unsafeCount) of \(controls.count) controls differ from the recommended state. Switches open Terminal to apply the change."
    }

    private var scriptPath: String {
        (workspace.repositoryPath as NSString).appendingPathComponent("MacGuardianSuite/posture_toggles.sh")
    }

    private func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let path = scriptPath
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.readStatus(scriptPath: path)
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let items):
                    controls = items
                    errorText = nil
                case .failure(let message):
                    errorText = message
                }
            }
        }
    }

    private enum StatusResult { case success([PostureControl]), failure(String) }

    private static func readStatus(scriptPath: String) -> StatusResult {
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            return .failure("posture_toggles.sh not found. Check the repository path in Settings.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, "status", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let items = try JSONDecoder().decode([PostureControl].self, from: data)
            return .success(items)
        } catch {
            return .failure("Couldn't read the current settings: \(error.localizedDescription)")
        }
    }

    private func openInTerminal(_ arguments: String) {
        // Controls and verbs come from a fixed list, so no user text reaches the shell.
        TerminalLauncher.shared.openTerminal(
            with: "./macguardian posture \(arguments)",
            workingDirectory: workspace.repositoryPath,
            title: "MacGuardian · Hardening Toggles"
        )
    }
}
