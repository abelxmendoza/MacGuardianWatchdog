import SwiftUI

struct PanicKillerView: View {
    @State private var isKilling = false
    @State private var showConfirmation = false
    @State private var sessions: [PanicKillSession] = []
    @State private var lastResultMessage: String?
    @State private var lastResultWasError = false
    @State private var expandedSessionIDs: Set<String> = []
    @State private var relaunchFeedback: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().background(Color.themePurpleDark)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    panicButtonSection

                    if let message = lastResultMessage {
                        resultBanner(message: message, isError: lastResultWasError)
                    }

                    SectionHeader(title: "Kill History", icon: "clock.arrow.circlepath")

                    Text("Review what was killed and relaunch anything you still need.")
                        .font(.subheadline)
                        .foregroundColor(.themeTextSecondary)

                    if sessions.isEmpty {
                        emptyHistoryView
                    } else {
                        ForEach(sessions) { session in
                            sessionCard(session)
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color.themeBlack)
        .onAppear {
            sessions = PanicKillService.shared.loadSessions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panicKillCompleted).receive(on: DispatchQueue.main)) { notification in
            guard let result = notification.userInfo?["result"] as? Result<PanicKillSession, PanicKillError> else { return }
            switch result {
            case .success(let session):
                lastResultWasError = false
                lastResultMessage = session.killedCount == 0
                    ? "No node/npm/npx processes were running - nothing to kill."
                    : "Killed \(session.killedCount) process(es). Review them below and relaunch anything you need."
            case .failure(let error):
                lastResultWasError = true
                lastResultMessage = error.errorDescription
            }
            sessions = PanicKillService.shared.loadSessions()
        }
        .alert("Panic Kill Node Processes", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Kill Now", role: .destructive) {
                Task { await runPanicKill() }
            }
        } message: {
            Text("This immediately terminates every running node, npm, npx, and corepack process on this Mac. Anything you're actively using them for (a dev server, a build, a script) will stop.\n\nEach one is logged below with enough detail to relaunch it afterward.")
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                .font(.title)
                .foregroundColor(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Panic Kill")
                    .font(.title.bold())
                    .foregroundColor(.themeText)
                Text("Stop a flood of node/npm alerts instantly, then review and recover")
                    .font(.subheadline)
                    .foregroundColor(.themeTextSecondary)
            }
            Spacer()
            Button {
                sessions = PanicKillService.shared.loadSessions()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .tint(.themePurple)
        }
        .padding()
        .background(Color.themeDarkGray)
    }

    private var panicButtonSection: some View {
        VStack(spacing: 12) {
            Button {
                showConfirmation = true
            } label: {
                HStack(spacing: 10) {
                    if isKilling {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                            .font(.title2)
                    }
                    Text(isKilling ? "Killing..." : "PANIC \u{2014} Kill All Node Processes")
                        .font(.title3.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isKilling)

            Text("Targets exactly node, npm, npx, corepack, and node-gyp processes. Nothing else is touched.")
                .font(.caption)
                .foregroundColor(.themeTextSecondary)
        }
        .padding()
        .background(Color.themeDarkGray.opacity(0.5))
        .cornerRadius(12)
    }

    private func resultBanner(message: String, isError: Bool) -> some View {
        HStack {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.themeText)
            Spacer()
            Button {
                lastResultMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.themeTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background((isError ? Color.red : Color.green).opacity(0.15))
        .cornerRadius(8)
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 40))
                .foregroundColor(.themeTextSecondary)
            Text("No panic-kill sessions yet")
                .font(.headline)
                .foregroundColor(.themeText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func sessionCard(_ session: PanicKillSession) -> some View {
        let isExpanded = expandedSessionIDs.contains(session.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpanded {
                    expandedSessionIDs.remove(session.id)
                } else {
                    expandedSessionIDs.insert(session.id)
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.themeTextSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.killedCount) process(es) killed")
                            .font(.headline)
                            .foregroundColor(.themeText)
                        Text(session.timestamp)
                            .font(.caption)
                            .foregroundColor(.themeTextSecondary)
                    }
                    Spacer()
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(session.killed) { entry in
                        killedEntryRow(entry)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(Color.themeDarkGray.opacity(0.5))
        .cornerRadius(10)
    }

    private func killedEntryRow(_ entry: KilledProcessEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.themeText)
                        .lineLimit(1)
                    Text("PID \(entry.pid) \u{00B7} \(entry.cwd)")
                        .font(.caption2)
                        .foregroundColor(.themeTextSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    relaunch(entry)
                } label: {
                    Label("Relaunch", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.themePurple)
                .disabled(!entry.canRelaunch)
            }

            if let feedback = relaunchFeedback[entry.id] {
                Text(feedback)
                    .font(.caption2)
                    .foregroundColor(.themeTextSecondary)
            }
        }
        .padding(8)
        .background(Color.themeBlack.opacity(0.4))
        .cornerRadius(6)
    }

    private func runPanicKill() async {
        isKilling = true
        // Result display is handled uniformly by the .panicKillCompleted
        // notification below, so this stays in sync with menu-bar-triggered
        // kills too.
        _ = await PanicKillService.shared.runPanicKill()
        isKilling = false
    }

    private func relaunch(_ entry: KilledProcessEntry) {
        let result = PanicKillService.shared.relaunch(entry)
        switch result {
        case .success:
            relaunchFeedback[entry.id] = "Relaunched at \(Date().formatted(date: .omitted, time: .standard))"
        case .failure(let error):
            relaunchFeedback[entry.id] = error.errorDescription
        }
    }
}
