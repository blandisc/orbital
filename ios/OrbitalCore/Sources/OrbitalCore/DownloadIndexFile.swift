import Foundation
import os

/// El índice de descargas en disco (`downloads.json`, sin enlaces: esos van en el Keychain).
///
/// Revisión del 11 nov 2026: si el índice falta o está dañado, las descargas siguen en la carpeta pero ya no se veían. Ahora se
/// reconstruye desde la carpeta (lo que dice cada carpeta: el título, el episodio, el tamaño y sus subtítulos). Un índice que solo
/// no se pudo leer ahora (el iPhone bloqueado) no se pisa: lo reconstruido vive en memoria y, al poder leerlo, manda el archivo.
public final class DownloadIndexFile: Sendable {
    private let url: URL
    private let root: URL
    private let read: @Sendable (URL) -> StoredRead<[DownloadItem]>
    private struct State {
        /// No se pudo leer al abrir: no se escribe encima hasta poder.
        var unread = false
        /// Las que se armaron desde la carpeta (si luego se puede leer el índice, el suyo es mejor).
        var rebuiltIDs: Set<String> = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    public convenience init(url: URL, root: URL) {
        self.init(url: url, root: root, read: { StoredFile.load([DownloadItem].self, from: $0, what: "el índice de descargas") })
    }

    init(url: URL, root: URL, read: @escaping @Sendable (URL) -> StoredRead<[DownloadItem]>) {
        self.url = url; self.root = root; self.read = read
    }

    public func load() -> [DownloadItem] {
        state.withLock { state in
            switch read(url) {
            case .loaded(let items): return items
            case .missing, .corrupt: return rebuild(&state)
            case .unreadable: state.unread = true; return rebuild(&state)
            }
        }
    }

    /// true si quedó en disco. Si al abrir no se pudo leer, primero se intenta leer: lo del índice gana sobre lo reconstruido.
    @discardableResult
    public func save(_ items: [DownloadItem]) -> Bool {
        state.withLock { state in
            var items = items
            if state.unread {
                switch read(url) {
                case .unreadable: return false   // nunca se pisa lo que no se pudo leer
                case .loaded(let onDisk):
                    let saved = Dictionary(onDisk.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    items = items.map { state.rebuiltIDs.contains($0.id) ? saved[$0.id] ?? $0 : $0 }
                    items += onDisk.filter { disk in !items.contains { $0.id == disk.id } }
                case .missing, .corrupt: break
                }
                state.unread = false
            }
            return StoredFile.write(items, to: url, what: "el índice de descargas")
        }
    }

    /// Lo que hay en la carpeta (`<título>/<video>/video.<ext>`, `DownloadFiles.relativePath`) como descargas terminadas.
    private func rebuild(_ state: inout State) -> [DownloadItem] {
        let found = Self.scan(root: root)
        state.rebuiltIDs = Set(found.map(\.id))
        if !found.isEmpty { Log.storage.error("El índice de descargas faltaba o no se pudo leer: se armó con las \(found.count, privacy: .public) de la carpeta") }
        return found
    }

    /// Las descargas que hay en `root`, sin índice.
    public static func scan(root: URL) -> [DownloadItem] {
        let fm = FileManager.default
        var out: [DownloadItem] = []
        for meta in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted() where !meta.hasPrefix(".") && !meta.hasPrefix("_") {
            let metaFolder = root.appendingPathComponent(meta)
            for video in ((try? fm.contentsOfDirectory(atPath: metaFolder.path)) ?? []).sorted() where !video.hasPrefix(".") {
                let folder = metaFolder.appendingPathComponent(video)
                guard let file = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().first(where: { $0.hasPrefix("video.") }) else { continue }
                let attributes = (try? fm.attributesOfItem(atPath: folder.appendingPathComponent(file).path)) ?? [:]
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                let created = (attributes[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
                let videoID = Self.videoID(folder: video, meta: meta)
                let kind = videoID == meta ? "movie" : "series"
                var item = DownloadItem(id: "\(meta)|\(videoID)", kind: kind, metaID: meta, videoID: videoID, title: meta, originalTitle: "",
                                        subtitle: "", poster: nil, addon: "", sourceIndex: 0, expectedBytes: size,
                                        relativePath: "\(meta)/\(video)/\(file)", createdAt: created)
                item.writtenBytes = size
                item.state = .done
                item.finishedAt = created
                let subs = ((try? fm.contentsOfDirectory(atPath: folder.appendingPathComponent("subs").path)) ?? []).sorted()
                item.subtitleFiles = subs.filter { $0.hasSuffix(".srt") || $0.hasSuffix(".vtt") }.map { "subs/\($0)" }
                out.append(item)
            }
        }
        return out
    }

    /// La carpeta guarda el id con «_» en vez de «:» (`DownloadFiles.component`): «tt0386676_2_5» → «tt0386676:2:5».
    static func videoID(folder: String, meta: String) -> String {
        guard folder != meta, folder.hasPrefix(meta + "_") else { return folder }
        let rest = folder.dropFirst(meta.count + 1).split(separator: "_", omittingEmptySubsequences: false)
        guard rest.count == 2, rest.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return folder }
        return "\(meta):\(rest[0]):\(rest[1])"
    }
}
