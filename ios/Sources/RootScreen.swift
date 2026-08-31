import SwiftUI

struct RootScreen: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        Group {
            if store.phase == .unlocked {
                VaultScreen()
            } else {
                LockScreen()
            }
        }
        .animation(Motion.snappy, value: store.phase)
    }
}

struct LockScreen: View {
    @EnvironmentObject private var store: VaultStore
    @State private var restoring = false
    @State private var passphrase = ""
    @State private var pulse = false

    private var isBusy: Bool { store.phase == .unlocking }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .trim(from: 0, to: isBusy ? 0.72 : 1)
                    .stroke(Palette.gradient(for: "accent"), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 104, height: 104)
                    .rotationEffect(.degrees(pulse && isBusy ? 360 : 0))
                    .animation(
                        isBusy ? .linear(duration: 1.1).repeatForever(autoreverses: false) : Motion.gentle,
                        value: pulse
                    )
                Image(systemName: "faceid")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Palette.gradient(for: "accent"))
            }
            .frame(height: 180)

            Text(Brand.name)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(store.isFirstRun ? "第一次啟用，用生物辨識建立保險庫" : "已鎖定")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            if let message = store.message {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
            }

            if restoring {
                VStack(spacing: 12) {
                    SecureField("備份密碼", text: $passphrase)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .frame(maxWidth: 260)
                    Button("用備份密碼開啟") {
                        store.adopt(withPassphrase: passphrase)
                        passphrase = ""
                        restoring = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(passphrase.isEmpty || isBusy)
                    Button("取消") { restoring = false }
                        .font(.footnote)
                }
                .padding(.top, 24)
            } else {
                Button {
                    store.unlock()
                } label: {
                    Label(isBusy ? "驗證中" : "解鎖", systemImage: "faceid")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isBusy)
                .padding(.top, 24)
            }

            Spacer()

            if !restoring && store.restoreAvailable {
                Button("從備份還原") { restoring = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            pulse = true
            store.unlock()
        }
    }
}
