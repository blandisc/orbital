import Foundation

public enum StremioError: Error, Sendable, CustomStringConvertible {
    /// No se llegó a Stremio (sin internet, caído): no es que tus datos estén mal.
    case unreachable(String)
    case api(String)

    public var description: String {
        switch self { case .unreachable(let m), .api(let m): return m }
    }
}

/// Cliente de la API de Stremio (api.strem.io). No es oficial ni está documentada: el formato sale de
/// stremio-core. Si Stremio la cambia, falla aquí y en Orbital a la vez y se arregla en los dos.
public struct StremioAPI: Sendable {
    public static let defaultBase = URL(string: "https://api.strem.io")!
    let http: HTTPClient
    let base: URL

    /// Lecturas compartidas: la misma lectura a la vez (dos pantallas, la ficha y el reproductor) es una sola petición.
    let reads = StremioReads()
    /// Cuánto vale una lectura para solo leer (dónde ibas): lo que tarda abrir una ficha y darle a reproducir.
    public static let recentRead: TimeInterval = 60

    public init(http: HTTPClient, base: URL = StremioAPI.defaultBase) { self.http = http; self.base = base }

    /// Las lecturas (`datastoreGet`, `addonCollectionGet`) idénticas en vuelo comparten la petición; las escrituras van siempre.
    public func request(_ method: String, _ params: [String: JSON]) async throws -> JSON {
        guard StremioReads.shareable.contains(method) else { return try await send(method, params) }
        let body = JSON.object(params).serialized(sortedKeys: true)
        return try await reads.shared(method + "|" + String(decoding: body, as: UTF8.self)) { try await send(method, params) }
    }

    private func send(_ method: String, _ params: [String: JSON]) async throws -> JSON {
        let body = JSON.object(params).serialized()
        let url = base.appendingPathComponent("api/\(method)")
        let response: HTTPResponse
        do {
            response = try await http.send(HTTPRequest(url: url, method: "POST", headers: ["Content-Type": "application/json"], body: body, timeout: 8))
        } catch let error as NetworkError {
            throw StremioError.unreachable("No pude conectar con Stremio: \(error)")
        }
        guard response.status < 400 else { throw StremioError.unreachable("Stremio respondió HTTP \(response.status)") }
        guard let json = JSON.parse(response.data), case .object(let object) = json else {
            throw StremioError.api("Respuesta de Stremio sin resultado")
        }
        if let error = object["error"], !error.isNull, error != .bool(false) {
            throw StremioError.api(error["message"]?.nonEmptyString ?? error.string ?? "Error de Stremio")
        }
        guard let result = object["result"] else { throw StremioError.api("Respuesta de Stremio sin resultado") }
        return result
    }

    public func login(email: String, password: String) async throws -> String {
        let result = try await request("login", ["type": "Login", "email": .string(email), "password": .string(password), "facebook": false])
        guard let key = result["authKey"]?.nonEmptyString else { throw StremioError.api("Stremio no devolvió la clave de sesión") }
        return key
    }

    public func library(authKey: String) async throws -> [JSON] {
        let generation = await reads.generation
        let result = try await request("datastoreGet", ["authKey": .string(authKey), "collection": "libraryItem", "ids": [], "all": true])
        let items = (result.array ?? []).filter { $0.object != nil }
        await reads.remember(authKey: authKey, items: items, complete: true, generation: generation)
        return items
    }

    /// `maxAge`: solo para LEER (dónde ibas, el ✓ de visto): reusa lo que se trajo hace menos de esos segundos (la biblioteca
    /// completa o el mismo elemento) en vez de volver a preguntar. Lo que lee para luego escribir pide siempre lo de Stremio.
    public func libraryItem(authKey: String, id: String, maxAge: TimeInterval = 0) async throws -> JSON? {
        if maxAge > 0, let recent = await reads.recentItem(authKey: authKey, id: id, maxAge: maxAge) { return recent }
        let generation = await reads.generation
        let result = try await request("datastoreGet", ["authKey": .string(authKey), "collection": "libraryItem", "ids": [.string(id)], "all": false])
        let item = (result.array ?? []).first { $0["_id"]?.string == id }
        await reads.remember(authKey: authKey, items: item.map { [$0] } ?? [], complete: false, asked: id, generation: generation)
        return item
    }

    public func saveLibraryItem(authKey: String, item: JSON) async throws {
        await reads.forget()
        defer { Task { await reads.forget() } }
        _ = try await request("datastorePut", ["authKey": .string(authKey), "collection": "libraryItem", "changes": [item]])
    }

    /// Los complementos de tu cuenta (`addonCollectionGet`).
    public func addonCollection(authKey: String) async throws -> JSON {
        try await request("addonCollectionGet", ["authKey": .string(authKey), "update": true])
    }
}

