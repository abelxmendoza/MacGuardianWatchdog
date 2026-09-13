import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct MacGuardianSuiteUIApp: App {
    @StateObject private var workspace = WorkspaceState()

    init() {
        #if os(macOS)
        // Configure NSApplication for proper app behavior
        NSApplication.shared.setActivationPolicy(.regular)
        
        // Ensure app appears in Dock and can be activated
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workspace)
                .onAppear {
                    #if os(macOS)
                    bringMacGuardianAboveAlertFloods()
                    #endif

                    // Initialize EventPipeline to start listening for events
                    _ = EventPipeline.shared
                    // Start LiveUpdateService for real-time WebSocket events
                    LiveUpdateService.shared.start()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("MacGuardian", systemImage: "shield.lefthalf.filled") {
            MenuBarPanicMenu(workspace: workspace)
        }
    }
}

#if os(macOS)
/// Forces MacGuardian's window(s) above a flood of LuLu-style alert popups.
///
/// LuLu's own alert window runs at NSPopUpMenuWindowLevel (confirmed from its
/// source: AlertWindowController.m sets [self.window setLevel:NSPopUpMenuWindowLevel],
/// rawValue 101). Activating our app or reordering our own window among its
/// own siblings can't out-rank a window sitting at a higher level - window
/// level, not which app is frontmost, decides draw order. .screenSaver
/// (rawValue 1000) comfortably outranks it, so elevate briefly and then drop
/// back to normal so this doesn't become a permanent always-on-top window
/// outside of an actual alert flood.
func bringMacGuardianAboveAlertFloods() {
    NSApplication.shared.activate(ignoringOtherApps: true)

    for window in NSApplication.shared.windows where window.contentViewController != nil || window.isVisible {
        window.level = .screenSaver
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            window.level = .normal
        }
    }
}
#endif

/// Menu bar content shown even when the main window is closed or buried,
/// so the panic-kill action is reachable during an alert flood without
/// having to find the app window first.
private struct MenuBarPanicMenu: View {
    @ObservedObject var workspace: WorkspaceState
    @State private var isKilling = false

    var body: some View {
        Button {
            bringAppToFront()
            guard !isKilling else { return }
            isKilling = true
            Task {
                _ = await PanicKillService.shared.runPanicKill()
                isKilling = false
            }
        } label: {
            Text(isKilling ? "Killing node processes..." : "\u{26A1} Panic Kill Node Processes")
        }
        .disabled(isKilling)

        Button("Show MacGuardian") {
            bringAppToFront()
        }

        Divider()

        Button("Quit MacGuardian") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func bringAppToFront() {
        #if os(macOS)
        workspace.selectedView = .panicKiller
        bringMacGuardianAboveAlertFloods()
        #endif
    }
}
