import AppKit
import Combine
import SwiftUI

/// Locked face of the desktop card: a widget-sized tile that reveals nothing.
struct DesktopFace: View {
    @EnvironmentObject private var store: VaultStore
    @State private var pulse = false

    private var isBusy: Bool { store.phase == .unlocking }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Brand.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(isBusy ? "驗證中" : "已鎖定")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .trim(from: 0, to: isBusy ? 0.72 : 1)
                        .stroke(Palette.gradient(for: "accent"), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(pulse && isBusy ? 360 : 0))
                        .animation(
                            isBusy ? .linear(duration: 1.1).repeatForever(autoreverses: false) : Motion.gentle,
                            value: pulse
                        )
                    Image(systemName: "touchid")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(Palette.gradient(for: "accent"))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array([206.0, 138.0, 174.0].enumerated()), id: \.offset) { _, width in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: 14, height: 14)
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: width, height: 7)
                    }
                }
            }
            .padding(.top, 14)

            Spacer(minLength: 0)

            Text(store.message ?? "點一下用 Touch ID 開啟")
                .font(.system(size: 11))
                .foregroundStyle(store.message == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color(red: 0.95, green: 0.35, blue: 0.35)))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: Metrics.cardWidth, height: Metrics.cardCollapsedHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { store.unlock() }
        .onAppear { pulse = true }
        .animation(Motion.snappy, value: store.message)
    }
}

final class CardState: ObservableObject {
    @Published var lifted = false
}

/// Lets a view drag the window it lives in. The floating panel injects a no-op
/// so the same views stay usable there.
final class WindowDragProxy: ObservableObject {
    var onMove: ((CGSize) -> Void)?
    var onEnd: (() -> Void)?

    private var last: CGSize = .zero

    func drag(to translation: CGSize) {
        let delta = CGSize(
            width: translation.width - last.width,
            height: translation.height - last.height
        )
        last = translation
        onMove?(delta)
    }

    func end() {
        last = .zero
        onEnd?()
    }
}

struct DesktopCardView: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var card: CardState

    var body: some View {
        content
            .scaleEffect(card.lifted ? 1.04 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: card.lifted)
    }

    private var content: some View {
        ZStack {
            if store.phase == .unlocked {
                RootView()
                    .frame(width: Metrics.cardWidth)
                    .frame(maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                DesktopFace()
                    .transition(.opacity)
            }
        }
    }
}

/// The invisible lattice macOS desktop widgets snap to, anchored at the top-left
/// of the usable screen area.
enum WidgetGrid {
    static var pitch: CGFloat { Metrics.widgetPitch }

    static func origin(in visible: NSRect) -> NSPoint {
        NSPoint(x: visible.minX + Metrics.widgetInsetX, y: visible.maxY - Metrics.widgetInsetY)
    }

    static func snap(
        topLeft: NSPoint,
        size: NSSize,
        in visible: NSRect,
        avoiding occupied: [NSRect] = []
    ) -> NSPoint {
        let start = origin(in: visible)
        let lastColumn = Int(max(0, floor((visible.maxX - start.x - size.width) / pitch)))
        let lastRow = Int(max(0, floor((start.y - visible.minY - size.height) / pitch)))

        var candidates: [(point: NSPoint, distance: CGFloat, free: Bool)] = []
        for column in 0...lastColumn {
            for row in 0...lastRow {
                let point = NSPoint(x: start.x + CGFloat(column) * pitch, y: start.y - CGFloat(row) * pitch)
                let frame = NSRect(x: point.x, y: point.y - size.height, width: size.width, height: size.height)
                let dx = point.x - topLeft.x, dy = point.y - topLeft.y
                candidates.append((point, dx * dx + dy * dy, !occupied.contains { $0.intersects(frame) }))
            }
        }
        let sorted = candidates.sorted { $0.distance < $1.distance }
        return (sorted.first { $0.free } ?? sorted.first)?.point ?? topLeft
    }

