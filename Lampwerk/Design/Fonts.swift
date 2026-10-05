import CoreText
import SwiftUI
import UIKit

/// IBM Plex Sans for words, IBM Plex Mono for numbers (SIL OFL, bundled in Lampwerk/Fonts/).
/// Registered at launch, so no Info.plist entry is needed. Falls back to SF if a file is missing.
enum Fonts {
    static func registerBundled() {
        let urls = ["ttf", "otf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func sans(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let name = weight == .medium ? "IBMPlexSans-Medium" : "IBMPlexSans-Regular"
        if UIFont(name: name, size: size) != nil { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let name = weight == .medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular"
        if UIFont(name: name, size: size) != nil { return .custom(name, fixedSize: size).monospacedDigit() }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}
