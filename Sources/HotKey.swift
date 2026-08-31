import Carbon.HIToolbox
import Foundation

/// Minimal Carbon hot-key registration: works without accessibility permission.
final class HotKey {
    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    nonisolated(unsafe) private static var installed = false

    private var reference: EventHotKeyRef?
    private let identifier: UInt32

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        HotKey.installDispatcher()
        identifier = HotKey.nextID
        HotKey.nextID += 1
        HotKey.handlers[identifier] = handler

        let hotKeyID = EventHotKeyID(signature: OSType(0x4B565431), id: identifier)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        HotKey.handlers[identifier] = nil
    }

    private static func installDispatcher() {
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if let handler = HotKey.handlers[hotKeyID.id] {
                    DispatchQueue.main.async(execute: handler)
                }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}