    /// Frames of the system's own desktop widgets, so a card never lands on one.
    static func occupiedFrames(excluding windowNumber: Int) -> [NSRect] {
        guard let screen = NSScreen.main else { return [] }
        let level = Int(CGWindowLevelForKey(.desktopIconWindow)) + 2
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == level,
                  (info[kCGWindowIsOnscreen as String] as? Bool) == true,
                  (info[kCGWindowNumber as String] as? Int) != windowNumber,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { return nil }
            return NSRect(x: x, y: screen.frame.maxY - (y + height), width: width, height: height)
        }
    }
}

final class DesktopWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// NSHostingView swallows the first click in a background window unless asked not to.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @MainActor required dynamic init?(coder: NSCoder) { super.init(coder: coder) }
    @MainActor required init(rootView: Content) { super.init(rootView: rootView) }
}

@MainActor
final class DesktopCardController: NSObject, NSWindowDelegate {
    private let store: VaultStore
    private var window: DesktopWindow!
    private var effectView: NSVisualEffectView!
    private var cancellables: Set<AnyCancellable> = []
    private var autoLockWork: DispatchWorkItem?
    private var snapWork: DispatchWorkItem?
    private var isDragging = false
    private let cardState = CardState()
    private let dragProxy = WindowDragProxy()
    private let gridOverlay = GridOverlayController()
    private var restingTopLeft: NSPoint = .zero
    /// The height we asked for. During an animation the window still reports
    /// the old one, so comparing against the window would drop the request
    /// that arrives while a previous resize is still running.
    private var targetHeight = Metrics.cardWindowCollapsedHeight
    private var isSnapping = false

    private static let originKey = "DesktopCardTopLeft"
    private static let visibleKey = "DesktopCardVisible"
    private static let idleLockSeconds: TimeInterval = 90

    var isVisible: Bool { window.isVisible }
    var isExpanded: Bool { window.isVisible && store.phase == .unlocked }

