import Foundation
import ImageIO
import UIKit
import WidgetKit
import OrbitalCore
import OrbitalModels

/// Le deja al widget «Un Simpson del día» la semana que viene: el episodio de cada día y su imagen ya reducida, en el App
/// Group. Se arma de nuevo cuando quedan menos de tres días armados o cambiaron las temporadas de Ajustes.
@MainActor
enum SimpsonsWidgetPublisher {
    private static var running = false

    static func publishIfNeeded(_ model: SimpsonsModel, seasons: [Int], now: Date = Date()) async {
        guard !running else { return }
        let stored = WidgetStore.loadSimpsons()
        let calendar = Calendar.current
        let ahead = calendar.date(byAdding: .day, value: DesignTokens.Widget.simpsonsAheadDays, to: calendar.startOfDay(for: now)) ?? now
        if let stored, stored.seasons == seasons.sorted(), stored.days.contains(where: { calendar.isDate($0.day, inSameDayAs: ahead) }),
           stored.days.allSatisfy({ $0.imageFile != nil }) { return }
        running = true
        defer { running = false }
        guard var week = await model.week(from: now), let directory = WidgetStore.simpsonsDirectory else { return }
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
        if WidgetStore.saveSimpsons(week) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.simpsonsKind) }
    }

    /// La imagen del episodio de a lo más `simpsonsImagePixels` (JPEG): cabe en el mediano sin pesar en la memoria del widget.
    nonisolated private static func reduce(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: DesignTokens.Widget.simpsonsImagePixels]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: DesignTokens.Widget.jpegQuality)
    }
}
