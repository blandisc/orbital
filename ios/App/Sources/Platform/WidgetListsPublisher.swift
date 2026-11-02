import Foundation
import ImageIO
import UIKit
import WidgetKit
import OrbitalCore
import OrbitalModels

/// Le deja al widget «Mosaico de una lista» tus listas de Explorar con sus pósters reducidos (máx. `listImagePixels`), en el App
/// Group. Se llama cuando Explorar arma sus estantes; un póster que ya estaba no se vuelve a bajar.
@MainActor
enum WidgetListsPublisher {
    private static var running: Task<Void, Never>?

    static func publish(_ lists: [WidgetLists.List]) {
        running?.cancel()
        running = Task(priority: .utility) {
            // Que Explorar termine de pintar primero (sus pósters van por la misma fila).
            try? await Task.sleep(for: .seconds(DesignTokens.Widget.publishDelay * 2))
            guard !Task.isCancelled, let directory = WidgetStore.listsDirectory else { return }
            var model = WidgetLists(lists: lists)
            for l in model.lists.indices {
                for p in model.lists[l].posters.indices {
                    guard !Task.isCancelled else { return }
                    let poster = model.lists[l].posters[p]
                    let name = WidgetLists.imageFileName(for: poster.metaID)
                    let target = directory.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: target.path) { model.lists[l].posters[p].imageFile = name; continue }
                    guard let url = URL(string: Artwork.variant(poster.poster, pixels: Int(DesignTokens.Widget.listImagePixels))),
                          let data = await ImagePipeline.shared.bytes(url),
                          let reduced = await Task.detached(priority: .utility, operation: { Self.reduce(data) }).value,
                          (try? reduced.write(to: target, options: .atomic)) != nil else { continue }
                    model.lists[l].posters[p].imageFile = name
                }
            }
            guard !Task.isCancelled else { return }
            if WidgetStore.loadLists() == model { return }
            let kept = Set(model.lists.flatMap { $0.posters.compactMap(\.imageFile) })
            for file in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where file.hasSuffix(".jpg") && !kept.contains(file) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
            if WidgetStore.saveLists(model) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.listsKind) }
        }
    }

    nonisolated private static func reduce(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: DesignTokens.Widget.listImagePixels]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: DesignTokens.Widget.jpegQuality)
    }
}
