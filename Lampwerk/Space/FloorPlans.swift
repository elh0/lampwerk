import PDFKit
import SwiftUI
import UIKit

/// Location floor plans, saved as images in Documents/floorplans and drawn under a plot.
/// A PDF is flattened to an image of its first page.
enum FloorPlans {
    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]

    private static var folder: URL {
        let url = URL.documentsDirectory.appending(path: "floorplans", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func image(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        if let hit = cache[name] { return hit }
        guard let img = UIImage(contentsOfFile: folder.appending(path: name).path) else { return nil }
        cache[name] = img
        return img
    }

    /// Saves picked image data and returns the file name to keep on the plot.
    static func save(imageData data: Data) -> String? {
        guard let img = UIImage(data: data) else { return nil }
        return save(img)
    }

    /// Reads an image or PDF the user picked from Files.
    static func save(fileAt url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "pdf" {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 2400 / max(bounds.width, bounds.height)
            let img = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            return save(img)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return save(imageData: data)
    }

    static func delete(_ name: String?) {
        guard let name else { return }
        cache[name] = nil
        try? FileManager.default.removeItem(at: folder.appending(path: name))
    }

    private static func save(_ img: UIImage) -> String? {
        // Keep files a sensible size; a plan doesn't need more than this.
        let maxSide: CGFloat = 2400
        let side = max(img.size.width, img.size.height)
        let scaled: UIImage
        if side > maxSide {
            let s = maxSide / side
            let size = CGSize(width: img.size.width * s, height: img.size.height * s)
            scaled = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        } else {
            scaled = img
        }
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: folder.appending(path: name), options: .atomic)
            cache[name] = scaled
            return name
        } catch {
            return nil
        }
    }
}
