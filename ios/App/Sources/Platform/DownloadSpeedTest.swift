import Foundation
import OrbitalCore
import OrbitalModels

/// Ajustes › Descargas › «Probar la velocidad»: de dónde viene la lentitud. Mide, unos segundos cada una y sin guardar nada:
/// tu internet sin Real-Debrid (un archivo de prueba de OVH, en Francia como los servidores de Real-Debrid), Real-Debrid con una conexión, con ocho, y como baja hoy la app (la sesión de
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

    /// Cuánto mide cada prueba (se descarta el arranque: la conexión tarda en tomar velocidad).
    static let seconds = 10.0, warmUp = 2.0
    /// Una película popular que casi siempre está «Al instante» en Real-Debrid.
    static let testTitle = "tt0111161"
    static let internetURL = URL(string: "https://proof.ovh.net/files/1Gb.dat")!
    static let backgroundIdentifier = "com.example.orbital.ios.speedtest"

    func run(services: Services) async {
        guard !running else { return }
        running = true; problem = nil; sourceName = nil
        rows = Row.Kind.allCases.map { Row(kind: $0) }
        defer { running = false; for i in rows.indices { rows[i].running = false } }

        await measure(.internet) { await Self.parallel(url: Self.internetURL, connections: 1, total: nil) }

        let prefs = services.appSettings.preferences(onCellular: false)
        guard let source = try? await services.finder.best(kind: "movie", videoID: Self.testTitle, prefs: prefs, purpose: .download),
              let link = source.playbackURL, let target = await Self.resolve(link) else {
            problem = "No pude conseguir un enlace de Real-Debrid para probar."
            for kind in [Row.Kind.single, .eight, .background] { set(kind) { $0.failed = "Sin enlace" } }
            return
        }
        sourceName = [source.resolution, source.cached ? "Al instante" : "No está al instante",
                      ByteCountFormatter.string(fromByteCount: target.total, countStyle: .file)].joined(separator: " · ")
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
        case .background: "Real-Debrid · como baja hoy (segundo plano, 4 partes)"
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
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        guard let (_, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 206, let final = http.url,
              let total = http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap({ Int64($0) }) else { return nil }
        return (final, total)
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
