import Foundation
import OrbitalCore

/// Dónde viven los archivos de la app. Las descargas van en Application Support y fuera de la copia de seguridad
/// de iCloud (pesan gigas y se pueden volver a bajar).
enum AppFiles {
    static var support: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Orbital", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Lo último que se vio (catálogos, Inicio, Para ti) para pintarlo al abrir mientras llega lo nuevo. iOS puede borrarlo.
    static var swrCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Orbital-SWR", isDirectory: true)
    }

    static var downloadsRoot: URL {
        var url = support.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    static var pendingWork: URL { support.appendingPathComponent("pending.json") }
    /// Lo tuyo (avance, visto, Mi lista): la biblioteca del teléfono (`LocalLibrary`). Entra en el respaldo de iCloud.
    static var library: URL { support.appendingPathComponent("library.json") }
    static var downloadIndex: URL { support.appendingPathComponent("downloads.json") }
}

/// El índice de descargas (sin enlaces: esos van en el Keychain), con `StoredFile` como la biblioteca (F10): uno dañado se aparta
/// con fecha y uno que falta o está dañado se rearma desde la carpeta de descargas (`DownloadIndexFile`, revisión del 11 nov
/// 2026: antes las descargas seguían en disco pero ya no se veían). Uno que solo no se pudo leer ahora no se pisa.
enum DownloadIndex {
    private static let file = DownloadIndexFile(url: AppFiles.downloadIndex, root: AppFiles.downloadsRoot)

    static func load() -> [DownloadItem] { file.load() }

    private static let queue = DispatchQueue(label: "orbital.download-index")
    static func save(_ items: [DownloadItem]) {
        queue.async { file.save(items) }
    }
}
