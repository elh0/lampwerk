import StoreKit
import SwiftUI

/// People who test Lampwerk before launch get a founding-tester reward when it launches.
/// TestFlight builds remember the tester on this phone; the App Store build will read that and offer the claim.
/// The reward is for testing only, never tied to a rating or review.
enum FoundingTester {
    static let key = "foundingTester.seenInBeta"
    static let dismissedKey = "foundingTester.cardDismissed"

    /// Call once at launch. Marks this install as a founding tester when it's a TestFlight or Xcode build.
    static func markIfBeta() async {
        if await isBetaBuild() { UserDefaults.standard.set(true, forKey: key) }
    }

    static var isTester: Bool { UserDefaults.standard.bool(forKey: key) }

    /// TestFlight and Xcode builds run in the sandbox; App Store builds are production.
    static func isBetaBuild() async -> Bool {
        guard let result = try? await AppTransaction.shared, case .verified(let tx) = result else { return false }
        return tx.environment != .production
    }
}

/// Shown only in TestFlight builds. No price, no code, no button: the launch build does the claiming.
struct FoundingTesterCard: View {
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Caps("Founding tester")
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Palette.quiet)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Hide")
            }
            Text("Thanks for plotting with Lampwerk early. When it launches, your first year of Pro is free. The app will show you how to claim it, nothing to do now.")
                .font(.lwBody).foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Palette.p1, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.rule))
    }
}
