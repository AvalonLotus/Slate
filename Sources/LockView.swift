import SwiftUI

struct LockView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var pulse = false
    @State private var restoring = false
    @State private var passphrase = ""

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

            if restoring || store.needsAdoption {
                VStack(spacing: 10) {
                    SecureField("備份密碼", text: $passphrase)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(width: 220)
                        .cardBackground(radius: 12)
                        .onSubmit(submitRestore)

                    HStack(spacing: 8) {
                        if !store.needsAdoption {
                            Button("取消") {
                                withAnimation(Motion.snappy) { restoring = false }
                                passphrase = ""
                            }
                            .buttonStyle(CapsuleButtonStyle(filled: false))
                        }

                        Button("用備份密碼開啟") { submitRestore() }
                            .buttonStyle(CapsuleButtonStyle())
                            .disabled(passphrase.isEmpty || isBusy)
                            .opacity(passphrase.isEmpty || isBusy ? 0.45 : 1)
                    }
                }
                .padding(.top, 22)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
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
            }

            Spacer(minLength: 0)

            if !restoring && !store.needsAdoption && store.restoreAvailable {
                Button("從備份還原") {
                    withAnimation(Motion.snappy) { restoring = true }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            }

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
        if store.needsAdoption {
            return "這台 Mac 還沒有加入這個保險庫\n輸入備份密碼即可加入"
        }
        return store.isFirstRun ? "第一次啟用，驗證身分後建立保險庫" : "已鎖定 · 需要驗證身分才能開啟"
    }

    private func submitRestore() {
        guard !passphrase.isEmpty else { return }
        store.adopt(withPassphrase: passphrase)
        passphrase = ""
        withAnimation(Motion.snappy) { restoring = false }
    }
}
