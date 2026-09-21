import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted around modal file dialogs so the floating panel does not treat
    /// losing key status as a reason to hide and lock.
    static let slateModalBegan = Notification.Name("SlateModalBegan")
    static let slateModalEnded = Notification.Name("SlateModalEnded")
}

/// Whether Slate comes back after a restart is the system's fact, not a
/// preference of ours: the switch reads the login item database itself, so
/// switching Slate off in System Settings also shows up here.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var failure: String?

    var isEnabled: Bool { status == .enabled }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        refresh()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: VaultStore
    let onClose: () -> Void

    @StateObject private var updates = UpdateChecker()
    @StateObject private var login = LoginItem()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollContainer {
                VStack(spacing: 14) {
                    startupSection
                    transferSection
                    updateSection
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 18)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(GlassButtonStyle())
            .keyboardShortcut(.cancelAction)

            BrandMark(size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("設定")
                    .font(.system(size: 15, weight: .semibold))
                Text(store.currentVaultName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Start at login

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("開機時啟動", systemImage: "power")

            Text("登入 macOS 後自己開起來，桌面卡片回到原本的位置。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("開啟") { login.set(true) }
                    .buttonStyle(CapsuleButtonStyle(filled: login.isEnabled))

                Button("關閉") { login.set(false) }
                    .buttonStyle(CapsuleButtonStyle(filled: !login.isEnabled))
            }

            // Registering succeeds even when the user has switched Slate off in
            // System Settings; only that panel can turn it back on.
            if login.status == .requiresApproval {
                Text("系統設定裡把 Slate 關掉了，要在那邊重新允許。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.95, green: 0.62, blue: 0.25))
                    .fixedSize(horizontal: false, vertical: true)

                Button("開啟系統設定") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(CapsuleButtonStyle(filled: false))
            } else if let failure = login.failure {
                Text(failure)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.95, green: 0.62, blue: 0.25))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        // Every section is one column: a short card must not shrink to its
        // content while the talkative ones stretch.
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .onAppear { login.refresh() }
    }

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("轉移至其他裝置", systemImage: "arrow.left.arrow.right")

            Text("將「\(store.currentVaultName)」匯出成一個檔案，另一台匯入後直接以自己的驗證方式開啟。該檔可直接讀取，匯入後請刪除。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("匯出保險庫") { exportVault() }
                    .buttonStyle(CapsuleButtonStyle())

                Button("匯入") { importVault() }
                    .buttonStyle(CapsuleButtonStyle(filled: false))
            }

        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        // Every section is one column: a short card must not shrink to its
        // content while the talkative ones stretch.
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Updates

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("版本", systemImage: "arrow.down.circle.fill")

            HStack(spacing: 10) {
                Text(updateDescription)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button(updateLabel) {
                    updates.install()
                }
                .buttonStyle(CapsuleButtonStyle(filled: updateAvailable))
                .disabled(!updateActionable)
                .opacity(updateActionable ? 1 : 0.45)
                .fixedSize()
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        // Every section is one column: a short card must not shrink to its
        // content while the talkative ones stretch.
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .onAppear { updates.check() }
    }

    private var updateAvailable: Bool {
        if case .available = updates.state { return true }
        return false
    }

    /// The button is only ever for taking an update: with nothing to install
    /// it stays greyed out rather than inviting a pointless press.
    private var updateActionable: Bool { updateAvailable }

    /// A failed check reads the same as a successful one that found nothing:
    /// either way there is no update to take, and the reason is not the
    /// reader's problem to solve.
    private var updateLabel: String {
        switch updates.state {
        case .available(let version, _): return "更新至 ver. \(version)"
        case .checking: return "檢查中"
        case .installing: return "更新中"
        case .upToDate, .failed, .idle: return "最新版本"
        }
    }

    private var updateDescription: String {
        switch updates.state {
        case .available(let version, _):
            return "目前 ver. \(updates.currentVersion)，可更新至 ver. \(version)，更新後會自動重新啟動。"
        case .installing:
            return "正在下載並驗證。"
        case .failed(let reason):
            return "目前 ver. \(updates.currentVersion)。\(reason)。"
        default:
            return "目前 ver. \(updates.currentVersion)。"
        }
    }

    private func exportVault() {
        NotificationCenter.default.post(name: .slateModalBegan, object: nil)
        defer { NotificationCenter.default.post(name: .slateModalEnded, object: nil) }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [VaultBundle.contentType]
        // No extension here: the panel appends the one the type declares, and
        // spelling it out as well is what produced name.slatevault.slatevault.
        panel.nameFieldStringValue = store.currentVaultName
        panel.message = "存成一個檔案，傳到另一台 Mac"
        if panel.runModal() == .OK, let url = panel.url {
            store.exportBundle(to: url)
        }
    }

    private func importVault() {
        NotificationCenter.default.post(name: .slateModalBegan, object: nil)
        defer { NotificationCenter.default.post(name: .slateModalEnded, object: nil) }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [VaultBundle.contentType]
        panel.message = "選擇從另一台匯出的 Slate 檔案"
        if panel.runModal() == .OK, let url = panel.url {
            store.importBundle(from: url)
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(.secondary)
    }
}
