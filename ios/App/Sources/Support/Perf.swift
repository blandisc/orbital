import SwiftUI
import Darwin
import OrbitalCore

/// Cuánto tarda en verse cada cosa (con `-perf`): cada marca se anota una sola vez, en milisegundos desde que arrancó el
/// proceso (o desde `begin`), como «ORBITAL-PERF home.hero.image 812». Sin `-perf` no hace nada.
enum Perf {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-perf")
    @MainActor private static var done = Set<String>()
    @MainActor private static var origins: [String: Double] = [:]

    /// El arranque del proceso (no el de la primera vista): así cuenta también lo que tarda en abrir la app.
    private static let processStart: Double = {
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date().timeIntervalSince1970 }
        let t = info.kp_proc.p_un.__p_starttime
        return Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000
    }()

    /// Empieza a contar desde ahora las marcas que empiezan con `scope` («search»).
    static let log = FileManager.default.temporaryDirectory.appendingPathComponent("orbital-perf.log")

    @MainActor static func begin(_ scope: String) {
        guard isOn else { return }
        origins[scope] = Date().timeIntervalSince1970
        done = done.filter { !$0.hasPrefix(scope + ".") }
    }

    @MainActor static func mark(_ name: String) {
        guard isOn, done.insert(name).inserted else { return }
        let scope = String(name.split(separator: ".").first ?? "")
        let origin = origins[scope] ?? processStart
        let line = "ORBITAL-PERF \(name) \(Int((Date().timeIntervalSince1970 - origin) * 1000))" + "\n"
        // A un archivo de la app (el medidor lo lee del contenedor del simulador al terminar).
        if let handle = try? FileHandle(forWritingTo: log) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() }
        else { try? Data(line.utf8).write(to: log) }
    }

    /// Las peticiones, en un archivo aparte: «ORBITAL-NET api 812 940 5321 200 GET https://…/ruta?token=…».
    static let netLog = FileManager.default.temporaryDirectory.appendingPathComponent("orbital-net.log")
    private static let netLock = NSLock()

    /// Milisegundos desde el arranque del proceso (la misma escala que las marcas sin `begin`).
    static func now() -> Int { Int((Date().timeIntervalSince1970 - processStart) * 1000) }

    /// Una petición terminada. `kind`: `api`, `img` (de la red) o `imgcache` (del caché de disco). Se puede llamar desde
    /// cualquier tarea. De la URL quedan la ruta y los nombres de los parámetros, nunca sus valores (tokens, claves).
    static func net(kind: String, url: URL, method: String = "GET", start: Int, end: Int, bytes: Int, status: Int) {
        guard isOn else { return }
        let line = "ORBITAL-NET \(kind) \(start) \(end) \(bytes) \(status) \(method) \(redacted(url))\n"
        netLock.withLock {
            if let handle = try? FileHandle(forWritingTo: netLog) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() }
            else { try? Data(line.utf8).write(to: netLog) }
        }
    }

    private static func redacted(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.host ?? "?" }
        parts.user = nil; parts.password = nil; parts.fragment = nil
        parts.queryItems = parts.queryItems?.map { URLQueryItem(name: $0.name, value: $0.value == nil ? nil : "…") }
        return parts.string ?? url.host ?? "?"
    }
}

/// Envuelve un `HTTPClient` y anota cada petición (`kind` api) con `-perf`.
struct PerfHTTPClient: HTTPClient {
    let inner: any HTTPClient
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let start = Perf.now()
        do {
            let response = try await inner.send(request)
            Perf.net(kind: "api", url: request.url, method: request.method, start: start, end: Perf.now(), bytes: response.data.count, status: response.status)
            return response
        } catch {
            Perf.net(kind: "api", url: request.url, method: request.method, start: start, end: Perf.now(), bytes: 0, status: -1)
            throw error
        }
    }
}

/// La marca que deja la primera imagen que termina de cargar dentro de esta vista («home.hero» → «home.hero.image»).
private struct PerfTagKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var perfTag: String? { get { self[PerfTagKey.self] } set { self[PerfTagKey.self] = newValue } }
}
extension View {
    /// Marca cuándo aparecen los datos (al pintarse) y la primera imagen de esta vista.
    func perfTag(_ tag: String) -> some View {
        environment(\.perfTag, Perf.isOn ? tag : nil).onAppear { Perf.mark(tag + ".shown") }
    }
}
