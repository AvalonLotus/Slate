import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var route: Route?
    @State private var vaultSheet: VaultSheet?
    @State private var vaultName = ""

    enum VaultSheet: Identifiable {
        case create
        case rename
        case delete

        var id: String {
            switch self {
            case .create: return "create"
            case .rename: return "rename"
            case .delete: return "delete"
            }
        }
    }

    enum Route: Identifiable {
        case editor(KeyItem, isNew: Bool)
        case settings

        var id: String {
            switch self {
            case .editor(let item, _): return item.id.uuidString
            case .settings: return "settings"
            }
        }
    }

    var body: some View {
        ZStack {
            if store.phase == .unlocked {
                VaultListView(
                    onSelect: { item in
                        withAnimation(Motion.snappy) { route = .editor(item, isNew: false) }
                    },
                    onCreate: {
                        withAnimation(Motion.snappy) { route = .editor(KeyItem(), isNew: true) }
                    },
                    onSettings: {
                        withAnimation(Motion.snappy) { route = .settings }
                    },
                    onNewVault: {
                        vaultName = ""
                        withAnimation(Motion.snappy) { vaultSheet = .create }
                    },
                    onRenameVault: {
                        vaultName = store.currentVaultName
                        withAnimation(Motion.snappy) { vaultSheet = .rename }
                    },
                    onDeleteVault: {
                        withAnimation(Motion.snappy) { vaultSheet = .delete }
                    }
                )
                .transition(.opacity)
                .blur(radius: route == nil ? 0 : 8)
                .opacity(route == nil ? 1 : 0)

                if let sheet = vaultSheet {
                    vaultSheetView(for: sheet)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(1)
                }

                if let route {
                    Group {
                        switch route {
                        case .editor(let item, let isNew):
                            EditorView(draft: item, isNew: isNew) {
                                withAnimation(Motion.snappy) { self.route = nil }
                            }
                        case .settings:
                            SettingsView {
                                withAnimation(Motion.snappy) { self.route = nil }
                            }
                        }
                    }
                    .id(route.id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            } else {
                LockView()
                    .transition(.opacity)
            }
        }
        .onChange(of: store.phase) { _, phase in
            if phase != .unlocked { route = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .keyVaultPanelWillHide)) { _ in
            route = nil
        }
    }
}

struct VaultNameSheet: View {
    let title: String
    let caption: String
    let confirmLabel: String
    @Binding var name: String
    let onFinish: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        SheetChrome {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(caption)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("名稱", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .cardBackground(radius: 12)
                .focused($focused)
                .onSubmit { onFinish(name) }

            HStack(spacing: 8) {
                Button("取消") { onFinish("") }
                    .buttonStyle(CapsuleButtonStyle(filled: false))
                Button(confirmLabel) { onFinish(name) }
                    .buttonStyle(CapsuleButtonStyle())
                    .disabled(name.isEmpty)
                    .opacity(name.isEmpty ? 0.45 : 1)
            }
        } onDismiss: {
            onFinish("")
        }
        .onAppear { focused = true }
    }
}

extension RootView {
    @ViewBuilder
    func vaultSheetView(for sheet: VaultSheet) -> some View {
        switch sheet {
        case .create:
            VaultNameSheet(
                title: "新增保險庫",
                caption: "每間公司一個，金鑰與備份密碼各自獨立",
                confirmLabel: "建立",
                name: $vaultName
            ) { name in
                withAnimation(Motion.snappy) { vaultSheet = nil }
                guard !name.isEmpty else { return }
                store.createVault(named: name)
            }
        case .rename:
            VaultNameSheet(
                title: "重新命名",
                caption: "只改顯示的名稱，裡面的內容不動",
                confirmLabel: "更名",
                name: $vaultName
            ) { name in
                withAnimation(Motion.snappy) { vaultSheet = nil }
                guard !name.isEmpty else { return }
                store.renameVault(store.currentVaultID, to: name)
            }
        case .delete:
            ConfirmSheet(
                title: "刪除「\(store.currentVaultName)」",
                caption: "這個保險庫裡的所有金鑰會一起消失，無法復原。",
                confirmLabel: "刪除"
            ) { confirmed in
                withAnimation(Motion.snappy) { vaultSheet = nil }
                if confirmed { store.deleteVault(store.currentVaultID) }
            }
        }
    }
}

struct ConfirmSheet: View {
    let title: String
    let caption: String
    let confirmLabel: String
    let onFinish: (Bool) -> Void

    var body: some View {
        SheetChrome {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(caption)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("取消") { onFinish(false) }
                    .buttonStyle(CapsuleButtonStyle(filled: false))
                Button(confirmLabel) { onFinish(true) }
                    .buttonStyle(CapsuleButtonStyle(
                        tint: Color(red: 0.95, green: 0.33, blue: 0.33), filled: true
                    ))
            }
        } onDismiss: {
            onFinish(false)
        }
    }
}

/// The dimmed backdrop and rounded panel every small dialog sits in.
struct SheetChrome<Content: View>: View {
    @ViewBuilder var content: Content
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.35))
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 14) { content }
                .padding(18)
                .frame(width: 260)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        }
    }
}

extension Notification.Name {
    static let keyVaultPanelWillHide = Notification.Name("KeyVaultPanelWillHide")
}
