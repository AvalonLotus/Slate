import AppKit
import SwiftUI

@MainActor
func render<Content: View>(
    _ view: Content,
    name: String,
    dark: Bool,
    directory: URL,
    width: CGFloat = Metrics.panelWidth,
    height: CGFloat = Metrics.panelHeight
) {
    let renderer = ImageRenderer(
        content: view
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .fill(dark ? Color(white: 0.13) : Color(white: 0.93))
            )
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .padding(20)
            .background(dark ? Color(white: 0.05) : Color(white: 0.8))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.staticRendering, true)
            .environmentObject(WindowDragProxy())
    )
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("failed: \(name)")
        return
    }
    let url = directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
    try? png.write(to: url)
    print("wrote \(url.lastPathComponent)")
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let samples: [KeyItem] = [
    KeyItem(kind: .login, name: "公司信箱", username: "someone@example.com", secret: "correct-horse-battery"),
    KeyItem(kind: .token, name: "粉專權杖", username: "1000000000000000", secret: "EXAMPLE-token-value"),
    KeyItem(kind: .identifier, name: "頻道 ID", secret: "2000000000"),
    KeyItem(name: "正式環境", secret: "EXAMPLE-api-key-0001"),
    KeyItem(name: "模型服務", secret: "EXAMPLE-api-key-0002"),
    KeyItem(name: "付款串接", secret: "EXAMPLE-api-key-0003"),
    KeyItem(name: "物件儲存", secret: "EXAMPLE-api-key-0004"),
    KeyItem(name: "部署權杖", secret: "EXAMPLE-token-0005"),
]

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)

    for dark in [true, false] {
        application.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let locked = VaultStore(previewPhase: .locked, previewItems: [])
        render(LockView().environmentObject(locked), name: "01-lock", dark: dark, directory: output)

        let busy = VaultStore(previewPhase: .unlocking, previewItems: [])
        render(LockView().environmentObject(busy), name: "02-unlocking", dark: dark, directory: output)

        let filled = VaultStore(previewPhase: .unlocked, previewItems: samples)
        render(
            VaultListView(onSelect: { _ in }, onCreate: {}, onSettings: {}, onNewVault: {}, onRenameVault: {}, onDeleteVault: {}).environmentObject(filled),
            name: "03-list", dark: dark, directory: output
        )

        let empty = VaultStore(previewPhase: .unlocked, previewItems: [])
        render(
            VaultListView(onSelect: { _ in }, onCreate: {}, onSettings: {}, onNewVault: {}, onRenameVault: {}, onDeleteVault: {}).environmentObject(empty),
            name: "04-empty", dark: dark, directory: output
        )

        render(
            EditorView(draft: samples[0], isNew: false, onClose: {}).environmentObject(filled),
            name: "05-editor", dark: dark, directory: output
        )

        render(
            EditorView(draft: KeyItem(), isNew: true, onClose: {}).environmentObject(filled),
            name: "06-new", dark: dark, directory: output
        )

        render(
            SettingsView(onClose: {}).environmentObject(filled),
            name: "09-settings", dark: dark, directory: output
        )

        let secured = VaultStore(previewPhase: .unlocked, previewItems: samples, previewHasPassphrase: true)
        render(
            SettingsView(onClose: {}).environmentObject(secured),
            name: "11-settings-secured", dark: dark, directory: output
        )

        render(
            EditorView(draft: KeyItem(kind: .login), isNew: true, onClose: {}).environmentObject(filled),
            name: "10-new-login", dark: dark, directory: output
        )

        render(
            DesktopFace().environmentObject(locked),
            name: "07-card-locked", dark: dark, directory: output,
            width: Metrics.cardWidth, height: Metrics.cardCollapsedHeight
        )

        render(
            RootView().environmentObject(filled),
            name: "08-card-open", dark: dark, directory: output,
            width: Metrics.cardWidth, height: Metrics.cardExpandedHeight
        )
    }
}
