import SwiftUI

struct VaultListView: View {
    @EnvironmentObject private var store: VaultStore
    @FocusState private var searchFocused: Bool
    let onSelect: (KeyItem) -> Void
    let onCreate: () -> Void
    let onSettings: () -> Void
    let onNewVault: () -> Void
    let onRenameVault: () -> Void
    let onDeleteVault: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 10)

            if store.items.isEmpty {
                emptyState
            } else if store.filtered.isEmpty {
                noMatchState
            } else {
                ScrollContainer {
                    LazyVStack(spacing: 8) {
                        ForEach(store.filtered) { item in
                            KeyRow(item: item, onOpen: { onSelect(item) }, onCopy: { store.copy(item) })
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 14)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            BrandMark(size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Menu {
                    // A Picker gives the native checkmark column, so rows line
                    // up instead of shifting with the text.
                    Picker("", selection: Binding(
                        get: { store.currentVaultID },
                        set: { store.switchVault(to: $0) }
                    )) {
                        ForEach(store.vaults) { vault in
                            Text(vault.name).tag(vault.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    Divider()
                    Button("新增保險庫") { onNewVault() }
                    Button("重新命名") { onRenameVault() }

                    if store.vaults.count > 1 {
                        Divider()
                        // The name stays here: this is the one action worth
                        // spelling out before it happens.
                        Button("刪除「\(store.currentVaultName)」") { onDeleteVault() }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(store.currentVaultName)
                            .font(.system(size: 15, weight: .semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Text("\(store.visibleItems.count) 筆 · 已解鎖")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 0)
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(GlassButtonStyle())
            .help("設定")
            Button(action: { store.lockNow() }) {
                Image(systemName: "lock.fill")
            }
            .buttonStyle(GlassButtonStyle())
            .keyboardShortcut("l", modifiers: .command)
            .help("立即鎖定　⌘L")
            Button(action: onCreate) {
                Image(systemName: "plus")
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
            .keyboardShortcut("n", modifiers: .command)
            .help("新增金鑰　⌘N")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜尋", text: $store.search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if !store.search.isEmpty {
                Button {
                    store.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous).fill(Color.primary.opacity(0.07))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "key.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("尚無項目")
                .font(.system(size: 14, weight: .medium))
            Text("驗證後即可取用")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
            Button(action: onCreate) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("新增")
                }
            }
            .buttonStyle(CapsuleButtonStyle())
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var noMatchState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("找不到「\(store.search)」")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct KeyRow: View {
    let item: KeyItem
    let onOpen: () -> Void
    let onCopy: () -> Void

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 11) {
            IconTile(
                seed: item.name,
                fallbackSymbol: item.kind.symbol,
                symbolOverride: item.kind == .apiKey ? nil : item.kind.symbol
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(trailingLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                // Room for the hover controls even when the row shows no text.
                .frame(minWidth: 54, alignment: .trailing)
                .opacity(hovering ? 0 : 1)
                .overlay(alignment: .trailing) {
                    HStack(spacing: 6) {
                        Button(action: copy) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc.fill")
                        }
                        .buttonStyle(GlassButtonStyle(size: 25))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .opacity(hovering ? 1 : 0)
                }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(hovering ? 0.16 : 0.07), lineWidth: 0.6)
        )
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { value in
            withAnimation(Motion.pop) { hovering = value }
        }
        .contextMenu {
            Button("複製金鑰", action: copy)
            Button("編輯", action: onOpen)
        }
    }

    /// Rows stay quiet: a secret shows nothing at all, while an ID is not a
    /// secret and shows as it is.
    private var trailingLabel: String {
        item.kind.isSecret ? "" : item.secret
    }

    private func copy() {
        onCopy()
        withAnimation(Motion.pop) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(Motion.pop) { copied = false }
        }
    }
}
