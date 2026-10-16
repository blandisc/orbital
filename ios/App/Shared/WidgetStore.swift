import Foundation
import OrbitalCore

/// Dónde vive lo que la app le deja al widget «Lo siguiente para ti»: el `WidgetSnapshot` (JSON) y las imágenes ya reducidas, en el
/// App Group (la app y la extensión de widgets son procesos distintos y solo comparten este contenedor). La compilan los dos.
enum WidgetStore {
    static let groupID = "group.mx.iracheta.orbital"
    /// El identificador del widget para `WidgetCenter.reloadTimelines(ofKind:)`.
    static let kind = "mx.iracheta.orbital.nextup"

    /// nil si el App Group no está disponible (una compilación sin firmar).
    static var directory: URL? {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        let url = root.appendingPathComponent("Widget", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var snapshotURL: URL? { directory?.appendingPathComponent("snapshot.json") }

    static func load() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return WidgetSnapshot.decode(data)
    }

    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = snapshotURL, let data = try? snapshot.encoded() else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func imageURL(_ name: String) -> URL? { directory?.appendingPathComponent(name) }
}
