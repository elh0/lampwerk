import SwiftUI

/// Brand v2 "Console" tokens (eltio/lampwerk/brand-kit/tokens.json).
/// Four panel tones for depth, one off-white at three strengths, and one gel that only ever means light.
enum Palette {
    static let p0 = Color(hex: 0x0E0E0D)       // canvas
    static let p1 = Color(hex: 0x151514)       // panel
    static let p2 = Color(hex: 0x1D1D1B)       // raised, selected
    static let p3 = Color(hex: 0x262624)       // track
    static let text = Color(hex: 0xEDEDEA)
    static let quiet = Color(hex: 0xEDEDEA).opacity(0.52)
    static let faint = Color(hex: 0xEDEDEA).opacity(0.30)
    static let rule = Color(hex: 0xEDEDEA).opacity(0.10)
    static let ruleStrong = Color(hex: 0xEDEDEA).opacity(0.20)
    /// Medium Yellow, Lee 010. A lit lamp, its beam, an on switch, the selection ring. Never text.
    static let gel = Color(hex: 0xFFC21A)
    static let beamOpacity = 0.22
    /// Print only: the gaffer sheet and the icon.
    static let ink = Color(hex: 0x0B0B0A)
    static let paper = Color.white
}

enum Radius {
    static let chip: CGFloat = 6
    static let card: CGFloat = 8
    static let panel: CGFloat = 10
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    /// Words.
    static let lwBody = Fonts.sans(14, .regular)
    static let lwTitle = Fonts.sans(15, .medium)
    static let lwButton = Fonts.sans(13, .medium)
    static let lwChip = Fonts.sans(12, .regular)
    /// Labels: 11 caps, +8% tracking, quiet.
    static let lwLabel = Fonts.sans(11, .regular)
    /// Anything you'd read off a meter.
    static let lwData = Fonts.mono(12, .regular)
    static let lwValue = Fonts.mono(13, .regular)
    static let lwReadout = Fonts.mono(15, .medium)
}

/// The quiet uppercase label used above lists and readouts.
struct Caps: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.lwLabel)
            .tracking(11 * 0.08)
            .foregroundStyle(Palette.quiet)
    }
}

/// Small rounded chip: a setup, a role, a library group.
struct Chip: View {
    let title: String
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.lwChip)
                .foregroundStyle(selected ? Palette.text : Palette.quiet)
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(selected ? Palette.p2 : Palette.p0, in: RoundedRectangle(cornerRadius: Radius.chip))
                .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(selected ? Palette.ruleStrong : Palette.rule))
        }
        .buttonStyle(.plain)
    }
}

/// Buttons: primary is off-white on dark, the rest are raised panels.
struct ActionButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.lwButton)
            .foregroundStyle(primary ? Palette.p0 : Palette.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(primary ? Palette.text : Palette.p2, in: RoundedRectangle(cornerRadius: Radius.chip))
            .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(primary ? Palette.text : Palette.rule))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The mark and wordmark, from the outlined SVGs in the asset catalogue. Solid, never in gel.
struct Lockup: View {
    var height: CGFloat = 22
    var body: some View {
        HStack(spacing: height * 0.36) {
            Image("Mark").resizable().scaledToFit().frame(height: height)
            Image("Wordmark").resizable().scaledToFit().frame(height: height * 0.66)
        }
        .foregroundStyle(Palette.text)
        .accessibilityElement()
        .accessibilityLabel("Lampwerk")
    }
}