    init(store: VaultStore) {
        self.store = store
        super.init()
        buildWindow()
        observeStore()

        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.visibleKey) as? Bool ?? true { show() }
    }

    private func buildWindow() {
        let size = NSSize(width: Metrics.cardWindowWidth, height: Metrics.cardWindowCollapsedHeight)
        window = DesktopWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        // Same layer the system's own desktop widgets sit on.
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.animationBehavior = .none
        window.delegate = self

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true

        let cardFrame = container.bounds.insetBy(dx: Metrics.cardShadowInset, dy: Metrics.cardShadowInset)
        effectView = NSVisualEffectView(frame: cardFrame)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .windowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Metrics.cardCornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        container.addSubview(effectView)

        dragProxy.onMove = { [weak self] delta in
            guard let self else { return }
            var frame = self.window.frame
            frame.origin.x += delta.width
            frame.origin.y -= delta.height
            self.window.setFrameOrigin(frame.origin)
        }
        dragProxy.onEnd = { [weak self] in self?.scheduleSnap(after: 0.05) }

        let hosting = FirstMouseHostingView(
            rootView: DesktopCardView()
                .environmentObject(store)
                .environmentObject(cardState)
                .environmentObject(dragProxy)
        )
        hosting.frame = cardFrame
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        window.contentView = container
        restingTopLeft = savedTopLeft(for: size)
        targetHeight = size.height
        window.setFrameTopLeftPoint(restingTopLeft)
    }

    private func observeStore() {
        store.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                guard let self else { return }
                self.resize(expanded: phase == .unlocked)
                if phase == .unlocked { self.scheduleAutoLock() } else { self.autoLockWork?.cancel() }
            }
            .store(in: &cancellables)

        store.objectWillChange
            .sink { [weak self] in
                guard let self, self.store.phase == .unlocked else { return }
                self.scheduleAutoLock()
            }
            .store(in: &cancellables)
    }

    private func scheduleAutoLock() {
        autoLockWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.store.phase == .unlocked else { return }
            withAnimation(Motion.snappy) { self.store.lock() }
        }
        autoLockWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleLockSeconds, execute: work)
    }

    private func resize(expanded: Bool) {
        let visible = (window.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let top = restingTopLeft.y

        // The top edge never moves: the card only ever grows downwards, and
        // stops at the bottom of the screen if it runs out of room.
        let wanted = expanded ? Metrics.cardWindowExpandedHeight : Metrics.cardWindowCollapsedHeight
        let available = max(Metrics.cardWindowCollapsedHeight, top - visible.minY)
        let height = min(wanted, available)
        guard height != targetHeight else { return }
        targetHeight = height

        let frame = NSRect(
            x: restingTopLeft.x,
            y: top - height,
            width: Metrics.cardWindowWidth,
            height: height
        )

        isSnapping = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.isSnapping = false }
        }
    }

    private func savedTopLeft(for size: NSSize) -> NSPoint {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame

        // A remembered position is honoured exactly; only a first run picks a
        // free slot, and only then does it care what else is on the desktop.
        if let stored = UserDefaults.standard.string(forKey: Self.originKey) {
            return WidgetGrid.snap(topLeft: NSPointFromString(stored), size: size, in: visible)
        }

        let start = WidgetGrid.origin(in: visible)
        return WidgetGrid.snap(
            topLeft: NSPoint(x: start.x + Metrics.widgetPitch * 3, y: start.y),
            size: size,
            in: visible,
            avoiding: WidgetGrid.occupiedFrames(excluding: window.windowNumber)
        )
    }

    func show() {
        window.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: Self.visibleKey)
    }

    func hide() {
        store.lock()
        window.orderOut(nil)
        UserDefaults.standard.set(false, forKey: Self.visibleKey)
    }

    func toggle() {
        window.isVisible ? hide() : show()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isSnapping else { return }
        if !isDragging {
            isDragging = true
            cardState.lifted = true
        }
        gridOverlay.show(slot: targetSlot())
        scheduleSnap(after: 0.18)
    }

    /// A pause mid-drag is not a drop, so the button state decides, not a timer.
    private func scheduleSnap(after delay: TimeInterval) {
        snapWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard NSEvent.pressedMouseButtons & 1 == 0 else {
                self.scheduleSnap(after: 0.1)
                return
            }
            self.snapToGrid()
        }
        snapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Where the card would land if it were dropped right now. Occupied slots
    /// are not avoided here: a drag should land where the pointer says, even if
    /// that sits alongside a system widget.
    private func targetSlot() -> NSRect {
        let visible = (window.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let current = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let target = WidgetGrid.snap(topLeft: current, size: window.frame.size, in: visible)
        return NSRect(
            x: target.x,
            y: target.y - window.frame.height,
            width: window.frame.width,
            height: window.frame.height
        )
    }

    private func snapToGrid() {
        isDragging = false
        cardState.lifted = false
        let frame = targetSlot()
        restingTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
        targetHeight = frame.height
        UserDefaults.standard.set(NSStringFromPoint(restingTopLeft), forKey: Self.originKey)

        guard frame != window.frame else {
            gridOverlay.hide()
            return
        }
        isSnapping = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.45, 0.36, 1)
            window.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isSnapping = false
                self?.gridOverlay.hide()
            }
        }
    }
}

/// While a card is being moved, macOS shows only the slot it will land in.
@MainActor
final class GridOverlayController {
    private let window: NSPanel
    private var hideWork: DispatchWorkItem?

    init() {
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.cardWindowWidth, height: Metrics.cardWindowCollapsedHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.animationBehavior = .none
        window.alphaValue = 0

        let hosting = NSHostingView(rootView: GridSlotView())
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
    }

    func show(slot: NSRect) {
        hideWork?.cancel()
        window.setFrame(slot, display: true)
        guard window.alphaValue < 1 else { return }
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.window.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                self?.window.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}

struct GridSlotView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.30), lineWidth: 3)
            .padding(Metrics.cardShadowInset)
    }
}