/// Lo que comparten las copias de `StremioAPI` (es un struct): las lecturas en vuelo y los elementos leídos hace poco.
public actor StremioReads {
    static let shareable: Set<String> = ["datastoreGet", "addonCollectionGet"]
    private var inflight: [String: Task<JSON, Error>] = [:]
    /// authKey → id → (cuándo, el elemento o nil si Stremio no lo tiene).
    private var items: [String: [String: (at: Date, item: JSON?)]] = [:]
    /// Cuándo se trajo la biblioteca completa (un id que no venía ahí es que no está).
    private var complete: [String: Date] = [:]
    /// Sube con cada escritura: lo que se leyó antes de escribir ya no se recuerda ni se comparte.
    private(set) var generation = 0
    private let clock: @Sendable () -> Date

    init(clock: @escaping @Sendable () -> Date = { Date() }) { self.clock = clock }

    func shared(_ key: String, _ work: @escaping @Sendable () async throws -> JSON) async throws -> JSON {
        if let running = inflight[key] { return try await running.value }
        let task = Task { try await work() }
        inflight[key] = task
        defer { inflight[key] = nil }
        return try await task.value
    }

    func remember(authKey: String, items new: [JSON], complete full: Bool, asked: String? = nil, generation: Int) {
        guard generation == self.generation else { return }
        let now = clock()
        if full { items[authKey] = [:]; complete[authKey] = now }
        for item in new { if let id = item["_id"]?.string { items[authKey, default: [:]][id] = (now, item) } }
        if let asked, !new.contains(where: { $0["_id"]?.string == asked }) { items[authKey, default: [:]][asked] = (now, nil) }
    }

    /// `.some(nil)`: se sabe que Stremio no lo tiene; `nil`: no hay nada reciente.
    func recentItem(authKey: String, id: String, maxAge: TimeInterval) -> JSON?? {
        let now = clock()
        if let hit = items[authKey]?[id], now.timeIntervalSince(hit.at) < maxAge { return .some(hit.item) }
        if let at = complete[authKey], now.timeIntervalSince(at) < maxAge, items[authKey]?[id] == nil { return .some(nil) }
        return nil
    }

    func forget() { items = [:]; complete = [:]; inflight = [:]; generation += 1 }
}

// MARK: - Lo que se guarda en la biblioteca de Stremio

