import Foundation

/// Lo tuyo de un título, guardado en el teléfono: dónde ibas, qué episodios viste y si está en Mi lista. Es la verdad para la
/// pantalla; Trakt es la copia en la nube que comparten tus aparatos (`LibrarySync`) y Stremio, mientras dure la prueba, recibe
/// otra copia (`WatchService`).
public struct LibraryEntry: Sendable, Equatable, Codable {
    public var metaID: String
    public var kind: String              // movie | series
    /// El nombre ORIGINAL (Cinemeta o Trakt, en inglés): la pantalla lo traduce.
    public var name: String
    public var poster: String?
    /// El video en curso (o el siguiente episodio, con `nextUp`). En una serie que ibas al día, el último que viste.
    public var videoID: String?
    /// Segundos exactos donde te quedaste (0 = desde el principio o ya terminado).
    public var position: Double = 0
    /// Duración del video en segundos (0 si no se sabe). Si vino de Trakt sin duración conocida, es la de la ficha.
    public var duration: Double = 0
    /// El avance de Trakt (0–1) cuando no se sabía la duración exacta del archivo: al reproducir se busca con la del video.
    public var fraction: Double?
    /// Cuándo cambió dónde ibas (epoch): aquí al pausar o terminar; `paused_at` o `last_watched_at` si vino de Trakt.
    public var updatedAt: Double = 0
    /// Terminaste el anterior: toca este episodio desde el principio («Sigue: T2 E6»).
    public var nextUp = false
    /// Lo que viste (ids de episodio; en una película, su propio id). Se suma: lo visto en cualquier lado queda visto.
    public var seen: Set<String> = []
    public var inList = false
    public var listedAt: Double?
    /// Cuándo lo quitaste de «Seguir viendo». Vuelve solo si avanzas (aquí o en otro aparato) después de quitarlo.
    public var hiddenAt: Double?
    /// Cuándo se le mandó a Trakt tu avance de aquí: lo que Trakt devuelva hasta un poco después es eco de lo tuyo, no algo nuevo.
    public var pushedAt: Double?

    public var hidden: Bool { hiddenAt != nil }

    /// Hasta cuándo lo de aquí manda: lo que llegue de Trakt con una fecha anterior es viejo (o el eco de lo que mandó este teléfono).
    public var localStamp: Double { max(updatedAt, hiddenAt ?? 0, (pushedAt ?? 0) + LibraryMerge.echoMargin) }

    public init(metaID: String, kind: String, name: String, poster: String? = nil) {
        self.metaID = metaID; self.kind = kind; self.name = name; self.poster = poster
    }

    /// Tolerante con lo guardado antes: un campo nuevo no hace perder la biblioteca.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        metaID = try c.decode(String.self, forKey: .metaID); kind = try c.decode(String.self, forKey: .kind)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        poster = try c.decodeIfPresent(String.self, forKey: .poster); videoID = try c.decodeIfPresent(String.self, forKey: .videoID)
        position = try c.decodeIfPresent(Double.self, forKey: .position) ?? 0; duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        fraction = try c.decodeIfPresent(Double.self, forKey: .fraction); updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        nextUp = try c.decodeIfPresent(Bool.self, forKey: .nextUp) ?? false; seen = try c.decodeIfPresent(Set<String>.self, forKey: .seen) ?? []
        inList = try c.decodeIfPresent(Bool.self, forKey: .inList) ?? false; listedAt = try c.decodeIfPresent(Double.self, forKey: .listedAt)
        hiddenAt = try c.decodeIfPresent(Double.self, forKey: .hiddenAt); pushedAt = try c.decodeIfPresent(Double.self, forKey: .pushedAt)
    }
    enum Keys: String, CodingKey { case metaID, kind, name, poster, videoID, position, duration, fraction, updatedAt, nextUp, seen, inList, listedAt, hiddenAt, pushedAt }

    /// Dónde ibas, de 0 a 1 (nil si no ibas a medias).
    public var progress: Double? {
        guard !nextUp, position > 0 else { return nil }
        if let fraction { return fraction }
        return duration > 0 ? min(1, position / duration) : nil
    }

    /// ¿Va en «Seguir viendo»? A medias (desde el 1 %) o con el siguiente episodio listo; no si lo quitaste.
    public var inContinue: Bool {
        guard !hidden, videoID != nil, ["movie", "series"].contains(kind) else { return false }
        if nextUp { return kind == "series" }
        return (progress ?? 0) >= PlaybackRules.continueMinProgress
    }

    /// Para los modelos de pantalla: el mismo `Watchable` que antes salía de Stremio (tiempos en milisegundos).
    public var watchable: Watchable {
        let offset = hidden ? 0 : nextUp ? 1 : Int((position * 1000).rounded())
        let length = nextUp ? 0 : Int((duration * 1000).rounded())
        var w = Watchable(id: metaID, type: kind, name: name, poster: poster, videoID: videoID, timeOffset: offset, duration: length,
                          lastWatched: updatedAt > 0 ? updatedAt : listedAt, inContinue: inContinue, inLibrary: inList)
        w.seen = seen
        return w
    }

    /// Lo que pasa al terminar un video: queda visto y se pasa al siguiente episodio (o sale de «Seguir viendo»).
    public mutating func finish(videoID: String, next: String?, at: Double) {
        seen.insert(videoID)
        position = 0; duration = 0; fraction = nil; hiddenAt = nil; updatedAt = at
        if let next, kind == "series" { self.videoID = next; nextUp = true } else { self.videoID = videoID; nextUp = false }
    }
}

/// Dónde se guarda la biblioteca del teléfono: un archivo JSON en Application Support (o en memoria, en pruebas y en la demo).
public final class LocalLibrary: @unchecked Sendable {
    /// Algo cambió (aquí o al sincronizar): Inicio y la ficha se vuelven a pintar.
    public static let changed = Notification.Name("orbital.library-changed")

    private let url: URL?
    private let lock = NSLock()
    private var entries: [String: LibraryEntry]

    public init(url: URL? = nil) {
        self.url = url
        entries = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: LibraryEntry].self, from: $0) } ?? [:]
    }

    public var isEmpty: Bool { lock.withLock { entries.isEmpty } }
    public func entry(_ metaID: String) -> LibraryEntry? { lock.withLock { entries[metaID] } }
    public var all: [LibraryEntry] { lock.withLock { Array(entries.values) } }

    /// Cambia un título (o lo crea con `make`). Devuelve cómo quedó.
    @discardableResult
    public func update(_ metaID: String, make: () -> LibraryEntry, _ change: (inout LibraryEntry) -> Void) -> LibraryEntry {
        let result: LibraryEntry = lock.withLock {
            var entry = entries[metaID] ?? make()
            change(&entry)
            entries[metaID] = entry
            persist()
            return entry
        }
        return result
    }

    /// Varios cambios de una vez (una sincronización): se escribe el archivo una sola vez.
    public func batch(_ change: (inout [String: LibraryEntry]) -> Void) {
        lock.withLock { change(&entries); persist() }
    }

    /// Al cerrar la sesión de todo: el teléfono olvida lo tuyo.
    public func clear() { lock.withLock { entries = [:]; persist() } }

    private func persist() {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}
