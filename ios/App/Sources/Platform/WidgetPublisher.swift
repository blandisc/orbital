import Foundation
import ImageIO
import UIKit
import WidgetKit
import OrbitalCore

/// Le deja al widget «Lo siguiente para ti» lo que necesita: baja el póster, la imagen ancha y el logo de cada título de «Seguir viendo»,
/// los reduce (máx. 300 px: el widget no va a la red y su memoria es corta), calcula el tono del arte, escribe el snapshot en el
/// App Group y pide recarga.
@MainActor
enum WidgetPublisher {
    private static var running: Task<Void, Never>?

    static func publish(_ snapshot: WidgetSnapshot) {
        running?.cancel()
        running = Task(priority: .utility) {
            // Espera a que la pantalla termine de pintar: al abrir la app el widget ya no compite con el destacado y los estantes,
            // y varias publicaciones seguidas (Inicio, luego Para ti) se juntan en una sola.
            try? await Task.sleep(for: .seconds(DesignTokens.Widget.publishDelay))
            guard !Task.isCancelled else { return }
            let previous = WidgetStore.load()
            var result = snapshot
            for index in result.items.indices {
                guard !Task.isCancelled else { return }
                let item = result.items[index]
                let old = previous?.items.first { $0.metaID == item.metaID }
                let poster = await image(item.poster, as: .poster, id: item.metaID, reuse: old.flatMap { $0.poster == item.poster ? ($0.imageFile, $0.tint) : nil })
                result.items[index].imageFile = poster.file; result.items[index].tint = poster.tint
                let wide = await image(item.wide, as: .wide, id: item.metaID, reuse: old.flatMap { $0.wide == item.wide ? ($0.wideFile, nil) : nil })
                result.items[index].wideFile = wide.file
                if result.items[index].tint == nil { result.items[index].tint = wide.tint }
                result.items[index].logoFile = await image(item.logo, as: .logo, id: item.metaID, reuse: old.flatMap { $0.logo == item.logo ? ($0.logoFile, nil) : nil }).file
            }
            guard !Task.isCancelled else { return }
            // Nada que escribir ni recargar si lo que se ve es lo mismo.
            if let previous, previous.items == result.items, previous.language == result.language, previous.upcoming == result.upcoming { return }
            let kept = result.items.flatMap { [$0.imageFile, $0.wideFile, $0.logoFile] }.compactMap { $0 }
            clean(keeping: Set(kept))
            if WidgetStore.save(result) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.kind) }
        }
    }

    /// Una imagen reducida en el App Group (se reutiliza la de antes si la URL no cambió); nil si no hay o no cargó.
    private static func image(_ remote: String?, as kind: WidgetSnapshot.ImageKind, id: String, reuse: (String?, String?)?) async -> (file: String?, tint: String?) {
        if let (file, tint) = reuse, let file, let url = WidgetStore.imageURL(file), FileManager.default.fileExists(atPath: url.path) { return (file, tint) }
        // Por el mismo caché y la misma fila que las pantallas, y en la variante ligera (el widget usa 300 px como mucho).
        guard let remote, let url = URL(string: Artwork.variant(remote, pixels: Int(DesignTokens.Widget.maxImagePixels))), let directory = WidgetStore.directory,
              let data = await ImagePipeline.shared.bytes(url) else { return (nil, nil) }
        let name = WidgetSnapshot.imageFileName(for: id, kind: kind)
        let processed = await Task.detached(priority: .utility) { Self.reduce(data, png: kind == .logo) }.value
        guard let (bytes, tint) = processed, (try? bytes.write(to: directory.appendingPathComponent(name), options: .atomic)) != nil else { return (nil, nil) }
        return (name, tint)
    }

    /// La imagen de a lo más 300 px (JPEG, o PNG para el logo) y el tono medio de su arte.
    nonisolated private static func reduce(_ data: Data, png: Bool) -> (Data, String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: DesignTokens.Widget.maxImagePixels]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        guard let bytes = png ? image.pngData() : image.jpegData(compressionQuality: DesignTokens.Widget.jpegQuality) else { return nil }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        image.averageColor?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (bytes, WidgetSnapshot.tintHex(r: Double(red), g: Double(green), b: Double(blue)))
    }

    /// Borra las imágenes de lo que ya no sale en el widget.
    private static func clean(keeping: Set<String>) {
        guard let directory = WidgetStore.directory, let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where (file.hasSuffix(".jpg") || file.hasSuffix(".png")) && !keeping.contains(file) { try? FileManager.default.removeItem(at: directory.appendingPathComponent(file)) }
    }
}
