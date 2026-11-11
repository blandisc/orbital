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

/// El índice de descargas (sin enlaces: esos van en el Keychain).
/// Con `StoredFile`, como la biblioteca (F10, 10 nov 2026): un índice dañado ya no se lee como vacío en silencio (y luego se
/// pisaba, perdiendo de vista las descargas que siguen en disco): se aparta como `downloads.json.corrupt` y queda en la bitácora.
enum DownloadIndex {
    static func load() -> [DownloadItem] {
        StoredFile.read([DownloadItem].self, from: AppFiles.downloadIndex, what: "el índice de descargas") ?? []
    }

    private static let queue = DispatchQueue(label: "orbital.download-index")
    static func save(_ items: [DownloadItem]) {
        queue.async { StoredFile.write(items, to: AppFiles.downloadIndex, what: "el índice de descargas") }
    }
}
