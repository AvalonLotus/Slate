import AppKit
import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var store: VaultStore
    @State var draft: KeyItem
    let isNew: Bool
    let onClose: () -> Void

    @State private var revealed = false
    @State private var copied = false
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool
    @FocusState private var secretFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollContainer {
                VStack(spacing: 14) {
                    field(title: "名稱", systemImage: "tag.fill") {
                        TextField(draft.kind.namePlaceholder, text: $draft.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($nameFocused)
                    }

                    if draft.kind.showsAccountField {
                        field(title: draft.kind.accountLabel, systemImage: "person.fill") {
                            TextField(draft.kind.accountPlaceholder, text: $draft.username)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                        }
                    }

                    urlField

                    secretField

                    customFields

                    if !isNew {
                        metadata
                    }

                    saveButton

                    if !isNew {
                        deleteButton
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 18)
            }
        }
        // 面板平常一失焦就收起來。編輯到一半切去瀏覽器複製金鑰，正是最容易
        // 失焦的時候，而收起來等於把還沒存的內容丟掉——所以編輯期間比照對話框，
        // 面板留在原地等人回來。
        .onAppear {
            NotificationCenter.default.post(name: .slateModalBegan, object: nil)
            if isNew { nameFocused = true }
        }
        .onDisappear { NotificationCenter.default.post(name: .slateModalEnded, object: nil) }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(GlassButtonStyle())
            .keyboardShortcut(.cancelAction)

            IconTile(
                seed: draft.name,
                size: 30,
                fallbackSymbol: draft.kind.symbol,
                symbolOverride: draft.kind == .apiKey ? nil : draft.kind.symbol
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(isNew ? draft.kind.newTitle : draft.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(isNew ? "只保存在這台 Mac" : draft.subtitle)
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

    private var urlField: some View {
        field(title: "網址", systemImage: "link") {
            HStack(spacing: 8) {
                TextField("https://…", text: $draft.url)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                Button {
                    store.open(draft)
                } label: {
                    Image(systemName: "arrow.up.right")
                }
                .buttonStyle(GlassButtonStyle(size: 24))
                .disabled(draft.openableURL == nil)
                .help("在瀏覽器開啟")
            }
        }
    }

    private var secretLabel: String { draft.kind.valueLabel }

    private var secretField: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(secretLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                Spacer()
                Button {
                    withAnimation(Motion.pop) { revealed.toggle() }
                } label: {
                    Image(systemName: revealed ? "eye.slash.fill" : "eye.fill")
                }
                .buttonStyle(GlassButtonStyle(size: 24))
                .help(revealed ? "隱藏" : "顯示")

                Button {
                    store.copy(draft)
                    withAnimation(Motion.pop) { copied = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        withAnimation(Motion.pop) { copied = false }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc.fill")
                }
                .buttonStyle(GlassButtonStyle(size: 24))
                .disabled(draft.secret.isEmpty)
                .help("複製（45 秒後自動清空剪貼簿）")

                Button {
                    guard let text = NSPasteboard.general.string(forType: .string),
                          !text.isEmpty else { return }
                    draft.secret = text
                } label: {
                    Image(systemName: "arrow.down.doc.fill")
                }
                .buttonStyle(GlassButtonStyle(size: 24))
                .help("貼上，取代整個值")
            }
            .foregroundStyle(.secondary)

            Group {
                if revealed {
                    TextField(draft.kind.valuePlaceholder, text: $draft.secret, axis: .vertical)
                        .lineLimit(1...5)
                } else {
                    SecureField(draft.kind.valuePlaceholder, text: $draft.secret)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .cardBackground(radius: 12)
            .focused($secretFocused)
            // Taking focus selects the whole value: replacing a key outright is
            // what this field is opened for.
            .onChange(of: secretFocused) { _, focused in
                guard focused else { return }
                DispatchQueue.main.async {
                    _ = NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
            // Revealing swaps one field for the other, and focus does not
            // cross that swap.
            .onChange(of: revealed) { _, _ in
                DispatchQueue.main.async { secretFocused = true }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .cardBackground()
    }

    /// The only save in the editor, so it carries the keyboard path too.
    private var saveButton: some View {
        Button(action: save) {
            Text("儲存")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CapsuleButtonStyle(filled: false))
        .disabled(draft.secret.isEmpty && draft.name.isEmpty)
        .opacity(draft.secret.isEmpty && draft.name.isEmpty ? 0.45 : 1)
        .keyboardShortcut("s", modifiers: .command)
        .padding(.top, 4)
    }

    private func save() {
        store.save(draft)
        onClose()
    }

    /// 固定那四欄裝不下的東西。名稱自己打，值要不要遮自己決定。
    private var customFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("其他欄位")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                Spacer()
                Button {
                    withAnimation(Motion.pop) { draft.fields.append(CustomField()) }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(GlassButtonStyle(size: 24))
                .help("新增一欄")
            }
            .foregroundStyle(.secondary)

            ForEach($draft.fields) { $entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("欄位名稱", text: $entry.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))

                        Button {
                            withAnimation(Motion.pop) { $entry.isSecret.wrappedValue.toggle() }
                        } label: {
                            Image(systemName: entry.isSecret ? "eye.slash.fill" : "eye.fill")
                        }
                        .buttonStyle(GlassButtonStyle(size: 22))
                        .help(entry.isSecret ? "值會遮起來" : "值直接顯示")

                        Button {
                            withAnimation(Motion.pop) {
                                draft.fields.removeAll { $0.id == entry.id }
                            }
                        } label: {
                            Image(systemName: "trash.fill")
                        }
                        .buttonStyle(GlassButtonStyle(size: 22))
                        .help("刪掉這一欄")
                    }
                    .foregroundStyle(.secondary)

                    Group {
                        if entry.isSecret {
                            SecureField("值", text: $entry.value)
                        } else {
                            TextField("值", text: $entry.value, axis: .vertical)
                                .lineLimit(1...4)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .cardBackground(radius: 12)
                }
            }

            if draft.fields.isEmpty {
                Text("有什麼就加什麼：環境、到期日、專案代號、備註。名稱自己打。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func field<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
            }
            .foregroundStyle(.secondary)

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .cardBackground(radius: 12)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .cardBackground()
    }

    private var metadata: some View {
        HStack {
            Label(Self.formatter.string(from: draft.createdAt), systemImage: "calendar")
            Spacer()
            Label(Self.formatter.string(from: draft.updatedAt), systemImage: "clock.arrow.circlepath")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
    }

    private var deleteButton: some View {
        Button {
            if confirmingDelete {
                store.delete(draft)
                onClose()
            } else {
                withAnimation(Motion.pop) { confirmingDelete = true }
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(Motion.pop) { confirmingDelete = false }
                }
            }
        } label: {
            Text(confirmingDelete ? "再按一次確認" : "刪除")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CapsuleButtonStyle(tint: Color(red: 0.95, green: 0.33, blue: 0.33), filled: confirmingDelete))
        .padding(.top, 4)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()
}