/// Funciones puras sobre el `libraryItem` (se portan de `stremio_api.py`; se prueban con sus mismos casos).
public enum StremioLibrary {
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
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, millis)
    }

    public static func epoch(_ value: JSON?) -> Double? {
        guard let text = value?.nonEmptyString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)?.timeIntervalSince1970
    }

    public static func state(of raw: JSON?) -> [String: JSON] { raw?["state"]?.object ?? [:] }

    /// Un número finito y no negativo (un NaN o infinito de un motor o de una URL no tumba nada).
    public static func finite(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }

    /// Segundos → milisegundos enteros, acotados (un valor absurdo no desborda el entero).
    static func ms(_ seconds: Double) -> Int { Int(min(finite(seconds), 1e9) * 1000) }

    /// Dónde ibas en ese episodio o película según Stremio (0 = desde el principio).
    public static func resumeSeconds(_ raw: JSON?, videoID: String) -> Double {
        let state = state(of: raw)
        guard state["video_id"]?.string == videoID else { return 0 }
        let offset = asInt(state["timeOffset"]), duration = asInt(state["duration"])
        if offset <= 0 || finished(position: Double(offset) / 1000, duration: Double(duration) / 1000, kind: raw?["type"]?.string) { return 0 }
        return Double(offset) / 1000
    }

    private static var defaultHints: JSON {
        ["defaultVideoId": nil, "featuredVideoId": nil, "hasScheduledVideos": false]
    }

    /// El libraryItem de Stremio con lo que viste (para «Seguir viendo» en todos lados). Se parte del que ya
    /// existe y solo se toca `state`; si no existía, se crea como `temp`. Tiempos en milisegundos.
    /// `name` debe ser el título ORIGINAL (el de Cinemeta), nunca el traducido.
    public static func withProgress(_ raw: JSON?, metaID: String, kind: String, name: String, poster: String?, videoID: String,
                                    position: Double, duration: Double, watched: Double, nextVideo: String?, now: Double,
                                    videoIDs: [String]? = nil) -> JSON {
        var item: [String: JSON] = raw?.object ?? [
            "_id": .string(metaID), "name": .string(name), "type": .string(kind), "poster": poster.map(JSON.string) ?? .null,
            "posterShape": "poster", "removed": true, "temp": true, "_ctime": .string(iso(now)), "behaviorHints": defaultHints,
        ]
        var state = state(of: .object(item))
        if state["video_id"]?.string != videoID { state["timeWatched"] = 0 }
        let posMs = ms(position), durMs = ms(duration), watchedMs = ms(watched)
        state["lastWatched"] = .string(iso(now))
        state["video_id"] = .string(videoID)
        state["duration"] = .int(durMs)
        state["timeOffset"] = .int(posMs)
        state["timeWatched"] = .int(asInt(state["timeWatched"]) + watchedMs)
        state["overallTimeWatched"] = .int(asInt(state["overallTimeWatched"]) + watchedMs)
        if state["timesWatched"] == nil { state["timesWatched"] = 0 }
        if state["flaggedWatched"] == nil { state["flaggedWatched"] = 0 }
        if state["noNotif"] == nil { state["noNotif"] = false }
        if finished(position: Double(posMs) / 1000, duration: Double(durMs) / 1000, kind: kind) {
            state["timesWatched"] = .int(asInt(state["timesWatched"]) + 1)
            state["flaggedWatched"] = 1
            if let ids = videoIDs, ids.contains(videoID) {  // ✓ en ese episodio, en Orbital y en Stremio
                var seen = parseWatched(state["watched"]?.string, videoIDs: ids)
                seen.insert(videoID)
                if let encoded = encodeWatched(seen, videoIDs: ids) { state["watched"] = .string(encoded) }
            }
            if let next = nextVideo {  // sigue en «Seguir viendo», ya en el siguiente episodio
                state["video_id"] = .string(next); state["timeOffset"] = 1; state["timeWatched"] = 0; state["duration"] = 0
            } else {
                state["timeOffset"] = 0  // terminada: sale de «Seguir viendo»
            }
        }
        item["state"] = .object(state)
        item["_mtime"] = .string(iso(now))
        return .object(item)
    }

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

    public static func encodeWatched(_ seen: Set<String>, videoIDs: [String]) -> String? {
        let marks = videoIDs.enumerated().filter { seen.contains($0.element) }.map(\.offset)
        guard let lastMark = marks.last else { return nil }
        let length = lastMark + 1
        var bits = [UInt8](repeating: 0, count: (length + 7) / 8)
        for i in marks { bits[i >> 3] |= 1 << UInt8(i & 7) }
        let encoded = Data(Zlib.compressStored(bits)).base64EncodedString()
        return "\(videoIDs[lastMark]):\(length):\(encoded)"
    }

    /// El libraryItem dentro o fuera de tu biblioteca («Mi lista»): `removed` y `temp`; el avance no se toca.
    public static func libraryToggled(_ raw: JSON?, metaID: String, kind: String, name: String, poster: String?, add: Bool, now: Double) -> JSON {
        var item: [String: JSON] = raw?.object ?? [
            "_id": .string(metaID), "name": .string(name), "type": .string(kind), "poster": poster.map(JSON.string) ?? .null,
            "posterShape": "poster", "_ctime": .string(iso(now)), "state": [:], "behaviorHints": defaultHints,
        ]
        item["removed"] = .bool(!add)
        item["temp"] = .bool(add ? false : (item["temp"].map(truthy) ?? false))
        item["_mtime"] = .string(iso(now))
        return .object(item)
    }

    /// ¿Está en tu biblioteca de Stremio («Mi lista»)? Ni quitado ni temporal.
    public static func isInLibrary(_ raw: JSON?) -> Bool {
        guard let raw else { return false }
        return !(raw["removed"].map(truthy) ?? false) && !(raw["temp"].map(truthy) ?? false)
    }

    /// Marca un video como visto sin tocar el resto: solo el bitfield de `state.watched`. Si ese video es justo el que Stremio
    /// tenía como actual (o no había ninguno), el puntero pasa al siguiente, como al terminarlo.
    public static func markWatched(_ raw: JSON?, metaID: String, kind: String, name: String, poster: String?, videoID: String,
                                   videoIDs: [String], nextVideo: String?, now: Double) -> JSON {
        var item: [String: JSON] = raw?.object ?? [
            "_id": .string(metaID), "name": .string(name), "type": .string(kind), "poster": poster.map(JSON.string) ?? .null,
            "posterShape": "poster", "removed": true, "temp": true, "_ctime": .string(iso(now)), "behaviorHints": defaultHints,
        ]
        var state = state(of: .object(item))
        if videoIDs.contains(videoID) {
            var seen = parseWatched(state["watched"]?.string, videoIDs: videoIDs)
            seen.insert(videoID)
            if let encoded = encodeWatched(seen, videoIDs: videoIDs) { state["watched"] = .string(encoded) }
        }
        let current = state["video_id"]?.nonEmptyString
        if current == nil || current == videoID {
            state["timesWatched"] = .int(asInt(state["timesWatched"]) + 1)
            state["flaggedWatched"] = 1
            if let next = nextVideo { state["video_id"] = .string(next); state["timeOffset"] = 1; state["timeWatched"] = 0; state["duration"] = 0 }
            else { state["video_id"] = .string(videoID); state["timeOffset"] = 0 }
        }
        if state["timesWatched"] == nil { state["timesWatched"] = 0 }
        if state["flaggedWatched"] == nil { state["flaggedWatched"] = 0 }
        if state["noNotif"] == nil { state["noNotif"] = false }
        item["state"] = .object(state)
        item["_mtime"] = .string(iso(now))
        return .object(item)
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

    /// El libraryItem fuera de «Seguir viendo» (como el «Quitar» de Stremio). Con `videoID` (quitaste una serie que había vuelto
    /// con su episodio nuevo), apunta a ese episodio para que no vuelva otra vez.
    public static func dismissed(_ raw: JSON, now: Double, videoID: String? = nil) -> JSON {
        var item = raw.object ?? [:]
        var state = state(of: raw)
        state["timeOffset"] = 0
        if let videoID { state["video_id"] = .string(videoID) }
        item["state"] = .object(state)
        item["_mtime"] = .string(iso(now))
        return .object(item)
    }

    public static func truthy(_ value: JSON) -> Bool {
        switch value {
        case .null: return false
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .double(let d): return d != 0
        case .string(let s): return !s.isEmpty
        case .array(let a): return !a.isEmpty
        case .object(let o): return !o.isEmpty
        }
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
    public var isNew = false            // ibas al día y ya salió el episodio que sigue: «Nuevo»

    public var progress: Double? {
        guard duration > 0, timeOffset > 0 else { return nil }
        return min(1, Double(timeOffset) / Double(duration))
    }

    /// «tt0944947:1:5» → (1, 5); «kitsu:123:7» → (nil, 7).
    public var episode: (season: Int?, episode: Int?) {
        guard let videoID, type != "movie" else { return (nil, nil) }
        return StremioLibrary.episodeNumbers(videoID: videoID, metaID: id)
    }

    public static func == (a: Watchable, b: Watchable) -> Bool {
        a.id == b.id && a.type == b.type && a.name == b.name && a.poster == b.poster && a.videoID == b.videoID
            && a.timeOffset == b.timeOffset && a.duration == b.duration && a.lastWatched == b.lastWatched
            && a.inContinue == b.inContinue && a.inLibrary == b.inLibrary && a.watched == b.watched && a.isNew == b.isNew
    }

    /// ¿Es una serie fuera de Seguir viendo que viste hace poco? (Quizá ibas al día y ya salió el episodio que sigue.)
    public func mayReturn(now: Double) -> Bool {
        guard type == "series", timeOffset <= 0, videoID != nil, let lastWatched else { return false }
        return now - lastWatched < StremioLibrary.returnDays * 86400
    }

    /// La serie de vuelta en Seguir viendo con su episodio nuevo, en su lugar según cuándo salió. En Stremio no se escribe nada.
    public func returning(videoID: String, released: Double) -> Watchable {
        var w = self
        w.videoID = videoID; w.timeOffset = 1; w.duration = 0; w.lastWatched = released; w.inContinue = true; w.isNew = true
        return w
    }
}

extension StremioLibrary {
    public static func parseItem(_ raw: JSON) -> Watchable? {
        guard raw.object != nil, let id = raw["_id"]?.nonEmptyString else { return nil }
        var name: String?
        switch raw["name"] {
        case .string(let s)?: name = s
        case .int(let i)?: name = String(i)  // «1917»: el título es un número
        case .double(let d)?: name = d == d.rounded() && abs(d) < 9e15 ? String(Int(d)) : String(d)
        default: name = nil
        }
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let state = state(of: raw)
        let kind = raw["type"]?.nonEmptyString ?? "other"
        let removed = raw["removed"].map(truthy) ?? false, temp = raw["temp"].map(truthy) ?? false
        let offset = asInt(state["timeOffset"])
        if removed && !temp { return nil }
        return Watchable(
            id: id, type: kind, name: name, poster: raw["poster"]?.nonEmptyString, videoID: state["video_id"]?.nonEmptyString,
            timeOffset: offset, duration: asInt(state["duration"]), lastWatched: epoch(state["lastWatched"]),
            // Misma regla que stremio-core (LibraryItem::is_in_continue_watching).
            inContinue: kind != "other" && offset > 0, inLibrary: !removed && !temp, watched: state["watched"]?.nonEmptyString)
    }

    /// Tu biblioteca, lo último visto primero.
    public static func parseLibrary(_ raws: [JSON]) -> [Watchable] {
        raws.compactMap(parseItem).sorted { ($0.lastWatched ?? 0) > ($1.lastWatched ?? 0) }
    }
}
