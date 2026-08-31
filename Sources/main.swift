import AppKit

@MainActor
private func bootstrap() -> AppDelegate {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    return delegate
}

let retainedDelegate = MainActor.assumeIsolated { bootstrap() }
MainActor.assumeIsolated { NSApplication.shared.run() }
