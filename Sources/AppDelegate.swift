import AppKit
import Carbon.HIToolbox

/// The agent answers on its own queue, so anything touching the store has to
/// hop to the main thread first. assumeIsolated would only trap there.
private func onMainThread<T>(_ work: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { work() }
    }
    return DispatchQueue.main.sync { MainActor.assumeIsolated { work() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = VaultStore()
    private var statusItem: NSStatusItem!
    private var panel: PanelController!
    private var card: DesktopCardController!
    private var hotKey: HotKey?
    private let agent = AgentServer()

    /// The write half of the agent protocol. Names identify entries, because
    /// that is what a caller knows; ids never leave the app.
    private func applyWrite(_ request: AgentRequest) -> AgentResponse {
        func find(_ name: String) -> KeyItem? {
            let target = name.lowercased()
            return store.items.first {
                !$0.isDeleted && $0.displayName.lowercased() == target
            }
        }

        guard let name = request.name, !name.isEmpty else { return .failure("missing name") }

        switch request.command {
        case "add":
            guard let value = request.value, !value.isEmpty else { return .failure("missing value") }
            guard find(name) == nil else { return .failure("\(name) 已經存在，要改值請用 set") }
            let kind = request.kind.flatMap(ItemKind.init(rawValue:)) ?? .apiKey
            let item = KeyItem(kind: kind, name: name, username: request.account ?? "", secret: value)
            _ = store.save(item)
            return AgentResponse(ok: true, value: name)

        case "set":
            guard let value = request.value, !value.isEmpty else { return .failure("missing value") }
            guard let item = find(name) else { return .failure("not found: \(name)") }
            store.replaceSecret(of: item, with: value, detail: request.detail ?? "由命令列更新")
            return AgentResponse(ok: true, value: name)

        case "rename":
            guard let newName = request.newName, !newName.isEmpty else { return .failure("missing new name") }
            guard var item = find(name) else { return .failure("not found: \(name)") }
            item.name = newName
            _ = store.save(item)
            return AgentResponse(ok: true, value: newName)

        case "kind":
            guard let raw = request.kind, let kind = ItemKind(rawValue: raw) else {
                return .failure("kind 只能是 apiKey、token、identifier、login")
            }
            guard var item = find(name) else { return .failure("not found: \(name)") }
            item.kind = kind
            _ = store.save(item)
            return AgentResponse(ok: true, value: kind.label)

        case "field":
            guard let wanted = request.field, !wanted.isEmpty else { return .failure("missing field") }
            guard let value = request.value, !value.isEmpty else { return .failure("missing value") }
            guard var item = find(name) else { return .failure("not found: \(name)") }
            if let index = item.fields.firstIndex(where: {
                $0.name.lowercased() == wanted.lowercased()
            }) {
                // 已經有這一欄就只換值，遮不遮維持原樣。
                item.fields[index].value = value
            } else {
                item.fields.append(CustomField(name: wanted, value: value))
            }
            _ = store.save(item)
            return AgentResponse(ok: true, value: wanted)

        case "id":
            guard var item = find(name) else { return .failure("not found: \(name)") }
            item.username = request.account ?? ""
            _ = store.save(item)
            return AgentResponse(ok: true, value: item.username)

        case "url":
            guard var item = find(name) else { return .failure("not found: \(name)") }
            item.url = request.url ?? ""
            _ = store.save(item)
            return AgentResponse(ok: true, value: item.url)

        default:
            return .failure("unknown write: \(request.command)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        takeOverFromOtherInstances()
        AgentProtocol.deleteHandler = { [weak self] name in
            guard let self else { return false }
            return onMainThread {
                guard let item = self.store.items.first(where: { $0.displayName == name }) else {
                    return false
                }
                self.store.delete(item)
                return true
            }
        }
        AgentProtocol.mutateHandler = { [weak self] request in
            guard let self else { return .failure("app unavailable") }
            return onMainThread { self.applyWrite(request) }
        }
        AgentProtocol.importHandler = { [weak self] path in
            guard let self else { return "app unavailable" }
            return onMainThread {
                self.store.importFile(at: URL(fileURLWithPath: path))
                return self.store.message ?? "已匯入"
            }
        }
        AgentProtocol.unlockHandler = { [weak self] in
            self?.unlockForAgent() ?? false
        }
        // 保險庫開好之前不開 socket。遷移期間換金鑰，這時候讓任何人進來開一次
        // 保險庫，舊金鑰就會卡進 DeviceKey 的快取，換完之後全部打不開。
        // 舊格式的安全區金鑰還在的話先換掉，那是最後一次需要你驗證。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if EnclaveFormat.needsMigration {
                onMainThread { NSApp.activate(ignoringOtherApps: true) }
                do {
                    try EnclaveMigration.run()
                } catch {
                    let reason = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    onMainThread { self?.store.message = "改成免驗證讀取沒有完成：\(reason)" }
                }
            }
            onMainThread {
                self?.store.openVault()
                self?.agent.start()
            }
        }
        panel = PanelController(store: store)
        card = DesktopCardController(store: store)
        panel.lockOnHide = { [weak self] in !(self?.card.isExpanded ?? false) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: Brand.symbol, accessibilityDescription: Brand.name)
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.togglePanel()
        }

        // A sleeping or locked Mac ends the unlock window: whoever wakes it up
        // has to prove who they are again. It does not discard what is already
        // open — the screen going dark is not a request to cut off the scripts
        // and apps on this machine that are mid-conversation with the vault.
        // Only the lock button (⌘L) really closes it.
        let seal: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.store.lock() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: seal
        )
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main, using: seal
        )

        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.togglePanel()
            }
        }
    }

    /// Opens the vault for the command line. `slate` used to open it inside
    /// its own process whenever this app was locked, which cost one Touch ID
    /// per invocation — reading eight keys meant eight prompts. Asking here
    /// instead means one unlock covers every read that follows, because the
    /// device key stays cached for the length of the unlock window.
    ///
    /// Runs on the agent queue and blocks it until the sheet is answered, so
    /// requests arriving meanwhile queue up behind this one and then find the
    /// vault already open. What it wins lasts until the vault is locked
    /// outright: hiding the panel only takes the contents off the screen.
    nonisolated private func unlockForAgent() -> Bool {
        if SecretSnapshot.shared.isUnlocked { return true }

        // 沒有面板可跳，也不該跳：這條路上沒有人，只有腳本。開檔案而已。
        onMainThread { self.store.openVault() }

        // 這條路跑在 socket 自己的佇列上：空等會把後面每一個請求一起卡住。
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if SecretSnapshot.shared.isUnlocked { return true }
            if onMainThread({ self.store.openFailed }) { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        agent.stop()
    }

    /// Two copies would each draw their own desktop card; the newest one wins.
    private func takeOverFromOtherInstances() {
        let mine = ProcessInfo.processInfo.processIdentifier
        let executable = Bundle.main.executableURL?.lastPathComponent
        for app in NSWorkspace.shared.runningApplications
        where app.processIdentifier != mine && app.executableURL?.lastPathComponent == executable {
            app.terminate()
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        panel.toggle(relativeTo: statusItem.button)
    }

    /// The only dispatch point for ⌘V, ⌘A, ⌘C and ⌘X is a main menu key
    /// equivalent, so an app that never assigns one leaves its text fields
    /// unable to paste or select all. Items keep a nil target and reach the
    /// field editor through the responder chain.
    private func installEditMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "結束 \(Brand.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "編輯")
        edit.addItem(withTitle: "還原", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪下", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷貝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "貼上", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全選", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        NSApp.mainMenu = main
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "開啟面板　⌥⌘K", action: #selector(togglePanelAction), keyEquivalent: "")
            .target = self
        let cardItem = menu.addItem(withTitle: "在桌面顯示卡片", action: #selector(toggleCard), keyEquivalent: "")
        cardItem.target = self
        cardItem.state = card.isVisible ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "結束", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePanelAction() {
        togglePanel()
    }

    @objc private func toggleCard() {
        card.toggle()
    }
}
