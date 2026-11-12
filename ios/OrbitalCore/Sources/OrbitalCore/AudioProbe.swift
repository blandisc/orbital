import Foundation

/// Revisar por dentro el audio de una versión sin abrirla (Fernando, 12 nov: «Sí, vamos a hacer la 2»): se leen solo los
/// primeros bytes de su MKV (las pistas) y se anota lo que de verdad trae, como si la hubieras visto.
///
/// Con cuidado, por Real-Debrid: solo las que arrancan al instante (pedir el enlace de una «por bajar» le pide a Real-Debrid
/// que la baje, R6), pocas (`limit`), una a la vez, nunca con el reproductor abierto (Real-Debrid no aguanta dos conexiones al
/// mismo archivo) y cada archivo una sola vez (lo que se supo queda en «Comprobado»; lo que no se pudo, no se repite).
public final class AudioProbe: @unchecked Sendable {
    public static let shared = AudioProbe(reader: URLSessionRangeReader())
    /// Cuántas se revisan cada vez que abres «Versión».
    public static let limit = 3
    /// Lo que se lee del principio (las pistas de un MKV caben de sobra) y, si su índice dice que están en otra parte, de ahí.
    static let headBytes = 512 * 1024, tracksBytes = 256 * 1024

    private let lock = NSLock()
    private var reader: RangeReader
    private var tried = Set<String>()
    private var tail: Task<Void, Never>?

    public init(reader: RangeReader) { self.reader = reader }

    /// Apagada no revisa nada. Así sale la app de verdad hasta que Fernando lo apruebe: pedir el enlace de una versión para
    /// leerla la agrega a su cuenta de Real-Debrid, y eso no se ha probado con su cuenta (12 nov 2026). Lo ya comprobado al
    /// reproducir y «Lo trajo otro episodio» siguen funcionando.
    public var isOn: Bool { lock.withLock { on } }
    public func turnOff() { lock.withLock { on = false } }
    private var on = true

    /// Otra forma de leer (la demostración, las pruebas).
    public func use(_ reader: RangeReader) { lock.withLock { self.reader = reader } }

    /// Ya se intentó en esta sesión (salió o no): no se repite.
    public func tried(_ key: String) -> Bool { lock.withLock { tried.contains(key) } }

    /// Las pistas de audio de esa versión, o nil si no se pudo (no es MKV, no contestó, no dejó leer un pedazo). En fila: si
    /// hay otra lectura en curso, espera a que termine.
    public func audioTracks(of source: Source) async -> [MediaTrack]? {
        guard let url = source.playbackURL else { return nil }
        let headers = source.requestHeaders
        let (previous, reader): (Task<Void, Never>?, RangeReader) = lock.withLock {
            tried.insert(source.key)
            if tried.count > 2000 { tried = [source.key] }
            return (tail, self.reader)
        }
        let work = Task { () -> [MediaTrack]? in
            await previous?.value
            guard !Task.isCancelled else { return nil }
            return await Self.read(url, headers: headers, reader: reader)
        }
        lock.withLock { tail = Task { _ = await work.value } }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    static func read(_ url: URL, headers: [String: String], reader: RangeReader) async -> [MediaTrack]? {
        guard let head = try? await reader.read(url, from: 0, count: headBytes, headers: headers) else { return nil }
        switch MatroskaTracks.read(head: head) {
        case .tracks(let tracks): return tracks
        case .unknown: return nil
        case .elsewhere(let offset):
            guard !Task.isCancelled, let data = try? await reader.read(url, from: offset, count: tracksBytes, headers: headers) else { return nil }
            return MatroskaTracks.read(tracksAt: data)
        }
    }

    /// Cuáles revisar: solo si tu idioma no está entre las que arrancan al instante (si ya está, no hace falta), las primeras
    /// `limit` que arrancan al instante, son MKV, no se han comprobado ni intentado y cuyo idioma es dudoso (lo supone el
    /// original, no dice nada o solo hay pistas débiles; también las «Multi» y «Dual», que suelen traer varias pistas).
    public static func candidates(_ ranked: [Source], wanted: String, limit: Int = AudioProbe.limit, tried: (String) -> Bool) -> [Source] {
        func speaks(_ code: String) -> Bool { code == wanted || (wanted.count == 2 && code.hasPrefix(wanted)) }
        let usable = ranked.filter { $0.instant && $0.playbackURL != nil && !$0.isOtherTitle && !$0.refused && !$0.tags.contains("CAM") && !$0.tags.contains("Tráiler") }
        if usable.contains(where: { s in s.audio.contains { speaks($0.code) && $0.evidence.solid } }) { return [] }
        return Array(usable.filter { s in
            guard isMatroska(s), !tried(s.key), !s.audio.contains(where: { $0.evidence == .checked }) else { return false }
            return s.audio.allSatisfy { [.original, .unknown, .maybe].contains($0.evidence) } || mentionsMulti(s)
        }.prefix(limit))
    }

    /// Un MKV, por su nombre, su archivo o su enlace.
    static func isMatroska(_ s: Source) -> Bool {
        let names = [s.release, s.stream["behaviorHints"]?["filename"]?.string ?? "", s.stream["title"]?.string ?? "", s.playbackURL?.path ?? ""]
        return names.contains { $0.lowercased().contains(".mkv") }
    }

    static func mentionsMulti(_ s: Source) -> Bool {
        let blob = "\(s.release) \(s.stream["title"]?.string ?? "") \(s.stream["name"]?.string ?? "")".lowercased()
        return blob.contains("multi") || blob.contains("dual")
    }
}

/// Leer un pedazo de un archivo en línea (`count` bytes desde `from`), sin bajar el resto.
public protocol RangeReader: Sendable {
    func read(_ url: URL, from: Int64, count: Int, headers: [String: String]) async throws -> Data
}

/// Con el cliente de la app (la demostración y las pruebas): un pedido con «Range». Un servidor que no respeta «Range» y manda
/// el archivo entero no sirve aquí: se descarta.
public struct HTTPRangeReader: RangeReader {
    let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }
    public func read(_ url: URL, from: Int64, count: Int, headers: [String: String]) async throws -> Data {
        var all = headers
        all["Range"] = "bytes=\(from)-\(from + Int64(count) - 1)"
        let response = try await http.send(HTTPRequest(url: url, headers: all, timeout: 8))
        guard response.status == 206 || (response.status == 200 && from == 0 && response.data.count <= count) else { throw NetworkError("HTTP \(response.status)") }
        return response.data.prefix(count)
    }
}

/// La de verdad: pide el pedazo y corta en cuanto llegan `count` bytes, aunque el servidor ignore «Range» (nunca baja el
/// archivo entero). Sesión efímera: los enlaces llevan tu clave.
public struct URLSessionRangeReader: RangeReader {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: config)
    }()
    public init() {}
    public func read(_ url: URL, from: Int64, count: Int, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("Orbital", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("bytes=\(from)-\(from + Int64(count) - 1)", forHTTPHeaderField: "Range")
        let (bytes, response) = try await Self.session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Sin «Range» (200) solo sirve si se pidió el principio; lo demás sería leer otra parte del archivo.
        guard status == 206 || (status == 200 && from == 0) else { bytes.task.cancel(); throw NetworkError("HTTP \(status)") }
        var data = Data(); data.reserveCapacity(count)
        for try await byte in bytes {
            data.append(byte)
            if data.count >= count { break }
        }
        bytes.task.cancel()
        return data
    }
}
