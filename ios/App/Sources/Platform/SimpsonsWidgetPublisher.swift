import Foundation
import UIKit
import WidgetKit
import OrbitalCore
import OrbitalModels

/// Le deja al widget «Los Simpson en la tele» la tanda del día: los episodios que van pasando por la tele (uno cada media hora)
/// y su imagen ya reducida, en el App Group. Se arma de nuevo cuando cambia el día, falta alguna imagen o cambiaron las
/// temporadas de Ajustes.
///
/// Corre en su propia tarea: antes vivía en el `.task` de Inicio y, si cambiabas de pestaña o salías de la app mientras bajaba
/// (pasa unos segundos después de abrir: espera la ficha de ~650 KB y la fila de imágenes de Inicio), las descargas se
/// cancelaban y se guardaba la semana sin imágenes: el widget enseñaba la dona en vez del episodio (Fernando, 2 nov 2026:
/// «la imagen del episodio no llega bien»).
@MainActor
enum SimpsonsWidgetPublisher {
    private static var running: Task<Void, Never>?

    static func publishIfNeeded(_ model: SimpsonsModel, seasons: [Int], now: Date = Date()) async {
        if let running { return await running.value }
        let task = Task { @MainActor in await publish(model, seasons: seasons, now: now) }
        running = task
        await task.value
        running = nil
    }

    private static func publish(_ model: SimpsonsModel, seasons: [Int], now: Date) async {
        guard let directory = WidgetStore.simpsonsDirectory else { return }
        let rebuilt = WidgetStore.discardOutdatedImages(in: directory)   // cambió el tamaño: se vuelven a bajar
        let stored = WidgetStore.loadSimpsons()
        if !rebuilt, let stored, stored.seasons == seasons.sorted(), Calendar.current.isDate(stored.day, inSameDayAs: now),
           stored.episodes.allSatisfy({ hasImage($0, in: directory) }) { return }
        guard var week = await model.week(from: now) else { return }
        for index in week.episodes.indices {
            let episode = week.episodes[index]
            let name = "\(episode.season)-\(episode.episode).jpg"
            let target = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) { week.episodes[index].imageFile = name; continue }
            guard let url = URL(string: episode.still), let data = await ImagePipeline.shared.bytes(url),
                  let reduced = await Task.detached(priority: .utility, operation: { Self.reduce(data) }).value,
                  (try? reduced.write(to: target, options: .atomic)) != nil else { continue }
            week.episodes[index].imageFile = name
        }
        // Las imágenes de episodios que ya no están en la tanda se van.
        let kept = Set(week.episodes.compactMap(\.imageFile))
        for file in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where file.hasSuffix(".jpg") && !kept.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
        if week != stored, WidgetStore.saveSimpsons(week) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.simpsonsKind) }
        else if rebuilt { WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.simpsonsKind) }
    }

    /// El episodio tiene su imagen apuntada y el archivo sigue ahí.
    private static func hasImage(_ episode: SimpsonsOfTheDay.Episode, in directory: URL) -> Bool {
        episode.imageFile.map { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) } ?? false
    }

    /// La imagen del episodio de a lo más `simpsonsImagePixels` (JPEG); el widget la recorta a la pantalla de la tele al pintarla.
    nonisolated private static func reduce(_ data: Data) -> Data? {
        WidgetImage.reduce(data, maxPixels: DesignTokens.Widget.simpsonsImagePixels, quality: DesignTokens.Widget.jpegQuality)?.data
    }
}
