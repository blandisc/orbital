import Foundation
import OrbitalCore

/// Dónde vive lo que la app le deja al widget «Lo siguiente para ti»: el `WidgetSnapshot` (JSON) y las imágenes ya reducidas, en el
/// App Group (la app y la extensión de widgets son procesos distintos y solo comparten este contenedor). La compilan los dos.
enum WidgetStore {
    static let groupID = "group.mx.iracheta.orbital"
    /// El identificador del widget para `WidgetCenter.reloadTimelines(ofKind:)`.
    static let kind = "mx.iracheta.orbital.nextup"
    /// «Lo nuevo de lo tuyo»: lo que ya salió de tus series y lo que viene (lee el mismo snapshot).
    static let releasesKind = "mx.iracheta.orbital.releases"

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

    /// La versión de las imágenes guardadas. Al subirla (cambió el tamaño con que se guardan), la primera publicación borra
    /// las de antes y las vuelve a bajar: sin esto, las de 300 px se quedaban para siempre (se reutilizan si ya están).
    static let imagesVersion = 2
    /// El mosaico va aparte: sus pósters se guardan del tamaño de su pieza (330 px), no a 450 (2 nov 2026).
    static let listImagesVersion = 3

    /// Borra las imágenes de una versión anterior de `folder` (cada widget tiene la suya) y apunta la actual; true si borró
    /// (hay que volver a escribir y recargar aunque lo demás no haya cambiado). Lo llaman los que publican.
    @discardableResult
    static func discardOutdatedImages(in folder: URL, version: Int = imagesVersion) -> Bool {
        let marker = folder.appendingPathComponent("images-v\(version)")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return false }
        for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        where file.hasSuffix(".jpg") || file.hasSuffix(".png") || file.hasPrefix("images-v") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
        FileManager.default.createFile(atPath: marker.path, contents: Data())
        return true
    }

    // MARK: Un Simpson del día

    static let simpsonsKind = "mx.iracheta.orbital.simpsons-day"
    /// Su propia carpeta: la limpieza de «Lo siguiente para ti» no toca estas imágenes.
    static var simpsonsDirectory: URL? {
        guard let url = directory?.appendingPathComponent("Simpsons", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func loadSimpsons() -> SimpsonsOfTheDay? {
        guard let url = simpsonsDirectory?.appendingPathComponent("week.json"), let data = try? Data(contentsOf: url) else { return nil }
        return SimpsonsOfTheDay.decode(data)
    }

    @discardableResult
    static func saveSimpsons(_ week: SimpsonsOfTheDay) -> Bool {
        guard let url = simpsonsDirectory?.appendingPathComponent("week.json"), let data = try? week.encoded() else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func simpsonsImageURL(_ name: String) -> URL? { simpsonsDirectory?.appendingPathComponent(name) }

    // MARK: Mosaico de una lista

    static let listsKind = "mx.iracheta.orbital.list-mosaic"
    static var listsDirectory: URL? {
        guard let url = directory?.appendingPathComponent("Lists", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func loadLists() -> WidgetLists? {
        guard let url = listsDirectory?.appendingPathComponent("lists.json"), let data = try? Data(contentsOf: url) else { return nil }
        return WidgetLists.decode(data)
    }

    @discardableResult
    static func saveLists(_ lists: WidgetLists) -> Bool {
        guard let url = listsDirectory?.appendingPathComponent("lists.json"), let data = try? lists.encoded() else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func listImageURL(_ name: String) -> URL? { listsDirectory?.appendingPathComponent(name) }

    /// El orden del mosaico: cambia con «Revolver» (cada número es un orden distinto de los mismos pósters).
    static var mosaicSeed: Int { UserDefaults(suiteName: groupID)?.integer(forKey: "mosaic.seed") ?? 0 }
    static func shuffleMosaic() { UserDefaults(suiteName: groupID)?.set(mosaicSeed + 1, forKey: "mosaic.seed") }
}
