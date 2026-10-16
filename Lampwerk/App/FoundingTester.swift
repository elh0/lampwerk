import StoreKit
import SwiftUI

/// People who test Lampwerk before launch get a founding-tester reward when it launches.
/// TestFlight builds remember the tester on this phone; the App Store build will read that and offer the claim.
/// The reward is for testing only, never tied to a rating or review.
enum FoundingTester {
    static let key = "foundingTester.seenInBeta"
    static let dismissedKey = "foundingTester.cardDismissed"

    /// The App Store offer code. Empty until launch: the offer can only be made once Pro is approved,
    /// and while it's empty the claim card never shows.
    static let code = ""
    /// Placeholder until the Pro in-app purchase exists. Used to hide the claim once Pro is owned.
    static let proProductID = "com.lampwerk.app.pro"
    /// Lampwerk's numeric App Store id, for the redeem link. Fill in with the code.
    static let appleAppID = ""

    /// The claim card shows only in the App Store build, to a remembered tester, once a code is set.
    /// TODO when the paywall exists: also require that Pro isn't owned (Transaction.currentEntitlements).
    static func shouldOfferClaim() async -> Bool {
        guard !code.isEmpty, isTester else { return false }
        return !(await isBetaBuild())
    }

    /// Apple's redeem page with the code filled in, for when the in-app sheet misbehaves.
    static var redeemURL: URL? {
        guard !code.isEmpty, !appleAppID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/redeem?ctx=offercodes&id=\(appleAppID)&code=\(code)")
    }

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

/// The App Store build's thanks, with the claim. Never mentions testing builds, and never asks for a review.
struct FoundingClaimCard: View {
    @State private var redeeming = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Caps("Founding tester")
            Text("Thanks for plotting with Lampwerk early. Your first year of Pro is free.")
                .font(.lwBody).foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Claim Pro") { redeeming = true }
                    .buttonStyle(ActionButtonStyle(primary: true))
                if let url = FoundingTester.redeemURL {
                    Button("Use a link instead") { openURL(url) }
                        .buttonStyle(ActionButtonStyle())
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Palette.p1, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.rule))
        .offerCodeRedemption(isPresented: $redeeming) { _ in }
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
