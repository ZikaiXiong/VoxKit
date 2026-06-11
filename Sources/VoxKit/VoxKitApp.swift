import SwiftUI
import AppKit

@main
struct VoxKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState.shared

    init() {
        // Must run before anything reads UserDefaults / the data directory
        Migration.runIfNeeded()
    }

    var body: some Scene {
        Window(L.appName, id: "main") {
            MainWindow()
                .environmentObject(state)
        }
        .defaultSize(width: 1000, height: 660)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
        } label: {
            Image(systemName: menuIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuIcon: String {
        switch state.phase {
        case .recording, .paused: return "record.circle.fill"
        case .processing: return "ellipsis.circle"
        default: return "waveform.circle"
        }
    }
}

/// Dock icon policy: shown while the main window is open, retracts to the menu bar when it closes (Settings can make it permanent)
@MainActor
enum WindowPolicy {
    static func windowOpened() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func mainWindowClosed() {
        if !UserDefaults.standard.bool(forKey: "showDock") {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    static func applyDockPreference() {
        let show = UserDefaults.standard.bool(forKey: "showDock")
        let hasVisibleMain = NSApp.windows.contains {
            $0.isVisible && ($0.identifier?.rawValue.contains("main") ?? false)
        }
        NSApp.setActivationPolicy(show || hasVisibleMain ? .regular : .accessory)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Global hotkey → Quick Dictation
        HotKeyManager.shared.onHotKey = {
            Task { @MainActor in AppState.shared.toggleQuick() }
        }
        HotKeyManager.shared.applyFromDefaults()

        // Main window closed → retract to the menu bar
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard window.identifier?.rawValue.contains("main") ?? false else { return }
                WindowPolicy.mainWindowClosed()
            }
        }

        WindowPolicy.applyDockPreference()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.store.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // stays resident in the menu bar
    }
}
