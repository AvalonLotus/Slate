import SwiftUI

@main
struct SlateApp: App {
    @StateObject private var store = VaultStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootScreen()
                .environmentObject(store)
                .tint(Palette.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            // Anything but active means the vault should not stay open.
            if phase != .active { store.lock() }
        }
    }
}

enum Palette {
    static let accent = Color(red: 0.29, green: 0.56, blue: 1.0)
    static let gold = Color(red: 0.96, green: 0.80, blue: 0.44)

    private static let tiles: [[Color]] = [
        [Color(red: 0.29, green: 0.56, blue: 1.00), Color(red: 0.35, green: 0.34, blue: 0.94)],
        [Color(red: 0.40, green: 0.78, blue: 0.38), Color(red: 0.19, green: 0.62, blue: 0.41)],
        [Color(red: 1.00, green: 0.60, blue: 0.20), Color(red: 0.96, green: 0.38, blue: 0.27)],
        [Color(red: 0.85, green: 0.36, blue: 0.78), Color(red: 0.55, green: 0.29, blue: 0.90)],
        [Color(red: 0.20, green: 0.74, blue: 0.85), Color(red: 0.16, green: 0.48, blue: 0.83)],
        [Color(red: 0.98, green: 0.44, blue: 0.52), Color(red: 0.85, green: 0.24, blue: 0.44)],
        [Color(red: 0.55, green: 0.60, blue: 0.68), Color(red: 0.33, green: 0.38, blue: 0.47)],
    ]

    static func gradient(for seed: String) -> LinearGradient {
        var hash = 5381
        for byte in seed.lowercased().utf8 { hash = (hash &* 33) &+ Int(byte) }
        let index = seed == "accent" ? 0 : abs(hash) % tiles.count
        return LinearGradient(
            colors: tiles[index],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// The app mark, drawn rather than shipped as an asset so it stays in step
/// with the macOS build.
struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(white: 0.36), Color(white: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .strokeBorder(Palette.gold.opacity(0.9), lineWidth: max(0.7, size * 0.030))
                    .padding(size * 0.17)
            )
            .overlay(
                VStack(alignment: .leading, spacing: size * 0.10) {
                    Capsule().frame(width: size * 0.34, height: max(1, size * 0.055))
                    Capsule().frame(width: size * 0.26, height: max(1, size * 0.055))
                }
                .foregroundStyle(.white.opacity(0.92))
            )
            .frame(width: size, height: size)
    }
}

struct ItemTile: View {
    let item: KeyItem
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Palette.gradient(for: item.provider.isEmpty ? item.name : item.provider))
            .overlay(
                Image(systemName: item.kind.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }
}
