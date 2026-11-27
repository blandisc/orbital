import SwiftUI
import Darwin
import OrbitalCore

/// Cuánto tarda en verse cada cosa (con `-perf`): cada marca se anota una sola vez, en milisegundos desde que arrancó el
/// proceso (o desde `begin`), como «ORBITAL-PERF home.hero.image 812». Sin `-perf` no hace nada.
enum Perf {
    /// Solo en Debug (se mide con la demostración, que tampoco existe en Release): en la app de la tienda no lee argumentos
    /// ni escribe bitácoras, y el compilador quita las marcas (auditoría, 31 oct 2026, C2).
    #if DEBUG
    static let isOn = Demo.has("-perf")
    #else
    static let isOn = false
    #endif
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

    /// El inicio de una vuelta de medición («ORBITAL-CYCLE xtab 3 51234»): las peticiones que empiezan después son de esa vuelta.
    @MainActor static func cycle(_ scope: String, _ n: Int) {
        guard isOn else { return }
        let line = "ORBITAL-CYCLE \(scope) \(n) \(now())\n"
        if let handle = try? FileHandle(forWritingTo: log) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() }
        else { try? Data(line.utf8).write(to: log) }
    }

    /// Una línea suelta en la bitácora de medidas (el tirón más largo de una vuelta).
    @MainActor static func record(_ name: String, _ ms: Int) {
        guard isOn else { return }
        let line = "ORBITAL-PERF \(name) \(ms)\n"
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

/// V9 · cuántas veces se evalúa el `body` de cada pantalla (con `-perf-bodies`, solo Debug): `ios/scripts/medir-repintado.sh`
/// abre Inicio, una ficha y el reproductor con la demostración y lee el resumen («home 14», una línea por pantalla) de
/// `tmp/orbital-bodies.txt` en el contenedor de la app. Sin la bandera no hace nada (y en Release no existe).
enum BodyCount {
    #if DEBUG
    static let isOn = Demo.has("-perf-bodies")
    /// `-perf-why`: además, cada pantalla medida dice en la consola qué la hizo volver a pintarse (`_printChanges`).
    static let explains = Demo.has("-perf-why")
    #else
    static let isOn = false, explains = false
    #endif
    static let file = FileManager.default.temporaryDirectory.appendingPathComponent("orbital-bodies.txt")
    @MainActor private static var counts: [String: Int] = [:]
    @MainActor private static var writing = false

    /// Una evaluación más del `body` de `name`. El resumen se escribe medio segundo después (juntando las de esa ráfaga).
    @MainActor static func tick(_ name: String, why: () -> Void = {}) {
        guard isOn else { return }
        if explains { why() }
        if counts.isEmpty { try? FileManager.default.removeItem(at: file) }
        counts[name, default: 0] += 1
        guard !writing else { return }
        writing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            writing = false
            let text = counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "\n") + "\n"
            try? Data(text.utf8).write(to: file, options: .atomic)
        }
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


/// El cuadro que más tardó (ms) durante un rato (con `-perf`): lo que se siente como un tirón al cambiar de pestaña. A 60 Hz
/// un cuadro dura ~17 ms; uno de 100 ms ya se nota.
@MainActor final class HitchMeter: NSObject {
    private static var current: HitchMeter?
    private let scope: String, until: CFTimeInterval
    private var link: CADisplayLink?, last: CFTimeInterval = 0, worst: CFTimeInterval = 0, lost: CFTimeInterval = 0

    private init(scope: String, seconds: Double) {
        self.scope = scope; until = CACurrentMediaTime() + seconds
        super.init()
    }

    static func measure(_ scope: String, seconds: Double) {
        guard Perf.isOn else { return }
        let meter = HitchMeter(scope: scope, seconds: seconds)
        current = meter
        let link = CADisplayLink(target: meter, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        meter.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 {
            let gap = link.timestamp - last
            worst = max(worst, gap)
            lost += max(0, gap - link.duration * 1.5)   // lo que se atrasó más allá de un cuadro y medio
        }
        last = link.timestamp
        guard link.timestamp >= until else { return }
        link.invalidate()
        Perf.record(scope + ".hitch", Int(worst * 1000))
        Perf.record(scope + ".lost", Int(lost * 1000))
        if HitchMeter.current === self { HitchMeter.current = nil }
    }
}

#if DEBUG
/// Medidas y recorrido de la Mac sin manos (Fernando, 17 nov 2026: «tráeme 5 métricas de performance» y «que funcione bien en
/// distintas resoluciones, tengo un monitor ultrawide»). La app abierta desde Xcode lo hace sola si al arrancar encuentra el
/// archivo `tmp/mac-check-request` en su contenedor (Xcode no siempre logra arrancar `OrbitalMacTests` en la Mac). El archivo
/// dice qué hacer, una palabra por renglón: `perf <etiqueta>` (las cinco medidas, en `tmp/mac-perf-<etiqueta>.txt`) y
/// `tour` (una captura de cada pantalla en cinco tamaños de ventana, en `tmp/mac-tour/`). Ver `docs/ios-interfaz.md`
/// § «Rendimiento de la Mac».
@MainActor enum MacSelfCheck {
    private static var tmp: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
    nonisolated static var simulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    private static var env: AppEnvironment { AppEnvironment.shared }
    private static var window: UIWindow? { AppWindows.all.first(where: \.isKeyWindow) ?? AppWindows.all.first }

    /// `off sky`, `off breath`, `off drift`… en el archivo de petición: apaga esa animación desde el arranque (para encontrar
    /// qué gasta). Se lee una vez, al arrancar.
    nonisolated static let off: Set<String> = {
        let request = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mac-check-request")
        guard ProcessInfo.onMac || simulator, let text = try? String(contentsOf: request, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").compactMap { line in line.hasPrefix("off ") ? String(line.dropFirst(4)) : nil })
    }()

    static func runIfRequested() async {
        _ = off
        // La Mac, o el simulador (el iPad: la misma revisión sin manos, en su tamaño).
        guard ProcessInfo.onMac || Self.simulator else { return }
        let request = tmp.appendingPathComponent("mac-check-request")
        guard let text = try? String(contentsOf: request, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: request)
        try? await Task.sleep(for: .seconds(10))   // que Inicio termine de cargar
        for line in text.split(separator: "\n") {
            let words = line.split(separator: " ").map(String.init)
            switch words.first {
            case "perf": await perf(label: words.dropFirst().first ?? "medida")
            case "tour": await tour()
            case "fichas": await fichas()   // la ficha ancha en seis tamaños (la receta `WideStage`)
            // `size full` o `size 1440 900`: deja la ventana de ese tamaño (para medir desde fuera con `sample`).
            case "size": resize(words.count > 2 ? CGSize(width: Double(words[1]) ?? 1440, height: Double(words[2]) ?? 900) : screenSize)
            case "free": free()
            case "scroll":   // desplaza Inicio abajo y arriba (6 s) y anota los cuadros perdidos
                if let scroll = mainScroll() {
                    let top = -scroll.adjustedContentInset.top
                    let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    let meter = FrameMeter()
                    meter.start { progress in
                        let f = progress < 0.5 ? progress * 2 : (1 - progress) * 2
                        scroll.contentOffset.y = top + (bottom - top) * f
                    }
                    await wait(6.3)
                    let result = meter.stop()
                    let line = "scroll lost \(Int(result.lostPerSecond)) worst \(Int(result.worst))\n"
                    let out = tmp.appendingPathComponent("mac-cpu.txt")
                    if let h = try? FileHandle(forWritingTo: out) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() } else { try? Data(line.utf8).write(to: out) }
                }
            case "mark": try? Data().write(to: tmp.appendingPathComponent("mac-mark-\(words.dropFirst().first ?? "x")"))
            // `cpu <etiqueta>`: el CPU en reposo de 10 s, sin moverse de donde está. `ficha`: abre una serie y regresa.
            case "cpu": await idleCPU(label: words.dropFirst().first ?? "cpu")
            case "ficha":
                env.pendingTitle = TitleRoute(kind: "series", metaID: "tt0386676", title: "", poster: nil)
                await wait(5)
                env.ui.goBack = true
                await wait(3)
            case "wait": await wait(Double(words.dropFirst().first ?? "5") ?? 5)
            case "load": await load(label: words.dropFirst().first ?? "carga")
            case "ajustes": env.ui.openSettings = true
            case "pelicula": env.pendingTitle = TitleRoute(kind: "movie", metaID: "tt1160419", title: "", poster: nil)
            case "back": env.ui.goBack = true
            case "tab": env.ui.openTab = Int(words.dropFirst().first ?? "0") ?? 0   // `tab 3`: abre esa pestaña (para medir desde fuera)
            default: break
            }
        }
        try? Data("listo\n".utf8).write(to: tmp.appendingPathComponent("mac-check-done"))
    }

    private static func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    /// La ventana fija a ese tamaño (en la Mac, mínimo = máximo); `free` la deja libre otra vez.
    static func resize(_ size: CGSize) {
        guard ProcessInfo.onMac, let limits = AppWindows.scene?.sizeRestrictions else { return }
        limits.minimumSize = CGSize(width: min(size.width, WindowMetrics.minimum.width), height: min(size.height, WindowMetrics.minimum.height))
        limits.maximumSize = size
        limits.minimumSize = size
    }

    static func free() {
        guard ProcessInfo.onMac, let limits = AppWindows.scene?.sizeRestrictions else { return }
        limits.minimumSize = WindowMetrics.minimum
        limits.maximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    }

    /// Lo más grande que cabe en la pantalla (en el ultrawide de Fernando, 3440 × 1440 a 77 %).
    static var screenSize: CGSize {
        let bounds = window?.screen.bounds.size ?? CGSize(width: 4400, height: 1800)
        return CGSize(width: bounds.width, height: bounds.height - 80)
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// El ScrollView vertical más grande de la ventana (el de la pestaña a la vista).
    private static func mainScroll() -> UIScrollView? {
        var best: UIScrollView?
        func walk(_ view: UIView) {
            if let scroll = view as? UIScrollView, !scroll.isHidden, scroll.window != nil, scroll.alpha > 0,
               scroll.contentSize.height > scroll.bounds.height * 1.3,
               scroll.bounds.width * scroll.bounds.height > (best.map { $0.bounds.width * $0.bounds.height } ?? 0) { best = scroll }
            view.subviews.forEach(walk)
        }
        if let window { walk(window) }
        return best
    }

    private static func idleCPU(label: String) async {
        let cpu0 = cpuSeconds(), t0 = CACurrentMediaTime()
        await wait(10)
        let line = "\(label) idle-cpu \(String(format: "%.1f", (cpuSeconds() - cpu0) / (CACurrentMediaTime() - t0) * 100))\n"
        print("MAC-PERF " + line)
        let out = tmp.appendingPathComponent("mac-cpu.txt")
        if let handle = try? FileHandle(forWritingTo: out) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() }
        else { try? Data(line.utf8).write(to: out) }
    }

    /// Las cinco medidas, en una ventana grande y en una del tamaño de la pantalla:
    ///   1. `idle-cpu`: CPU en reposo en Inicio, sin tocar nada, 10 s (% de un núcleo).
    ///   2. `scroll-lost`: al desplazar Inicio abajo y arriba (6 s), ms de cuadros perdidos por segundo (y `scroll-worst`).
    ///   3. `title-worst`: el cuadro más largo (ms) al abrir la ficha de una serie.
    ///   4. `resize-worst`: el cuadro más largo (ms) al cambiar la ventana de tamaño.
    ///   5. `memory`: la memoria de la app al final (MB, `phys_footprint`).
    static func perf(label: String) async {
        var lines: [String] = []
        let out = tmp.appendingPathComponent("mac-perf-\(label).txt")
        func record(_ size: String, _ name: String, _ value: Double) {
            let line = "\(size) \(name) \(String(format: "%.1f", value))"
            print("MAC-PERF " + line); lines.append(line)
            try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: out)
        }
        env.ui.openTab = 0
        await wait(2)
        for (name, size) in [("grande", CGSize(width: 1440, height: 900)), ("ultrawide", screenSize)] {
            let meter = FrameMeter(); meter.start()
            resize(size)
            await wait(3)
            record(name, "resize-worst", meter.stop().worst)
            await wait(3)

            let cpu0 = cpuSeconds(), t0 = CACurrentMediaTime()
            await wait(10)
            record(name, "idle-cpu", (cpuSeconds() - cpu0) / (CACurrentMediaTime() - t0) * 100)

            if let scroll = mainScroll() {
                let top = -scroll.adjustedContentInset.top
                let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                let scrollMeter = FrameMeter()
                scrollMeter.start { progress in
                    let f = progress < 0.5 ? progress * 2 : (1 - progress) * 2
                    scroll.contentOffset.y = top + (bottom - top) * f
                }
                await wait(6.3)
                let result = scrollMeter.stop()
                record(name, "scroll-lost", result.lostPerSecond)
                record(name, "scroll-worst", result.worst)
                scroll.contentOffset.y = top
            } else {
                record(name, "scroll-lost", -1)
            }
            await wait(2)

            let titleMeter = FrameMeter(); titleMeter.start()
            env.pendingTitle = TitleRoute(kind: "series", metaID: "tt0386676", title: "", poster: nil)
            await wait(4)
            record(name, "title-worst", titleMeter.stop().worst)
            env.ui.goBack = true
            await wait(2.5)
        }
        let back = FrameMeter(); back.start()
        resize(CGSize(width: 1440, height: 900))
        await wait(3)
        record("regreso", "resize-worst", back.stop().worst)
        record("final", "memory", memoryMB())
        free()
    }

    /// La carga de cada pantalla (la primera vez que se abre, como al arrancar): `hitch`, el cuadro más largo al entrar (ms:
    /// lo que se siente trabado); `settled`, cuándo dejó de cambiar (la última imagen que llegó o el último cuadro atrasado, ms).
    /// Córrelo justo al arrancar, antes de `tour`, o las pantallas ya estarán en caché.
    static func load(label: String) async {
        var lines: [String] = []
        let out = tmp.appendingPathComponent("mac-load-\(label).txt")
        func measure(_ name: String, _ open: () -> Void, back: Bool) async {
            await quiet()   // que no se cuele lo que dejó pendiente la pantalla anterior
            let ping = MainPing(); ping.start()
            ImageWait.reset()
            let t0 = CACurrentMediaTime()
            open()
            await wait(1.5)
            let hitch = ping.worst
            await wait(6.5)
            ping.stop()
            let busy = ping.lastBlock > 0 ? ping.lastBlock - t0 : 0
            let settled = max(ImageWait.lastArrival > 0 ? ImageWait.lastArrival - t0 : 0, busy, 0)
            let line = "\(name) hitch \(Int(hitch)) blocked \(Int(ping.total)) settled \(Int(settled * 1000)) images \(ImageWait.arrived)"
            print("MAC-LOAD " + line); lines.append(line)
            try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: out)
            if back { env.ui.goBack = true; await wait(2) }
            if back == false { env.ui.openTab = 0; await wait(2) }   // cada pestaña se abre desde Inicio
        }
        // Sin App Nap: con la ventana tapada macOS la duerme y el hilo de la pantalla atiende tarde (medía trabas de 1–2 s falsas).
        let awake = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "medir la carga")
        defer { ProcessInfo.processInfo.endActivity(awake) }
        resize(CGSize(width: 1440, height: 900))
        await wait(2)
        await measure("explorar", { env.ui.openTab = 1 }, back: false)
        await measure("buscar", { env.ui.openTab = 2 }, back: false)
        await measure("biblioteca", { env.ui.openTab = 3 }, back: false)
        await measure("ficha-pelicula", { env.pendingTitle = TitleRoute(kind: "movie", metaID: "tt1160419", title: "", poster: nil) }, back: true)
        await measure("ficha-serie", { env.pendingTitle = TitleRoute(kind: "series", metaID: "tt0386676", title: "", poster: nil) }, back: true)
        await measure("ajustes", { env.ui.openSettings = true }, back: true)
        free()
    }

    /// Espera a que la pantalla esté quieta: 1.5 s seguidos sin un cuadro atrasado (a lo más 10 s).
    private static func quiet() async {
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < 10 {
            let ping = MainPing(); ping.start()
            await wait(1.5)
            ping.stop()
            if ping.worst < 40 { return }
        }
    }

    /// Una captura de cada pantalla en cinco tamaños, de la ventana chica al ultrawide completo.
    /// La ficha (película y serie) en seis tamaños, de angosta y alta a ultrawide: fotos en `mac-fichas/`.
    static func fichas() async {
        let folder = tmp.appendingPathComponent("mac-fichas")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let full = screenSize, before = window?.bounds.size ?? full
        let sizes: [CGSize] = !ProcessInfo.onMac ? [window?.bounds.size ?? full] : [
            CGSize(width: 760, height: 1000), CGSize(width: 1100, height: 760), CGSize(width: 1440, height: 900),
            CGSize(width: 1920, height: 1080), CGSize(width: full.width * 0.75, height: full.height), full,
        ]
        for size in sizes {
            resize(size)
            await wait(2)
            for (kind, id) in [("movie", "tt1160419"), ("series", "tt0386676")] {
                env.pendingTitle = TitleRoute(kind: kind, metaID: id, title: "", poster: nil)
                await wait(6)
                if let window {
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                    try? image.pngData()?.write(to: folder.appendingPathComponent("\(Int(window.bounds.width))x\(Int(window.bounds.height))-\(kind).png"))
                }
                env.ui.goBack = true
                await wait(2.5)
            }
        }
        resize(before)
        await wait(1)
        free()
    }

    static func tour() async {
        let folder = tmp.appendingPathComponent("mac-tour")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func shot(_ name: String) {
            guard let window else { return }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            try? image.pngData()?.write(to: folder.appendingPathComponent("\(name).png"))
            print("MAC-TOUR shot \(name) \(Int(window.bounds.width))x\(Int(window.bounds.height))")
        }
        let full = screenSize
        // En el iPad, su tamaño de siempre (la ventana no se cambia desde aquí).
        let sizes: [(String, CGSize)] = !ProcessInfo.onMac ? [("ipad", window?.bounds.size ?? full)] : [
            ("1-chica", CGSize(width: 560, height: 720)),
            ("2-mediana", CGSize(width: 960, height: 680)),
            ("3-grande", CGSize(width: 1440, height: 900)),
            ("4-ultrawide-media", CGSize(width: full.width / 2 + 200, height: full.height)),
            ("5-ultrawide", full),
        ]
        for (label, size) in sizes {
            resize(size)
            await wait(2)
            for (index, name) in [(0, "inicio"), (1, "explorar"), (2, "buscar"), (3, "biblioteca")] {
                env.ui.openTab = index
                await wait(3)
                shot("\(label)-\(name)")
                // Inicio y Explorar también más abajo: dos pantallas más.
                if index < 2, let scroll = mainScroll() {
                    let top = -scroll.adjustedContentInset.top
                    for page in 1...2 {
                        scroll.contentOffset.y = min(top + scroll.bounds.height * 0.85 * CGFloat(page), scroll.contentSize.height - scroll.bounds.height)
                        await wait(2)
                        shot("\(label)-\(name)-\(page + 1)")
                    }
                    scroll.contentOffset.y = top
                    await wait(1)
                }
            }
            env.ui.openTab = 0
            await wait(1.5)
            env.pendingTitle = TitleRoute(kind: "movie", metaID: "tt1160419", title: "", poster: nil)
            await wait(5)
            shot("\(label)-ficha-pelicula")
            env.ui.goBack = true
            await wait(2)
            env.pendingTitle = TitleRoute(kind: "series", metaID: "tt0386676", title: "", poster: nil)
            await wait(5)
            shot("\(label)-ficha-serie")
            env.ui.goBack = true
            await wait(2)
            env.ui.openSettings = true
            await wait(3)
            shot("\(label)-ajustes")
            env.ui.goBack = true
            await wait(2)
        }
        free()
    }
}

