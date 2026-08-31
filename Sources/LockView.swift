import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LockView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var pulse = false

    private var isBusy: Bool { store.phase == .unlocking }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    .frame(width: 168, height: 168)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    .frame(width: 132, height: 132)
                Circle()
                    .trim(from: 0, to: isBusy ? 0.72 : 1)
                    .stroke(
                        Palette.gradient(for: "accent"),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(pulse && isBusy ? 360 : 0))
                    .animation(
                        isBusy
                            ? .linear(duration: 1.1).repeatForever(autoreverses: false)
                            : Motion.gentle,
                        value: pulse
                    )
                    .shadow(color: Color(red: 0.29, green: 0.56, blue: 1).opacity(0.35), radius: 12)

                Image(systemName: "touchid")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Palette.gradient(for: "accent"))
                    .scaleEffect(pulse ? 1.04 : 0.98)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
            }
            .frame(height: 190)

            VStack(spacing: 7) {
                Text(Brand.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(lockSubtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            if let message = store.message {
                Text(message)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                store.unlock()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isBusy ? "ellipsis" : "touchid")
                        .font(.system(size: 14, weight: .semibold))
                    Text(isBusy ? "驗證中" : (EnclaveKey.hasBiometrics ? "使用 Touch ID 解鎖" : "使用登入密碼解鎖"))
                }
            }
            .buttonStyle(CapsuleButtonStyle())
            .disabled(isBusy)
            .opacity(isBusy ? 0.6 : 1)
            .padding(.top, 22)

            Spacer(minLength: 0)

            // A vault that cannot be opened would otherwise be a dead end:
            // settings live behind the unlock, so there would be no way to
            // bring in another file or move to a vault that does open.
            HStack(spacing: 14) {
                Button("匯入保險庫檔案") { importVault() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if store.vaults.count > 1 {
                    Menu("切換保險庫") {
                        Picker("", selection: Binding(
                            get: { store.currentVaultID },
                            set: { store.switchVault(to: $0) }
                        )) {
                            ForEach(store.vaults, id: \.id) { vault in
                                Text(vault.name).tag(vault.id)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)

            Text("內容以 Secure Enclave 加密保存")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.snappy, value: store.message)
        .onAppear { pulse = true }
    }

    private var lockSubtitle: String {
        store.isFirstRun ? "第一次啟用，驗證身分後建立保險庫" : "已鎖定 · 需要驗證身分才能開啟"
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

}
