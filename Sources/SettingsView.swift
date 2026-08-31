import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted around modal file dialogs so the floating panel does not treat
    /// losing key status as a reason to hide and lock.
    static let slateModalBegan = Notification.Name("SlateModalBegan")
    static let slateModalEnded = Notification.Name("SlateModalEnded")
}

struct SettingsView: View {
    @EnvironmentObject private var store: VaultStore
    let onClose: () -> Void

    @AppStorage("UnlockWindowMinutes") private var windowMinutes = UnlockWindow.choices[0]
    @State private var passphrase = ""
    @State private var passphraseRepeat = ""
    @State private var revealPassphrase = false
    @StateObject private var updates = UpdateChecker()
    @State private var confirmingRemoval = false
    @State private var passphraseExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollContainer {
                VStack(spacing: 14) {
                    passphraseSection
                    unlockSection
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

    // MARK: - Unlock window

    private var unlockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("免驗證時間", systemImage: "touchid")

            HStack(spacing: 8) {
                ForEach(UnlockWindow.choices, id: \.self) { minutes in
                    Button("\(minutes) 分鐘") { windowMinutes = minutes }
                        .buttonStyle(CapsuleButtonStyle(filled: windowMinutes == minutes))
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        // Every section is one column: a short card must not shrink to its
        // content while the talkative ones stretch.
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Master passphrase

    private var passphraseValid: Bool {
        passphrase.count >= 8 && passphrase == passphraseRepeat
    }

    /// Nothing left to do here only when every vault carries the passphrase.
    private var passphraseSettled: Bool {
        store.hasPassphrase && store.vaultsMissingPassphrase.isEmpty
    }

    /// Typing a passphrase blind is how people mistype it, so the field can be
    /// shown. One toggle drives both, since they have to match anyway.
    private func passphraseField(
        _ prompt: String,
        text: Binding<String>,
        showsToggle: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Group {
                if revealPassphrase {
                    TextField(prompt, text: text)
                } else {
                    SecureField(prompt, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))

            if showsToggle {
                Button {
                    revealPassphrase.toggle()
                } label: {
                    Image(systemName: revealPassphrase ? "eye.slash.fill" : "eye.fill")
                }
                .buttonStyle(GlassButtonStyle(size: 24))
                .help(revealPassphrase ? "隱藏" : "顯示")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .cardBackground(radius: 12)
    }

    private var passphraseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Once it is set there is nothing to do here day to day, so the
            // section folds to its title and opens only when asked.
            if passphraseSettled {
                Button {
                    withAnimation(Motion.snappy) { passphraseExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        sectionTitle("備份密碼", systemImage: "lock.rectangle.stack.fill")

                        Text("已設定")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(passphraseExpanded ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                sectionTitle("備份密碼", systemImage: "lock.rectangle.stack.fill")
            }

            if !passphraseSettled || passphraseExpanded {
                Text("所有保險庫共用這一組，匯出與還原時使用。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !store.hasPassphrase, store.passphraseExistsElsewhere {
                    Text("其他保險庫已經有備份密碼，這裡輸入同一組就會全部對齊。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.95, green: 0.62, blue: 0.25))
                        .fixedSize(horizontal: false, vertical: true)
                } else if !store.vaultsMissingPassphrase.isEmpty, store.hasPassphrase {
                    Text("「\(store.vaultsMissingPassphrase.joined(separator: "」「"))」還沒套用，重新輸入一次會一併補上。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.95, green: 0.62, blue: 0.25))
                        .fixedSize(horizontal: false, vertical: true)
                }

                passphraseField(
                    store.hasPassphrase ? "輸入新的備份密碼可更換" : "備份密碼",
                    text: $passphrase,
                    showsToggle: true
                )

                passphraseField("再輸入一次", text: $passphraseRepeat, showsToggle: false)

                HStack(spacing: 8) {
                    Button(store.hasPassphrase ? "更換備份密碼" : "設定備份密碼") {
                        withAnimation(Motion.snappy) {
                            store.setPassphrase(passphrase)
                            passphrase = ""
                            passphraseRepeat = ""
                            revealPassphrase = false
                            passphraseExpanded = false
                        }
                    }
                    .buttonStyle(CapsuleButtonStyle())
                    .disabled(!passphraseValid)
                    .opacity(passphraseValid ? 1 : 0.45)

                    if store.hasPassphrase {
                        Button(confirmingRemoval ? "確認移除？" : "移除") {
                            if confirmingRemoval {
                                withAnimation(Motion.snappy) {
                                    store.removePassphrase()
                                    confirmingRemoval = false
                                }
                            } else {
                                confirmingRemoval = true
                                Task {
                                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                                    confirmingRemoval = false
                                }
                            }
                        }
                        .buttonStyle(CapsuleButtonStyle(
                            tint: Color(red: 0.95, green: 0.33, blue: 0.33),
                            filled: confirmingRemoval
                        ))
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        // Every section is one column: a short card must not shrink to its
        // content while the talkative ones stretch.
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
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
                    .disabled(!store.hasPassphrase)
                    .opacity(store.hasPassphrase ? 1 : 0.45)

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
