import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 身分驗證過了，但選中的保險庫沒有這台機器的鑰匙。
///
/// 這一頁存在的理由：這是保險庫層的問題，不是身分層的。人已經證明過自己是誰，
/// 把他退回鎖定畫面等於要他再驗證一次，而再驗證幾次也開不了這個保險庫——真正
/// 需要的是換一個保險庫，或匯入一份帶得動鑰匙的檔案，這兩件事都得在門內才做得到。
struct UnavailableView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                    .frame(width: 132, height: 132)
                Image(systemName: "key.slash")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 150)

            VStack(spacing: 7) {
                Text(store.currentVaultName)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text("這個保險庫沒有這台 Mac 的鑰匙")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("到原本那台 Mac 匯出一份，拿到這台匯入即可；\n匯入的檔案自己帶鑰匙，不需要任何密碼。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 28)

            Button("匯入保險庫檔案") { importVault() }
                .buttonStyle(CapsuleButtonStyle())
                .padding(.top, 22)

            Spacer(minLength: 0)

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
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
