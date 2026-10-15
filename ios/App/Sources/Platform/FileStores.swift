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

    static var downloadsRoot: URL {
        var url = support.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    static var pendingWork: URL { support.appendingPathComponent("pending.json") }
    static var downloadIndex: URL { support.appendingPathComponent("downloads.json") }
}

/// El índice de descargas (sin enlaces: esos van en el Keychain).
enum DownloadIndex {
    static func load() -> [DownloadItem] {
        (try? Data(contentsOf: AppFiles.downloadIndex)).flatMap { try? JSONDecoder().decode([DownloadItem].self, from: $0) } ?? []
    }

    private static let queue = DispatchQueue(label: "orbital.download-index")
    static func save(_ items: [DownloadItem]) {
        queue.async { if let data = try? JSONEncoder().encode(items) { try? data.write(to: AppFiles.downloadIndex, options: .atomic) } }
    }
}
