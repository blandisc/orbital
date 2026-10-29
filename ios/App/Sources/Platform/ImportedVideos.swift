import Foundation

/// Los videos que te pasan (AirDrop, Archivos, «Abrir con…»): se guardan en una carpeta de la app, fuera del respaldo de
/// iCloud, y se borran solos a los pocos días. Solo disco: qué hacer con el video lo decide `AppEnvironment`.
enum ImportedVideos {
    /// Cuántos días se queda un video que te pasaron antes de borrarse solo.
    static let days: Double = 3

    static var folder: URL {
        let folder = AppFiles.support.appendingPathComponent("Importados", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Copia (o mueve, si venía de Documents/Inbox: no se queda una segunda copia de gigas) el video a la carpeta de la app,
    /// con la fecha de hoy (de ella se cuentan los días para borrarlo). Devuelve dónde quedó.
    static func store(_ url: URL) throws -> URL {
        prune()
        let target = folder.appendingPathComponent(url.lastPathComponent)
        if target.standardizedFileURL != url.standardizedFileURL {
            try? FileManager.default.removeItem(at: target)
            if url.path.contains("/Inbox/") { try FileManager.default.moveItem(at: url, to: target) }
            else { try FileManager.default.copyItem(at: url, to: target) }
        }
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutable = target; try? mutable.setResourceValues(values)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
        return target
    }

    /// Borra los videos que te pasaron hace más de `days`.
    static func prune() {
        let fm = FileManager.default
        let old = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in old where ((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < Date().addingTimeInterval(-days * 86_400) {
            try? fm.removeItem(at: file)
        }
    }
}
