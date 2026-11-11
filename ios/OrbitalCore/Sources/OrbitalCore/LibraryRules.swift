import Foundation

/// Las reglas de lo tuyo: cuándo algo ya se dio por visto, cuándo vuelve una serie, y el formato `libraryItem` (el de la
/// biblioteca que comparte la consola: `_mtime`, `state.video_id`, `timeOffset` en ms, el bitfield de vistos). Antes se llamaba
/// `LibraryRules` porque nació para escribir en la cuenta de Stremio; esa copia ya no existe (F8, 11 nov 2026) y estas reglas
/// siguen vivas para el teléfono (`LocalLibrary`, `LibraryMerge`) y los mensajes de la consola. Se portan de `stremio_api.py`
/// y se prueban con sus mismos casos.
public enum LibraryRules {
    /// Películas: mismo umbral que Stremio para dar algo por visto.
    public static let watchedAt = 0.9
    /// Episodios: visto solo en el último tramo (el 5 %, entre 45 s y 90 s). El 90 % de un episodio de Los Simpson (22 min)
    /// son los últimos 2 min 12 s, en plena escena final: uno quedó visto y salió de Seguir viendo antes de los créditos.
    public static let episodeTail = 0.05, episodeTailMin = 45.0, episodeTailMax = 90.0
    /// Una serie que ya ibas al día vuelve a Seguir viendo con su episodio nuevo si la viste en este plazo (días).
    public static let returnDays = 400.0
    /// Cuántas de esas series se revisan cada vez (las más recientes).
    public static let returnChecks = 30

    /// ¿Con esta posición ya se da por visto? (Segundos; sin duración, no.) Igual que `finished` de `stremio_api.py`.
    public static func finished(position: Double, duration: Double, kind: String?) -> Bool {
        guard duration > 0, duration.isFinite, position.isFinite else { return false }
        if kind == "series" {
            let tail = min(max(duration * episodeTail, episodeTailMin), episodeTailMax)
            return position >= duration - tail
        }
        return position >= duration * watchedAt
    }

    public static func iso(_ when: Double) -> String {
        let seconds = Int(floor(when))
        let millis = Int(floor(when * 1000)) % 1000
        let date = Date(timeIntervalSince1970: Double(seconds))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", c.year ?? 1970, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0, c.second ?? 0, millis)
    }

    public static func epoch(_ value: JSON?) -> Double? {
        guard let text = value?.nonEmptyString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)?.timeIntervalSince1970
    }

    /// Un número finito y no negativo (un NaN o infinito de un motor o de una URL no tumba nada).
    public static func finite(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }




    /// Los episodios vistos según Stremio (`state.watched`): «{video ancla}:{largo}:{bits en base64 de zlib}».
    public static func parseWatched(_ watched: String?, videoIDs: [String]) -> Set<String> {
        guard let watched, !watched.isEmpty, !videoIDs.isEmpty else { return [] }
        let parts = watched.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, let length = Int(parts[parts.count - 2]), (1...1_000_000).contains(length),
              let data = Data(base64Encoded: String(parts[parts.count - 1])),
              let bits = try? Zlib.decompress([UInt8](data)) else { return [] }
        let anchor = parts[0..<(parts.count - 2)].joined(separator: ":")
        let offset = videoIDs.firstIndex(of: anchor).map { (length - 1) - $0 } ?? 0
        var seen = Set<String>()
        for (i, video) in videoIDs.enumerated() {
            let bit = i + offset
            if bit >= 0, bit < bits.count * 8, (bits[bit >> 3] >> UInt8(bit & 7)) & 1 == 1 { seen.insert(video) }
        }
        return seen
    }




    /// «tt0944947:1:5» → (1, 5); «kitsu:123:7» → (nil, 7): el id del título puede tener «:» propios (kitsu:1).
    public static func episodeNumbers(videoID: String, metaID: String) -> (season: Int?, episode: Int?) {
        let rest = videoID.hasPrefix(metaID + ":") ? String(videoID.dropFirst(metaID.count + 1))
            : videoID.split(separator: ":", omittingEmptySubsequences: false).dropFirst().joined(separator: ":")
        let numbers = rest.split(separator: ":").filter { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }.compactMap { Int($0) }
        if numbers.count >= 2 { return (numbers[numbers.count - 2], numbers[numbers.count - 1]) }
        if numbers.count == 1 { return (nil, numbers[0]) }
        return (nil, nil)
    }


}

/// Un título de tu biblioteca o de «Seguir viendo».
public struct Watchable: Sendable, Equatable, Identifiable {
    public var id: String
    public var type: String
    public var name: String
    public var poster: String?
    public var videoID: String?
    public var timeOffset: Int
    public var duration: Int
    public var lastWatched: Double?
    public var inContinue: Bool
    public var inLibrary: Bool
    public var watched: String? = nil   // los episodios vistos, tal cual los guarda Stremio (parseWatched)
    public var seen: Set<String>? = nil // los episodios vistos ya leídos (la biblioteca del teléfono)
    public var isNew = false            // ibas al día y ya salió el episodio que sigue: «Nuevo»

    public var progress: Double? {
        guard duration > 0, timeOffset > 0 else { return nil }
        return min(1, Double(timeOffset) / Double(duration))
    }

    /// «tt0944947:1:5» → (1, 5); «kitsu:123:7» → (nil, 7).
    public var episode: (season: Int?, episode: Int?) {
        guard let videoID, type != "movie" else { return (nil, nil) }
        return LibraryRules.episodeNumbers(videoID: videoID, metaID: id)
    }

    public static func == (a: Watchable, b: Watchable) -> Bool {
        a.id == b.id && a.type == b.type && a.name == b.name && a.poster == b.poster && a.videoID == b.videoID
            && a.timeOffset == b.timeOffset && a.duration == b.duration && a.lastWatched == b.lastWatched
            && a.inContinue == b.inContinue && a.inLibrary == b.inLibrary && a.watched == b.watched && a.seen == b.seen && a.isNew == b.isNew
    }

    /// ¿Es una serie fuera de Seguir viendo que viste hace poco? (Quizá ibas al día y ya salió el episodio que sigue.)
    public func mayReturn(now: Double) -> Bool {
        guard type == "series", timeOffset <= 0, videoID != nil, let lastWatched else { return false }
        return now - lastWatched < LibraryRules.returnDays * 86400
    }

    /// La serie de vuelta en Seguir viendo con su episodio nuevo, en su lugar según cuándo salió. En Stremio no se escribe nada.
    public func returning(videoID: String, released: Double) -> Watchable {
        var w = self
        w.videoID = videoID; w.timeOffset = 1; w.duration = 0; w.lastWatched = released; w.inContinue = true; w.isNew = true
        return w
    }
}
