import SwiftUI

// Warm, calm palette — mirrors the web/RN clay / cream / sage / ink colours so
// all three clients feel like the same product. Defined as a namespace of
// Color so views read `Palette.clay600` etc.
enum Palette {
    static let cream50  = Color(hex: 0xfbf8f3)
    static let cream100 = Color(hex: 0xf6f0e6)
    static let cream200 = Color(hex: 0xecdfc9)

    static let ink900 = Color(hex: 0x1f1b16)
    static let ink700 = Color(hex: 0x3d362e)
    static let ink500 = Color(hex: 0x6b6258)
    static let ink300 = Color(hex: 0xa59c91)

    static let clay50  = Color(hex: 0xfdf5ef)
    static let clay100 = Color(hex: 0xf9e6d6)
    static let clay500 = Color(hex: 0xc87a4f)
    static let clay600 = Color(hex: 0xa85f3a)
    static let clay700 = Color(hex: 0x854a2d)

    static let sage100 = Color(hex: 0xe6ede4)
    static let sage500 = Color(hex: 0x6a8a64)
    static let sage700 = Color(hex: 0x4d6b48)

    static let amberBg = Color(hex: 0xfef3c7)
    static let amberFg = Color(hex: 0x92400e)
    static let danger  = Color(hex: 0xb91c1c)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Reusable view styling

/// A white rounded card with the warm border — the workhorse container.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.cream200, lineWidth: 1)
            )
    }
}

/// The primary clay-filled button label style.
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Palette.clay600.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
