import SwiftUI

enum Metrics {
    static let panelWidth: CGFloat = 380
    static let panelHeight: CGFloat = 560
    // Measured off the live desktop widget windows: cells are a flush 180pt
    // lattice starting 8pt in and 7pt down from the usable area, and each
    // widget draws its visible card 8pt inside its window.
    static let widgetPitch: CGFloat = 180
    static let widgetInsetX: CGFloat = 8
    static let widgetInsetY: CGFloat = 7
    static let cardShadowInset: CGFloat = 7.5
    static let cardWindowWidth: CGFloat = widgetPitch * 2
    static let cardWindowCollapsedHeight: CGFloat = widgetPitch
    static let cardWindowExpandedHeight: CGFloat = widgetPitch * 3
    static var cardWidth: CGFloat { cardWindowWidth - cardShadowInset * 2 }
    static var cardCollapsedHeight: CGFloat { cardWindowCollapsedHeight - cardShadowInset * 2 }
    static var cardExpandedHeight: CGFloat { cardWindowExpandedHeight - cardShadowInset * 2 }
    static let cornerRadius: CGFloat = 26
    static let cardCornerRadius: CGFloat = 24
    static let cardRadius: CGFloat = 16
    static let gutter: CGFloat = 16
}

enum Palette {
    static let accent = Color(red: 0.29, green: 0.56, blue: 1.0)
    static let gold = Color(red: 0.96, green: 0.80, blue: 0.44)

    private static func pair(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> [Color] {
        [Color(red: a.0, green: a.1, blue: a.2), Color(red: b.0, green: b.1, blue: b.2)]
    }

    /// Fallback gradients, picked deterministically from the provider name.
    private static let tiles: [[Color]] = [
        pair((0.29, 0.56, 1.00), (0.35, 0.34, 0.94)),
        pair((0.40, 0.78, 0.38), (0.19, 0.62, 0.41)),
        pair((1.00, 0.60, 0.20), (0.96, 0.38, 0.27)),
        pair((0.85, 0.36, 0.78), (0.55, 0.29, 0.90)),
        pair((0.20, 0.74, 0.85), (0.16, 0.48, 0.83)),
        pair((0.98, 0.44, 0.52), (0.85, 0.24, 0.44)),
        pair((0.55, 0.60, 0.68), (0.33, 0.38, 0.47)),
    ]

    /// Recognisable services get a tile close to their own brand colour.
    private static let brands: [(String, [Color])] = [
        ("openai", pair((0.16, 0.72, 0.62), (0.10, 0.53, 0.45))),
        ("gpt", pair((0.16, 0.72, 0.62), (0.10, 0.53, 0.45))),
        ("anthropic", pair((0.94, 0.50, 0.34), (0.84, 0.33, 0.24))),
        ("claude", pair((0.94, 0.50, 0.34), (0.84, 0.33, 0.24))),
        ("gemini", pair((0.26, 0.52, 0.96), (0.16, 0.35, 0.85))),
        ("google", pair((0.26, 0.52, 0.96), (0.16, 0.35, 0.85))),
        ("mistral", pair((1.00, 0.63, 0.15), (0.95, 0.42, 0.12))),
        ("aws", pair((1.00, 0.66, 0.20), (0.88, 0.44, 0.09))),
        ("amazon", pair((1.00, 0.66, 0.20), (0.88, 0.44, 0.09))),
        ("azure", pair((0.16, 0.55, 0.85), (0.10, 0.36, 0.70))),
        ("cloudflare", pair((0.97, 0.55, 0.15), (0.92, 0.30, 0.15))),
        ("github", pair((0.44, 0.47, 0.54), (0.20, 0.22, 0.28))),
        ("vercel", pair((0.44, 0.47, 0.54), (0.14, 0.15, 0.18))),
        ("notion", pair((0.52, 0.54, 0.58), (0.26, 0.27, 0.30))),
        ("gitlab", pair((0.99, 0.55, 0.24), (0.89, 0.25, 0.15))),
        ("stripe", pair((0.45, 0.42, 0.95), (0.34, 0.27, 0.85))),
        ("paypal", pair((0.16, 0.44, 0.80), (0.09, 0.27, 0.60))),
        ("supabase", pair((0.24, 0.82, 0.52), (0.11, 0.58, 0.36))),
        ("postgres", pair((0.28, 0.55, 0.75), (0.16, 0.34, 0.55))),
        ("mongo", pair((0.34, 0.74, 0.42), (0.15, 0.48, 0.28))),
        ("redis", pair((0.93, 0.35, 0.30), (0.72, 0.16, 0.16))),
        ("slack", pair((0.85, 0.30, 0.65), (0.55, 0.25, 0.80))),
        ("twilio", pair((0.94, 0.29, 0.35), (0.76, 0.15, 0.27))),
        ("resend", pair((0.30, 0.62, 0.98), (0.19, 0.44, 0.90))),
        ("sendgrid", pair((0.30, 0.62, 0.98), (0.19, 0.44, 0.90))),
        ("mailgun", pair((0.30, 0.62, 0.98), (0.19, 0.44, 0.90))),
        ("telegram", pair((0.24, 0.70, 0.92), (0.13, 0.48, 0.80))),
    ]

    static func gradient(for seed: String) -> LinearGradient {
        LinearGradient(colors: colors(for: seed), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static func colors(for seed: String) -> [Color] {
        if seed == "accent" { return tiles[0] }
        let value = seed.lowercased()
        for (needle, colors) in brands where value.contains(needle) { return colors }
        return tiles[abs(stableHash(value)) % tiles.count]
    }

    static func symbol(for seed: String, fallback: String = "key.fill") -> String {
        if seed == "accent" { return Brand.symbol }
        let value = seed.lowercased()
        let table: [(String, String)] = [
            ("openai", "sparkles"), ("gpt", "sparkles"),
            ("anthropic", "sparkles"), ("claude", "sparkles"),
            ("gemini", "sparkles"), ("mistral", "sparkles"),
            ("aws", "cloud.fill"), ("amazon", "cloud.fill"),
            ("azure", "cloud.fill"), ("gcp", "cloud.fill"), ("google", "cloud.fill"),
            ("cloudflare", "cloud.fill"), ("vercel", "triangle.fill"),
            ("github", "chevron.left.forwardslash.chevron.right"),
            ("gitlab", "chevron.left.forwardslash.chevron.right"),
            ("stripe", "creditcard.fill"), ("paypal", "creditcard.fill"),
            ("resend", "envelope.fill"), ("sendgrid", "envelope.fill"),
            ("mailgun", "envelope.fill"), ("twilio", "message.fill"),
            ("notion", "doc.text.fill"), ("slack", "number"),
            ("supabase", "cylinder.split.1x2.fill"), ("postgres", "cylinder.split.1x2.fill"),
            ("mongo", "cylinder.split.1x2.fill"), ("redis", "cylinder.split.1x2.fill"),
            ("telegram", "paperplane.fill"), ("map", "map.fill"),
        ]
        for (needle, symbol) in table where value.contains(needle) { return symbol }
        return fallback
    }

    private static func stableHash(_ string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ Int(byte) }
        return hash
    }
}

/// The app mark itself: a slate tablet with a gilt border.
struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.36), Color(white: 0.13)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
    }
}

