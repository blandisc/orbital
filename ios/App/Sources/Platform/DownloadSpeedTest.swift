import Foundation
import OrbitalCore
import OrbitalModels

/// Ajustes › Descargas › «Probar la velocidad»: de dónde viene la lentitud. Mide, unos segundos cada una y sin guardar nada:
/// tu internet sin Real-Debrid (un archivo de prueba de OVH, en Francia como los servidores de Real-Debrid), Real-Debrid con una conexión, con ocho (como baja la app abierta), y con la app cerrada (la sesión de
/// segundo plano de iOS, con sus cuatro pedazos). Con eso se sabe si el tope es tu red, Real-Debrid o iOS.
@MainActor
final class DownloadSpeedTest: ObservableObject {
    struct Row: Identifiable, Equatable {
        enum Kind: String, CaseIterable { case internet, single, eight, background }
        let kind: Kind
        var bytesPerSecond: Double?
        var failed: String?
        var running = false
        var id: String { kind.rawValue }
    }

    @Published private(set) var rows: [Row] = Row.Kind.allCases.map { Row(kind: $0) }
    @Published private(set) var running = false
    /// La fuente con que se probó («Shawshank · 1080p · 2.4 GB»), o por qué no se pudo.
    @Published private(set) var sourceName: String?
    @Published private(set) var problem: String?
    /// Qué está haciendo entre medidas («Buscando una fuente…»), para que no parezca trabada.
    @Published private(set) var status: String?

    /// Cuánto mide cada prueba (se descarta el arranque: la conexión tarda en tomar velocidad).
    static let seconds = 10.0, warmUp = 2.0
    /// Una película popular que casi siempre está «Al instante» en Real-Debrid.
    static let testTitle = "tt0111161"
    /// Cuántas fuentes se intentan y lo mínimo que mide un archivo para ser la película (no el video de aviso).
    static let maxTries = 6, minimumBytes: Int64 = 100_000_000
    /// Lo más que se espera a que los complementos digan qué fuentes hay (segundos).
    static let searchLimit = 30.0

    /// `work`, o nil si tarda más de `seconds`.
    static func within<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
    static let internetURL = URL(string: "https://proof.ovh.net/files/1Gb.dat")!
    static let backgroundIdentifier = "com.example.orbital.ios.speedtest"

    func run(services: Services) async {
        guard !running else { return }
        running = true; problem = nil; sourceName = nil; status = nil
        rows = Row.Kind.allCases.map { Row(kind: $0) }
        defer { running = false; status = nil; for i in rows.indices { rows[i].running = false } }

        await measure(.internet) { await Self.parallel(url: Self.internetURL, connections: 1, total: nil) }

        // La primera fuente que dé el archivo de verdad: si Torrentio no consigue el enlace, redirige a un video corto de aviso
        // (unos KB) que termina antes de empezar a medir; esas se saltan.
        let prefs = services.appSettings.preferences(onCellular: false)
        status = "Buscando una fuente de Real-Debrid…"
        let finder = services.finder
        let sources = await Self.within(Self.searchLimit) { (try? await finder.find(kind: "movie", videoID: Self.testTitle, prefs: prefs, purpose: .download)) ?? [] } ?? []
        // Las primeras fuentes se prueban a la vez (una por una, con su espera cada una, parecía trabado); gana la mejor que sirva.
        let tries = Array(sources.prefix(Self.maxTries))
        if !tries.isEmpty { status = "Probando \(tries.count) fuentes…" }
        let resolved = await withTaskGroup(of: (Int, (url: URL, total: Int64)?).self) { group in
            for (i, source) in tries.enumerated() {
                group.addTask { (i, await source.playbackURL.asyncMap { await Self.resolve($0) } ?? nil) }
            }
            var all: [Int: (url: URL, total: Int64)] = [:]
            for await (i, target) in group { if let target, target.total >= Self.minimumBytes { all[i] = target } }
            return all
        }
        status = nil
        let skipped = resolved.keys.min() ?? tries.count
        let picked = resolved.keys.min().flatMap { i in resolved[i].map { (tries[i], $0) } }
        guard let (source, target) = picked else {
            problem = sources.isEmpty ? "No encontré fuentes para probar." : "Ninguna de \(min(sources.count, Self.maxTries)) fuentes dio el archivo (Torrentio o Real-Debrid mandaron un aviso en vez del video)."
            for kind in [Row.Kind.single, .eight, .background] { set(kind) { $0.failed = "Sin enlace" } }
            return
        }
        sourceName = [source.resolution, source.cached ? "Al instante" : "No está al instante",
                      ByteCountFormatter.string(fromByteCount: target.total, countStyle: .file), target.url.host ?? "",
                      skipped > 0 ? "\(skipped) sin archivo antes" : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        await measure(.single) { await Self.parallel(url: target.url, connections: 1, total: target.total) }
        await measure(.eight) { await Self.parallel(url: target.url, connections: 8, total: target.total) }
        await measure(.background) { await BackgroundMeter().run(url: target.url, total: target.total, parts: BackgroundDownloadTransport.parts) }
    }

    /// El texto para copiar y mandar.
    var report: String {
        var lines = ["Prueba de velocidad de Orbital"]
        if let sourceName { lines.append("Fuente: \(sourceName)") }
        for row in rows {
            let value = row.bytesPerSecond.map { Self.format($0) } ?? (row.failed ?? "—")
            lines.append("\(Self.title(row.kind)): \(value)")
        }
        return lines.joined(separator: "\n")
    }

    static func title(_ kind: Row.Kind) -> String {
        switch kind {
        case .internet: "Tu internet (sin Real-Debrid)"
        case .single: "Real-Debrid · 1 conexión"
        case .eight: "Real-Debrid · 8 conexiones"
        case .background: "Real-Debrid · con la app cerrada (segundo plano)"
        }
    }

    /// «12.4 MB/s · 99 Mbps».
    static func format(_ bytesPerSecond: Double) -> String {
        String(format: "%.1f MB/s · %.0f Mbps", bytesPerSecond / 1e6, bytesPerSecond * 8 / 1e6)
    }

    private func set(_ kind: Row.Kind, _ change: (inout Row) -> Void) {
        guard let i = rows.firstIndex(where: { $0.kind == kind }) else { return }
        change(&rows[i])
    }

    private func measure(_ kind: Row.Kind, _ work: () async -> Double?) async {
        set(kind) { $0.running = true }
        let value = await work()
        set(kind) { $0.running = false; $0.bytesPerSecond = value; if value == nil { $0.failed = "No respondió" } }
    }

    /// El enlace final (Torrentio redirige a Real-Debrid) y cuánto mide.
    private static func resolve(_ url: URL) async -> (url: URL, total: Int64)? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        // Solo los encabezados: hay servidores que no hacen caso del «Range» y mandan la película entera; con `data(for:)` se
        // guardaba toda en memoria (seis a la vez) y iOS cerraba la app.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        guard let (bytes, response) = try? await session.bytes(for: request) else { return nil }
        bytes.task.cancel()
        guard let http = response as? HTTPURLResponse, let final = http.url else { return nil }
        if http.statusCode == 206, let total = http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap({ Int64($0) }) { return (final, total) }
        if http.statusCode == 200, http.expectedContentLength > 0 { return (final, http.expectedContentLength) }
        return nil
    }

