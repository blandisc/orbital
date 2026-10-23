import Foundation
import UIKit
import OrbitalCore

/// La bitácora de velocidad de las descargas (`Library/Application Support/download-timeline.txt`): cada ~2 s mientras baja
/// algo, si la app está a la vista o no, por qué carril va, si sigue viva la tarea continua de iOS y a cuánto baja. Sirve para
/// ver en el iPhone de verdad qué pasa al salir de la app (se lee desde la Mac con `devicectl … copy from`); los huecos son
/// ratos en que iOS tuvo la app suspendida. Se queda chica: al pasar de ~200 KB se empieza otra.
@MainActor
enum DownloadTimeline {
    static let file = AppFiles.support.appendingPathComponent("download-timeline.txt")
    private static var last: (bytes: Int64, at: Date)?
    private static let interval = 2.0, limit = 200_000

    static func record(_ items: [DownloadItem], fastLane: Bool, continued: Bool) {
        let active = items.filter { $0.state == .downloading }
        guard !active.isEmpty else { last = nil; return }
        let now = Date(), written = active.reduce(Int64(0)) { $0 + $1.writtenBytes }
        if let last, now.timeIntervalSince(last.at) < interval { return }
        let rate = last.map { max(0, Double(written - $0.bytes) / now.timeIntervalSince($0.at)) / 1e6 }
        last = (written, now)
        let state = switch UIApplication.shared.applicationState { case .active: "abierta"; case .inactive: "inactiva"; default: "fuera" }
        let line = [ISO8601DateFormatter().string(from: now), state, fastLane ? "rapido" : "fondo", continued ? "tarea-ios" : "sin-tarea",
                    String(format: "%.1f MB", Double(written) / 1e6), rate.map { String(format: "%.1f MB/s", $0) } ?? "-"].joined(separator: " ")
        append(line + "\n")
    }

    /// Agrega un renglón a una bitácora (esta o la de los avisos de estrenos); al pasar de ~200 KB empieza otra.
    static func append(_ text: String, to file: URL = file) {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        if size > limit { try? FileManager.default.removeItem(at: file) }
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }
}
