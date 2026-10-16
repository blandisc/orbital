import Foundation
import ImageIO
import UIKit
import WidgetKit
import OrbitalCore

/// Le deja al widget «Lo siguiente para ti» lo que necesita: baja los pósters de «Seguir viendo», los reduce (máx. 300 px, JPEG: el
/// widget no va a la red y su memoria es corta), calcula el tono del arte, escribe el snapshot en el App Group y pide recarga.
@MainActor
enum WidgetPublisher {
    private static var running: Task<Void, Never>?

    static func publish(_ snapshot: WidgetSnapshot) {
        running?.cancel()
        running = Task {
            let previous = WidgetStore.load()
            var result = snapshot
            for index in result.items.indices {
                guard !Task.isCancelled else { return }
                let item = result.items[index]
                // Si el póster no cambió y su archivo sigue ahí, no se baja otra vez.
                if let old = previous?.items.first(where: { $0.metaID == item.metaID && $0.poster == item.poster }),
                   let file = old.imageFile, let url = WidgetStore.imageURL(file), FileManager.default.fileExists(atPath: url.path) {
                    result.items[index].imageFile = file; result.items[index].tint = old.tint
                    continue
                }
                guard let poster = item.poster, let remote = URL(string: poster), let directory = WidgetStore.directory,
                      let (data, _) = try? await URLSession.shared.data(from: remote) else { continue }
                let name = WidgetSnapshot.imageFileName(for: item.metaID)
                let processed = await Task.detached(priority: .utility) { Self.reduce(data) }.value
                guard let (jpeg, tint) = processed else { continue }
                if (try? jpeg.write(to: directory.appendingPathComponent(name), options: .atomic)) != nil {
                    result.items[index].imageFile = name; result.items[index].tint = tint
                }
            }
            guard !Task.isCancelled else { return }
            // Nada que escribir ni recargar si lo que se ve es lo mismo.
            if let previous, previous.items == result.items, previous.language == result.language, previous.upcoming == result.upcoming { return }
            clean(keeping: Set(result.items.compactMap(\.imageFile)))
            if WidgetStore.save(result) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.kind) }
        }
    }

    /// El póster en JPEG de a lo más 300 px y el tono medio de su arte.
    nonisolated private static func reduce(_ data: Data) -> (Data, String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: DesignTokens.Widget.maxImagePixels]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        guard let jpeg = image.jpegData(compressionQuality: DesignTokens.Widget.jpegQuality) else { return nil }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        image.averageColor?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (jpeg, WidgetSnapshot.tintHex(r: Double(red), g: Double(green), b: Double(blue)))
    }

    /// Borra las imágenes de lo que ya no sale en el widget.
    private static func clean(keeping: Set<String>) {
        guard let directory = WidgetStore.directory, let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where file.hasSuffix(".jpg") && !keeping.contains(file) { try? FileManager.default.removeItem(at: directory.appendingPathComponent(file)) }
    }
}
