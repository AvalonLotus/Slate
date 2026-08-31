import SwiftUI

struct VaultScreen: View {
    @EnvironmentObject private var store: VaultStore
    @State private var editing: EditorTarget?
    @State private var showingSettings = false
    @State private var copied: UUID?

    struct EditorTarget: Identifiable {
        let item: KeyItem
        let isNew: Bool
        var id: UUID { item.id }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.filtered) { item in
                    Button {
                        editing = EditorTarget(item: item, isNew: false)
                    } label: {
                        row(for: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(item)
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            store.copy(item)
                            copied = item.id
                        } label: {
                            Label("複製", systemImage: "doc.on.doc")
                        }
                        .tint(Palette.accent)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $store.search, prompt: "搜尋")
            .overlay {
                if store.visibleItems.isEmpty {
                    ContentUnavailableView(
                        "還沒有任何項目",
                        systemImage: "key.slash",
                        description: Text("把 API Key 和帳號密碼收進來")
                    )
                }
            }
            .navigationTitle(Brand.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.lockNow() } label: {
                        Image(systemName: "lock.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = EditorTarget(item: KeyItem(), isNew: true)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { target in
                ItemEditor(draft: target.item, isNew: target.isNew)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsScreen().environmentObject(store)
            }
        }
    }

    private func row(for item: KeyItem) -> some View {
        HStack(spacing: 12) {
            ItemTile(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if copied == item.id {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
            } else {
                Text(masked(item))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func masked(_ item: KeyItem) -> String {
        guard item.kind == .apiKey, item.secret.count > 6 else { return "••••••" }
        return "••••" + item.secret.suffix(4)
    }
}

struct ItemEditor: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: KeyItem
    let isNew: Bool
    @State private var revealed = false

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Picker("類型", selection: $draft.kind) {
                        ForEach(ItemKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("名稱", text: $draft.name)
                    TextField("服務", text: $draft.provider)
                    if draft.kind == .login {
                        TextField("帳號", text: $draft.username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                    }
                }

                Section(draft.kind == .apiKey ? "API Key" : "密碼") {
                    HStack {
                        if revealed {
                            TextField("", text: $draft.secret, axis: .vertical)
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("", text: $draft.secret)
                                .font(.body.monospaced())
                        }
                        Button {
                            revealed.toggle()
                        } label: {
                            Image(systemName: revealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    Button {
                        store.copy(draft)
                    } label: {
                        Label("複製", systemImage: "doc.on.doc")
                    }
                    .disabled(draft.secret.isEmpty)
                }

                Section("備註") {
                    TextField("", text: $draft.note, axis: .vertical)
                        .lineLimit(1...5)
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            store.delete(draft)
                            dismiss()
                        } label: {
                            Label("刪除這筆", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "新增" : draft.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        store.save(draft)
                        dismiss()
                    }
                    .disabled(draft.name.isEmpty && draft.secret.isEmpty)
                }
            }
        }
    }
}
