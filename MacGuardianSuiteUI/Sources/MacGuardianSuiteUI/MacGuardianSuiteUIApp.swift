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
                    // Activate the app to bring it to front
                    NSApplication.shared.activate(ignoringOtherApps: true)
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
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows where window.contentViewController != nil || window.isVisible {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        #endif
    }
}
