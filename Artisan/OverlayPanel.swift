import AppKit
import SwiftUI

@MainActor
final class FloatingWidgetController {
    static let shared = FloatingWidgetController()
    private var panel: PetPanel?
    private weak var store: FileTaskStore?

    func openManager() {
        guard let store else { return }
        ManagerWindowController.shared.show(store: store)
    }

    func show(store: FileTaskStore) {
        self.store = store
        guard store.isConfigured else { return }
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let storedScale = UserDefaults.standard.double(forKey: "artisan.widget.scale")
        let scale = storedScale == 0 ? CGFloat(1) : CGFloat(storedScale)
        let size = NSSize(width: 180 * scale, height: 54 * scale)
        let panel = PetPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = false
        panel.contentView = NSHostingView(rootView: FloatingBarView(store: store) { newScale in
            guard let panel = self.panel else { return }
            let origin = panel.frame.origin
            panel.setContentSize(NSSize(width: 180 * newScale, height: 54 * newScale))
            panel.setFrameOrigin(origin)
        })

        if let mainFrame = NSScreen.main?.visibleFrame {
            let savedOrigin = NSPoint(
                x: UserDefaults.standard.object(forKey: "artisan.widget.x") as? CGFloat ?? mainFrame.midX - size.width / 2,
                y: UserDefaults.standard.object(forKey: "artisan.widget.y") as? CGFloat ?? mainFrame.minY + 32
            )
            let display = NSScreen.screens.first(where: { $0.visibleFrame.intersects(NSRect(origin: savedOrigin, size: size)) })
                ?? NSScreen.main
            let visible = display?.visibleFrame ?? mainFrame
            let x = min(max(savedOrigin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
            let y = min(max(savedOrigin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.onMove = { [weak panel] in
            guard let panel else { return }
            UserDefaults.standard.set(panel.frame.origin.x, forKey: "artisan.widget.x")
            UserDefaults.standard.set(panel.frame.origin.y, forKey: "artisan.widget.y")
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

@MainActor
final class ManagerWindowController: NSObject, NSWindowDelegate {
    static let shared = ManagerWindowController()
    private var window: NSWindow?

    func show(store: FileTaskStore) {
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = ManagerView(store: store)
            .frame(minWidth: 840, minHeight: 560)
            .onChange(of: store.isConfigured) { _, ready in
                if ready { FloatingWidgetController.shared.show(store: store) }
                else { FloatingWidgetController.shared.hide() }
            }
            .alert("Artisan", isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )) {
                Button("OK", role: .cancel) { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
            }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Artisan"
        window.identifier = NSUserInterfaceItemIdentifier("artisan.manager")
        window.minSize = NSSize(width: 840, height: 560)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.delegate = self
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow, closedWindow === window else { return }
        window = nil
    }
}

@MainActor
private final class PetPanel: NSPanel {
    var onMove: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        onMove?()
    }
}
