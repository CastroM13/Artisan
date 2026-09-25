import SwiftUI

@main
struct ArtisanApp: App {
    @NSApplicationDelegateAdaptor(ArtisanAppDelegate.self) private var appDelegate
    @StateObject private var store: FileTaskStore

    init() {
        _store = StateObject(wrappedValue: FileTaskStore.shared)
    }

    var body: some Scene {
        Settings {
            ArtisanSettingsView()
                .frame(width: 430, height: 220)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Open Task Tracker") { ManagerWindowController.shared.show(store: store) }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                Button("Show Floating Task Bar") { FloatingWidgetController.shared.show(store: store) }
            }
        }
    }
}

@MainActor
private final class ArtisanAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = FileTaskStore.shared
        if store.isConfigured {
            FloatingWidgetController.shared.show(store: store)
        } else {
            ManagerWindowController.shared.show(store: store)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the process alive while the floating task bar is the only visible UI.
        false
    }
}
