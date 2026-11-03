import Foundation
import UIKit
import WidgetKit
import OrbitalCore
import OrbitalModels

/// Le deja al widget «Un Simpson del día» la semana que viene: el episodio de cada día y su imagen ya reducida, en el App
/// Group. Se arma de nuevo cuando quedan menos de tres días armados, falta alguna imagen o cambiaron las temporadas de Ajustes.
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
        let calendar = Calendar.current
        let ahead = calendar.date(byAdding: .day, value: DesignTokens.Widget.simpsonsAheadDays, to: calendar.startOfDay(for: now)) ?? now
        if !rebuilt, let stored, stored.seasons == seasons.sorted(), stored.days.contains(where: { calendar.isDate($0.day, inSameDayAs: ahead) }),
           stored.days.allSatisfy({ hasImage($0, in: directory) }) { return }
        guard var week = await model.week(from: now) else { return }
        for index in week.days.indices {
            let day = week.days[index]
            let name = "\(day.season)-\(day.episode).jpg"
            let target = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) { week.days[index].imageFile = name; continue }
            guard let url = URL(string: day.still), let data = await ImagePipeline.shared.bytes(url),
                  let reduced = await Task.detached(priority: .utility, operation: { Self.reduce(data) }).value,
                  (try? reduced.write(to: target, options: .atomic)) != nil else { continue }
            week.days[index].imageFile = name
        }
        // Las imágenes de días que ya no están en la semana se van.
        let kept = Set(week.days.compactMap(\.imageFile))
        for file in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where file.hasSuffix(".jpg") && !kept.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
        if week != stored, WidgetStore.saveSimpsons(week) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.simpsonsKind) }
        else if rebuilt { WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.simpsonsKind) }
    }

    /// El día tiene su imagen apuntada y el archivo sigue ahí.
    private static func hasImage(_ day: SimpsonsOfTheDay.Day, in directory: URL) -> Bool {
        day.imageFile.map { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) } ?? false
    }

    /// La imagen del episodio de a lo más `simpsonsImagePixels` (JPEG); el widget la recorta a la pantalla de la tele al pintarla.
    nonisolated private static func reduce(_ data: Data) -> Data? {
        WidgetImage.reduce(data, maxPixels: DesignTokens.Widget.simpsonsImagePixels, quality: DesignTokens.Widget.jpegQuality)?.data
    }
}
