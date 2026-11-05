import Foundation

/// ST6 (Fernando, 5 nov 2026): el video se baja como las descargas, en pedazos y con varias conexiones a la vez, delante de
/// lo que estás viendo. Medido en su iPhone: Real-Debrid da 15.8 MB/s con una conexión y 50 MB/s con ocho; el reproductor
/// leía con una sola y un 4K HDR (8–10 MB/s) se quedaba sin colchón con cualquier bajón.
///
/// Cada pedazo va a su propio archivo temporal (se borran los que quedan lejos de donde vas: una película de 60 GB no se
/// queda en el disco). El que alguien está esperando va primero; luego, en orden, los que siguen al lector principal
/// (el que más ha leído: el que va reproduciendo, no los que leen el final del archivo o los subtítulos) hasta el colchón.
public actor ParallelStream {
    public struct Config: Sendable, Equatable {
        /// Conexiones a la vez (8 con Wi-Fi, 4 con datos).
        public var connections: Int
        /// Tamaño de cada pedazo: chico, para que lo que el reproductor necesita ya (el arranque, un salto, el final del
        /// archivo) llegue pronto.
        public var chunkBytes: Int
        /// Lo de adelante (el colchón) se pide de a varios pedazos seguidos por conexión: menos saludos con el servidor.
        public var runChunks = 4
        /// El colchón: cuántos segundos por delante (2 min con Wi-Fi, 30 s con datos, ST2).
        public var aheadSeconds: Double
        /// Mientras no se sabe cuánto pesa cada segundo, el colchón en bytes.
        public var fallbackAheadBytes: Int
        /// Lo que se guarda detrás de donde vas (un salto atrás de unos segundos no vuelve a la red).
        public var behindBytes: Int

        public static let wifi = Config(connections: 8, chunkBytes: 1 << 20, aheadSeconds: 120, fallbackAheadBytes: 400 << 20, behindBytes: 24 << 20)
        public static let cellular = Config(connections: 4, chunkBytes: 1 << 20, aheadSeconds: 30, fallbackAheadBytes: 60 << 20, behindBytes: 8 << 20)

        public init(connections: Int, chunkBytes: Int, aheadSeconds: Double, fallbackAheadBytes: Int, behindBytes: Int) {
            self.connections = connections; self.chunkBytes = chunkBytes; self.aheadSeconds = aheadSeconds
            self.fallbackAheadBytes = fallbackAheadBytes; self.behindBytes = behindBytes
        }
    }

    /// Un pedazo de la red: los bytes, el tamaño total (de `Content-Range`) y la dirección final (tras las redirecciones de
    /// Torrentio a Real-Debrid: los demás pedazos van directo ahí).
    public struct Piece: Sendable { public var data: Data; public var total: Int?; public var finalURL: URL?
        public init(data: Data, total: Int?, finalURL: URL?) { self.data = data; self.total = total; self.finalURL = finalURL } }
    public typealias Fetch = @Sendable (_ url: URL, _ range: ClosedRange<Int>) async throws -> Piece

    public enum Failure: Error, Equatable { case closed, refused(Int), empty }

    private let fetch: Fetch
    private var url: URL
    public let config: Config
    private let folder: URL
    public private(set) var total: Int?
    private var duration: Double?
    private var connections: Int
    private var done: Set<Int> = []
    private var inflight: [Int: Task<Void, Never>] = [:]
    private var waiters: [Int: [CheckedContinuation<Void, Error>]] = [:]
    private var tries: [Int: Int] = [:]
    /// Dónde va cada lector y cuánto ha leído (el principal es el que más).
    private var readers: [Int: (at: Int, read: Int)] = [:]
    private var closed = false
    /// Para el diagnóstico (y las pruebas): cuántos pedazos se pidieron a la red.
    public private(set) var fetched = 0

    public init(url: URL, config: Config, folder: URL, fetch: @escaping Fetch) {
        self.url = url; self.config = config; self.folder = folder; self.fetch = fetch; connections = max(1, config.connections)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Cuánto dura el video (cuando el motor lo sabe): con eso el colchón se mide en segundos.
    public func setDuration(_ seconds: Double) { if seconds > 0 { duration = seconds; schedule() } }

    /// El colchón en bytes: los segundos pedidos al peso de cada segundo de este archivo.
    var aheadBytes: Int {
        guard let total, let duration, duration > 0 else { return config.fallbackAheadBytes }
        return min(Int(Double(total) / duration * config.aheadSeconds), 2 << 30)
    }

    /// El tamaño del archivo (pide el primer pedazo si aún no se sabe).
    public func size() async throws -> Int {
        if let total { return total }
        try await wait(0)
        guard let total else { throw Failure.empty }
        return total
    }

    /// Hasta `maxLength` bytes desde `offset` (a lo más lo que queda del pedazo). `reader`: quién lee (cada respuesta del
    /// intermediario es uno).
    public func read(offset: Int, maxLength: Int, reader: Int) async throws -> Data {
        let chunk = config.chunkBytes, index = offset / chunk
        let before = readers[reader]
        readers[reader] = (offset, (before?.read ?? 0))
        try await wait(index)
        guard let data = try? Data(contentsOf: file(index)) else {   // se borró mientras: se vuelve a pedir
            done.remove(index)
            try await wait(index)
            return try await read(offset: offset, maxLength: maxLength, reader: reader)
        }
        let start = offset - index * chunk
        guard start < data.count else { return Data() }
        let piece = data.subdata(in: start..<min(data.count, start + maxLength))
        readers[reader] = (offset + piece.count, (readers[reader]?.read ?? 0) + piece.count)
        schedule()
        return piece
    }

    /// Ese lector terminó (su respuesta se cerró).
    public func finished(reader: Int) { readers[reader] = nil }

    /// Se acabó el video: se cancela lo que va en camino y se borran los pedazos.
    public func close() {
        closed = true
        for task in inflight.values { task.cancel() }
        inflight = [:]
        for (_, list) in waiters { for c in list { c.resume(throwing: Failure.closed) } }
        waiters = [:]
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ index: Int) -> URL { folder.appendingPathComponent("\(index).part") }
    private var lastIndex: Int { total.map { max(0, ($0 - 1) / config.chunkBytes) } ?? Int.max }

    private func wait(_ index: Int) async throws {
        if closed { throw Failure.closed }
        if done.contains(index) { return }
        guard index <= lastIndex else { throw Failure.empty }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            waiters[index, default: []].append(c)
            schedule()
        }
    }

    /// El lector principal: el que más ha leído (el que va reproduciendo).
    private var primary: Int? { readers.max { $0.value.read < $1.value.read }?.value.at }

    private func schedule() {
        guard !closed else { return }
        let chunk = config.chunkBytes
        var wanted = waiters.keys.sorted()
        if let at = primary {
            let first = at / chunk, last = min(lastIndex, (at + aheadBytes) / chunk)
            if first <= last { wanted += Array(first...last) }
        }
        let waited = Set(waiters.keys)
        var busy = Set(inflight.values).count
        for index in wanted where busy < connections && !done.contains(index) && inflight[index] == nil && index <= lastIndex {
            // Lo que alguien espera, solo (llega antes); lo de adelante, de a `runChunks` seguidos.
            var last = index
            if !waited.contains(index) {
                while last - index + 1 < config.runChunks, last + 1 <= lastIndex, !done.contains(last + 1), inflight[last + 1] == nil,
                      !waited.contains(last + 1), wanted.contains(last + 1) { last += 1 }
            }
            let task = Task { await self.run(index...last) }
            for i in index...last { inflight[i] = task }
            busy += 1
        }
        evict()
    }

    private func run(_ indices: ClosedRange<Int>) async {
        let chunk = config.chunkBytes, low = indices.lowerBound * chunk, index = indices.lowerBound
        let high = (total.map { min($0, (indices.upperBound + 1) * chunk) } ?? (indices.upperBound + 1) * chunk) - 1
        do {
            fetched += 1
            let piece = try await fetch(url, low...high)
            if closed { return }
            guard !piece.data.isEmpty else { throw Failure.empty }
            if let final = piece.finalURL { url = final }
            if let size = piece.total { total = size }
            for i in indices {
                let start = (i - indices.lowerBound) * chunk
                guard start < piece.data.count else { inflight[i] = nil; continue }
                try piece.data.subdata(in: start..<min(piece.data.count, start + chunk)).write(to: file(i))
                done.insert(i); tries[i] = nil; inflight[i] = nil
                for c in waiters.removeValue(forKey: i) ?? [] { c.resume() }
            }
        } catch {
            for i in indices { inflight[i] = nil }
            if closed { return }
            // Real-Debrid dice «demasiadas»: se baja a la mitad (como mucho hasta una conexión) en vez de insistir.
            if case Failure.refused(let status) = error, status == 429 || status == 503 || status == 509 { connections = max(1, connections / 2) }
            let count = (tries[index] ?? 0) + 1
            tries[index] = count
            // Lo que el reproductor espera se reintenta más (6 veces, ~8 s): rendirse es un tropiezo en la película.
            // Al abrir (aún sin una sola respuesta), a los 3: el reproductor abre directo sin esperar.
            if count >= (total == nil ? 3 : 6) || waiters[index] == nil && count >= 2 {
                for c in waiters.removeValue(forKey: index) ?? [] { c.resume(throwing: error) }
                if waiters[index] == nil { tries[index] = nil }
            } else {
                try? await Task.sleep(nanoseconds: UInt64(count) * 400_000_000)
            }
        }
        schedule()
    }

    /// Se borran los pedazos lejos de todos los lectores (detrás de su colchón de atrás o más allá del de adelante).
    private func evict() {
        guard !readers.isEmpty else { return }   // aún nadie lee (solo se preguntó el tamaño): nada está lejos
        let chunk = config.chunkBytes, ahead = aheadBytes
        let keep = readers.values.map { r in ((r.at - config.behindBytes) / chunk)...((r.at + ahead) / chunk + 1) }
        for index in done where !keep.contains(where: { $0.contains(index) }) && waiters[index] == nil {
            done.remove(index)
            try? FileManager.default.removeItem(at: file(index))
        }
    }
}

/// ST5 (Fernando, 5 nov): al abrir la ficha, la versión que va a sonar se le pide a Real-Debrid (un solo byte): Torrentio
/// resuelve el enlace y abre la conexión con su servidor, que se queda abierta en la misma sesión con que luego lee el
/// reproductor. Al dar «Ver» ya no se espera ese saludo. Una vez por enlace cada 10 min; nunca baja el video.
public enum StreamWarmup {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var warmed: [String: Date] = [:]

    @discardableResult
    public static func warm(_ url: URL, session: URLSession = ParallelStream.session, now: Date = Date()) -> Bool {
        guard url.scheme == "https" || url.scheme == "http" else { return false }
        let fresh: Bool = lock.withLock {
            if let at = warmed[url.absoluteString], now.timeIntervalSince(at) < 600 { return false }
            if warmed.count > 200 { warmed.removeAll() }
            warmed[url.absoluteString] = now
            return true
        }
        guard fresh else { return false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        for (k, v) in PlaybackHeaders.headers(for: url) { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        session.dataTask(with: request).resume()
        return true
    }
}