struct IconTile: View {
    let seed: String
    var size: CGFloat = 34
    var fallbackSymbol: String = "key.fill"
    /// Set to pin the glyph regardless of provider matching; logins always
    /// show a person even when the provider has its own symbol.
    var symbolOverride: String?

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Palette.gradient(for: seed))
            .overlay(
                Image(systemName: symbolOverride ?? Palette.symbol(for: seed, fallback: fallbackSymbol))
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }
}

/// Round translucent control, the shape used across iOS widgets.
struct GlassButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary.opacity(0.75)))
            .frame(width: size, height: size)
            .background(
                Circle().fill(prominent
                    ? AnyShapeStyle(Palette.gradient(for: "accent"))
                    : AnyShapeStyle(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08)))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.pop, value: configuration.isPressed)
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(filled ? AnyShapeStyle(Color.white) : AnyShapeStyle(tint))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(filled
                        ? AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.75)],
                                                       startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(tint.opacity(0.14)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(filled ? 0.2 : 0), lineWidth: 0.6)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.pop, value: configuration.isPressed)
    }
}

struct CardBackground: ViewModifier {
    var radius: CGFloat = Metrics.cardRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6)
            )
    }
}

extension View {
    func cardBackground(radius: CGFloat = Metrics.cardRadius) -> some View {
        modifier(CardBackground(radius: radius))
    }
}


private struct StaticRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// ImageRenderer cannot rasterise ScrollView content; the preview tool flips this on.
    var staticRendering: Bool {
        get { self[StaticRenderingKey.self] }
        set { self[StaticRenderingKey.self] = newValue }
    }
}

struct ScrollContainer<Content: View>: View {
    @Environment(\.staticRendering) private var isStatic
    @ViewBuilder var content: Content

    var body: some View {
        if isStatic {
            VStack(spacing: 0) {
                content
                Spacer(minLength: 0)
            }
        } else {
            ScrollView(.vertical) { content }
                .scrollIndicators(.hidden)
                // AppKit adds its own content insets, which put the scrolling
                // content out of line with headers sitting outside the scroll.
                .contentMargins(.all, 0, for: .scrollContent)
        }
    }
}
