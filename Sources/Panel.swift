import AppKit
import SwiftUI

final class PanelState: ObservableObject {
    @Published var presented = false
}

struct PanelHost: View {
    @EnvironmentObject private var panel: PanelState

    var body: some View {
        RootView()
            .frame(width: Metrics.panelWidth, height: Metrics.panelHeight)
            .scaleEffect(panel.presented ? 1 : 0.94, anchor: .top)
            .opacity(panel.presented ? 1 : 0)
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        (delegate as? PanelController)?.hide()
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let store: VaultStore
    private let state = PanelState()
    private var panel: FloatingPanel!
    private var effectView: NSVisualEffectView!

    /// The desktop card keeps its own idle timer, so closing the panel must not
    /// yank the vault shut underneath it.
    var lockOnHide: () -> Bool = { true }
    private var modalDialogActive = false

    var isVisible: Bool { panel?.isVisible ?? false }

    init(store: VaultStore) {
        self.store = store
        super.init()
        buildPanel()
        NotificationCenter.default.addObserver(
            forName: .slateModalBegan, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.modalDialogActive = true } }
        NotificationCenter.default.addObserver(
            forName: .slateModalEnded, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.modalDialogActive = false } }
    }

    private func buildPanel() {
        let size = NSSize(width: Metrics.panelWidth, height: Metrics.panelHeight)
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        panel.animationBehavior = .none

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true

        effectView = NSVisualEffectView(frame: container.bounds)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Metrics.cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        container.addSubview(effectView)

        let hosting = NSHostingView(
            rootView: PanelHost()
                .environmentObject(store)
                .environmentObject(state)
                .environmentObject(WindowDragProxy())
        )
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
    }

    func toggle(relativeTo button: NSStatusBarButton?) {
        if panel.isVisible {
            hide()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton?) {
        position(relativeTo: button)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        withAnimation(Motion.snappy) { state.presented = true }
        store.unlock()
    }

    func hide() {
        guard panel.isVisible else { return }
        NotificationCenter.default.post(name: .keyVaultPanelWillHide, object: nil)
        withAnimation(Motion.snappy) { state.presented = false }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.orderOut(nil)
                if self.lockOnHide() { self.store.lock() }
            }
        }
    }

    private func position(relativeTo button: NSStatusBarButton?) {
        let size = panel.frame.size
        let screen = button?.window?.screen ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame

        var origin = CGPoint(
            x: visible.maxX - size.width - 14,
            y: visible.maxY - size.height - 8
        )

        // The status item has no usable frame until the menu bar lays it out.
        if let button, let window = button.window, window.frame.height > 0,
           window.frame.maxY > visible.midY {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            origin.x = rect.midX - size.width / 2
            origin.y = rect.minY - size.height - 8
        }

        origin.x = min(max(origin.x, visible.minX + 10), visible.maxX - size.width - 10)
        origin.y = min(origin.y, visible.maxY - size.height - 6)
        origin.y = max(origin.y, visible.minY + 10)
        panel.setFrameOrigin(origin)
    }

    // Keep the panel open while the Touch ID sheet steals key focus.
    func windowDidResignKey(_ notification: Notification) {
        guard store.phase != .unlocking, !modalDialogActive else { return }
        hide()
    }
}