/// Cuánto se traba el hilo de la pantalla, aunque la ventana esté tapada (ahí la Mac no dibuja y no hay cuadros que contar):
/// desde otro hilo le pide algo cada 8 ms y mide cuánto tarda en atenderlo. `worst`: la traba más larga (ms); `total`: lo que
/// sumaron las trabas de más de 50 ms; `lastBlock`: cuándo fue la última de más de 50 ms.
final class MainPing: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var _worst = 0.0, _total = 0.0, _last: CFTimeInterval = 0
    var worst: Double { lock.withLock { _worst } }
    var total: Double { lock.withLock { _total } }
    var lastBlock: CFTimeInterval { lock.withLock { _last } }

    func start() {
        Thread.detachNewThread { [self] in
            while lock.withLock({ running }) {
                let t = CACurrentMediaTime()
                DispatchQueue.main.sync {}
                let ms = (CACurrentMediaTime() - t) * 1000
                lock.withLock {
                    _worst = max(_worst, ms)
                    if ms > 50 { _total += ms; _last = CACurrentMediaTime() }
                }
                Thread.sleep(forTimeInterval: 0.008)
            }
        }
    }

    func stop() { lock.withLock { running = false } }
}

/// Cuántas imágenes de la red faltan y cuándo llegó la última (para `MacSelfCheck.load`).
@MainActor enum ImageWait {
    static var pending = 0, arrived = 0
    static var lastArrival: CFTimeInterval = 0
    static func reset() { arrived = 0; lastArrival = 0 }
    static func begin() { pending += 1 }
    static func end(_ got: Bool) { pending = max(0, pending - 1); if got { arrived += 1; lastArrival = CACurrentMediaTime() } }
}