    /// Bytes por segundo con `connections` conexiones a la vez dentro de la app (cada una pide su tramo del archivo).
    private static func parallel(url: URL, connections: Int, total: Int64?) async -> Double? {
        let meter = Meter()
        let session = URLSession(configuration: .ephemeral, delegate: meter, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        for i in 0..<connections {
            var request = URLRequest(url: url, timeoutInterval: 20)
            if let total {
                let slice = total / Int64(connections)
                request.setValue("bytes=\(Int64(i) * slice)-\(Int64(i + 1) * slice - 1)", forHTTPHeaderField: "Range")
            }
            session.dataTask(with: request).resume()
        }
        return await meter.rate()
    }

    /// Cuenta lo que llega (y lo tira: no se guarda nada).
    final class Meter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var bytes: Int64 = 0
        var received: Int64 { lock.withLock { bytes } }
        func add(_ n: Int64) { lock.withLock { bytes += n } }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { add(Int64(data.count)) }

        /// Lo que llegó entre el final del arranque y el final de la prueba, por segundo; nil si no llegó nada.
        func rate() async -> Double? {
            try? await Task.sleep(nanoseconds: UInt64(DownloadSpeedTest.warmUp * 1e9))
            let start = received, began = Date()
            try? await Task.sleep(nanoseconds: UInt64((DownloadSpeedTest.seconds - DownloadSpeedTest.warmUp) * 1e9))
            let got = received - start
            return got > 0 ? Double(got) / Date().timeIntervalSince(began) : nil
        }
    }

    /// Una sesión de segundo plano propia (no la de las descargas), con los mismos pedazos que usa la app.
    final class BackgroundMeter: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let meter = Meter()

        func run(url: URL, total: Int64, parts: Int) async -> Double? {
            let configuration = URLSessionConfiguration.background(withIdentifier: DownloadSpeedTest.backgroundIdentifier)
            configuration.isDiscretionary = false
            configuration.httpMaximumConnectionsPerHost = parts
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let slice = total / Int64(parts)
            for i in 0..<parts {
                var request = URLRequest(url: url)
                request.setValue("bytes=\(Int64(i) * slice)-\(Int64(i + 1) * slice - 1)", forHTTPHeaderField: "Range")
                let task = session.downloadTask(with: request)
                task.taskDescription = "\(i)"
                task.resume()
            }
            return await meter.rate()
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            meter.add(bytesWritten)
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            try? FileManager.default.removeItem(at: location)
        }
    }
}

private extension Optional {
    func asyncMap<U>(_ transform: (Wrapped) async -> U) async -> U? {
        guard let self else { return nil }
        return await transform(self)
    }
}
