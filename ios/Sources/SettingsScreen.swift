import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var passphrase = ""
    @State private var passphraseRepeat = ""

    private var passphraseValid: Bool {
        passphrase.count >= 8 && passphrase == passphraseRepeat
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(store.hasPassphrase ? "輸入新的備份密碼可更換" : "備份密碼", text: $passphrase)
                    SecureField("再輸入一次", text: $passphraseRepeat)
                    Button(store.hasPassphrase ? "更換備份密碼" : "設定備份密碼") {
                        store.setPassphrase(passphrase)
                        passphrase = ""
                        passphraseRepeat = ""
                    }
                    .disabled(!passphraseValid)
                } header: {
                    Text("備份密碼")
                } footer: {
                    Text(store.hasPassphrase
                         ? "已設定。把保險庫檔案複製到新裝置後，輸入這組密碼就能開啟。"
                         : "平常用生物辨識，這組密碼只在新裝置還原時使用。至少 8 個字。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
