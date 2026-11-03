import Foundation
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
            WidgetStore.discardOutdatedImages(in: directory)   // cambió el tamaño: se vuelven a bajar
            var model = WidgetLists(lists: lists)
            // Primero lo que ya está en el disco: el widget lo enseña al momento.
            for l in model.lists.indices {
                for p in model.lists[l].posters.indices {
                    let name = WidgetLists.imageFileName(for: model.lists[l].posters[p].metaID)
                    if FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) { model.lists[l].posters[p].imageFile = name }
                }
            }
            save(model)
            // Luego lo que falta, lista por lista, guardando al terminar cada una. Antes se guardaba solo al final de todo: tras
            // borrar las imágenes viejas había que volver a bajar cientos de pósters y, si salías de Explorar antes, no se
            // guardaba nada y el mosaico se quedaba sin imágenes (Fernando, 2 nov 2026: «no salen imágenes en el widget»).
            for l in model.lists.indices {
                for p in model.lists[l].posters.indices where model.lists[l].posters[p].imageFile == nil {
                    guard !Task.isCancelled else { save(model); return }
                    let poster = model.lists[l].posters[p]
                    let name = WidgetLists.imageFileName(for: poster.metaID)
                    let target = directory.appendingPathComponent(name)
                    guard let url = URL(string: Artwork.variant(poster.poster, pixels: Int(DesignTokens.Widget.listImagePixels))),
                          let data = await ImagePipeline.shared.bytes(url),
                          let reduced = await Task.detached(priority: .utility, operation: { Self.reduce(data) }).value,
                          (try? reduced.write(to: target, options: .atomic)) != nil else { continue }
                    model.lists[l].posters[p].imageFile = name
                }
                save(model)
            }
            guard !Task.isCancelled else { return }
            let kept = Set(model.lists.flatMap { $0.posters.compactMap(\.imageFile) })
            for file in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where file.hasSuffix(".jpg") && !kept.contains(file) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            }
        }
    }

    /// Guarda las listas (si cambiaron) y le pide al widget que se vuelva a dibujar.
    private static func save(_ model: WidgetLists) {
        guard WidgetStore.loadLists() != model, WidgetStore.saveLists(model) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.listsKind)
    }

    nonisolated private static func reduce(_ data: Data) -> Data? {
        WidgetImage.reduce(data, maxPixels: DesignTokens.Widget.listImagePixels, quality: DesignTokens.Widget.jpegQuality)?.data
    }
}