/// Cuenta los cuadros de la pantalla: el más largo y cuánto se atrasaron (más de cuadro y medio). `step` mueve algo en cada
/// cuadro (de 0 a 1 en 6 s), como un dedo que desplaza.
@MainActor final class FrameMeter: NSObject {
    struct Result { let worst: Double; let lostPerSecond: Double; var frames = 0 }
    /// Cuándo fue el último cuadro atrasado (`CACurrentMediaTime`), o 0.
    private(set) var lastLongFrame: CFTimeInterval = 0
    private var link: CADisplayLink?, first: CFTimeInterval = 0, last: CFTimeInterval = 0
    private var worst: CFTimeInterval = 0, lost: CFTimeInterval = 0, frames = 0
    private var step: ((Double) -> Void)?

    func start(step: ((Double) -> Void)? = nil) {
        self.step = step
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        if first == 0 { first = link.timestamp }
        if last > 0 {
            let gap = link.timestamp - last
            worst = max(worst, gap)
            lost += max(0, gap - link.duration * 1.5)
            if gap > link.duration * 2.5 { lastLongFrame = CACurrentMediaTime() }
        }
        last = link.timestamp
        frames += 1
        step?(min(1, (link.timestamp - first) / 6))
    }

    func stop() -> Result {
        link?.invalidate(); link = nil
        let span = max(0.001, last - first)
        return Result(worst: worst * 1000, lostPerSecond: lost * 1000 / span, frames: frames)
    }
}
#endif
