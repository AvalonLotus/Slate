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

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollContainer {
                VStack(spacing: 14) {
                    if isNew {
                        kindPicker
                    }

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

                    secretField

                    if !isNew {
                        metadata
                        deleteButton
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 18)
            }
        }
        .onAppear { if isNew { nameFocused = true } }
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

            Button("儲存") {
                store.save(draft)
                onClose()
            }
            .buttonStyle(CapsuleButtonStyle())
            .disabled(draft.secret.isEmpty && draft.name.isEmpty)
            .opacity(draft.secret.isEmpty && draft.name.isEmpty ? 0.45 : 1)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private var kindPicker: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(ItemKind.allCases, id: \.self) { kind in
                Button {
                    withAnimation(Motion.pop) { draft.kind = kind }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Text(kind.label)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(draft.kind == kind
                                ? AnyShapeStyle(Palette.gradient(for: "accent"))
                                : AnyShapeStyle(Color.primary.opacity(0.07)))
                    )
                    .foregroundStyle(draft.kind == kind ? .white : .secondary)
                }
                .buttonStyle(.plain)
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
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
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
            HStack(spacing: 6) {
                Image(systemName: "trash.fill")
                Text(confirmingDelete ? "再按一次確認刪除" : "刪除這筆")
            }
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
