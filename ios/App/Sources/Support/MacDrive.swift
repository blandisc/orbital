#if MAC_DRIVE
import SwiftUI
import os
import OrbitalCore
import OrbitalModels

/// La Mac sin manos, en Release (24 nov 2026): solo en compilaciones de medición (`OTHER_SWIFT_FLAGS=-DMAC_DRIVE`; la app
/// normal no lo trae). Las órdenes llegan al abrir (`open Orbital.app --args -macDrive "tab 1|wait 4|…"`) y hace lo mismo que el
/// clic: `tab <n>` (la tira de pestañas, `MacTabSwitch.go`), `title <kind> <id> [póster] [Nombre_con_guiones]` (un póster: la
/// ficha en el panel, `ui.titlePanels`), `close` (Esc) y `wait <s>`. Antes de cada orden deja una marca en el registro del
/// sistema (categoría «drive») para cruzarla con Instruments (`ios/scripts/medir-mac-sin-manos.sh`). Sin clics por
/// accesibilidad, que suman su propio trabajo (docs/ios-interfaz.md § «Cambiar de pestaña en la Mac»).
@MainActor enum MacDrive {
    private static let log = Logger(subsystem: "mx.iracheta.orbital", category: "drive")
    static func start(tabs: MacTabs, closeTitle: @escaping () -> Void) {
        guard let script = UserDefaults.standard.string(forKey: "macDrive") else { return }
        // Qué dato de la ficha avisó, y cuándo se volvió a pintar (`body`): para saber qué junta un acomodo con otro.
        Tracking.changed = { path in
            if let name = TitleModel.trackedName(path) { log.notice("set \(name, privacy: .public)") }
        }
        // Qué lee cada cuerpo (`-macReads YES`, solo para buscar la causa: escribir cada lectura ensucia la medida).
        if UserDefaults.standard.bool(forKey: "macReads") {
            Tracking.read = { path in
                if let name = TitleModel.trackedName(path) { log.notice("read \(name, privacy: .public)") }
            }
        }
        Task { @MainActor in
            for (i, line) in script.split(separator: "|").enumerated() {
                let w = line.split(separator: " ").map(String.init)
                guard let command = w.first else { continue }
                if command == "wait" { try? await Task.sleep(for: .seconds(Double(w.dropFirst().first ?? "3") ?? 3)); continue }
                if command == "go" { await waitForGo(); continue }
                let name = "\(i)-\(command)-\(w.dropFirst().first ?? "")-\(w.count > 2 ? w[2] : "")"
                log.notice("mark \(name, privacy: .public)")
                switch command {
                case "tab": if let id = w.dropFirst().first.flatMap(Int.init) { MacTabSwitch.go(tabs, id) }
                case "title" where w.count >= 3:
                    let route = TitleRoute(kind: w[1], metaID: w[2], title: w.count > 4 ? w[4].replacingOccurrences(of: "_", with: " ") : "",
                                           poster: w.count > 3 ? w[3] : nil)
                    AppEnvironment.shared.ui.titlePanels.values.first?(route, nil)
                case "close": closeTitle()
                case "snap": snap(w.count > 1 ? w[1] : "\(i)")
                case "scroll": await scroll(by: w.count > 1 ? Double(w[1]) ?? 3000 : 3000, seconds: w.count > 2 ? Double(w[2]) ?? 3 : 3)
                default: break
                }
            }
            log.notice("mark listo")
        }
    }

    /// `-macStillGlass`: el vidrio de arriba sin respuesta al puntero (para aislar su costo al cambiar de pestaña).
    static let stillGlass = UserDefaults.standard.bool(forKey: "macStillGlass")
    /// `-macNoGlass`: sin vidrio arriba; `-macGlassInstant`: el vidrio sin su entrada animada al volver a una pestaña.
    static let noGlass = UserDefaults.standard.bool(forKey: "macNoGlass")
    static let glassInstant = UserDefaults.standard.bool(forKey: "macGlassInstant")
    static let frostGlass = UserDefaults.standard.bool(forKey: "macFrostGlass")
    static let solidGlass = UserDefaults.standard.bool(forKey: "macSolidGlass")
    /// Experimentos de deslizar (26 nov 2026): `-macNoEntrance` sin la entrada de las filas, `-macEager` las columnas de Inicio
    /// y Explorar armadas de una vez, `-macLitePoster` el póster sin el marco del puntero, su realce ni el origen del zoom.
    static let noEntrance = UserDefaults.standard.bool(forKey: "macNoEntrance")
    static let eager = UserDefaults.standard.bool(forKey: "macEager")
    /// `-macLazy`: Inicio perezoso también en la Mac (como antes), para comparar.
    static let lazy = UserDefaults.standard.bool(forKey: "macLazy")
    static let litePoster = UserDefaults.standard.bool(forKey: "macLitePoster")


    /// `go`: espera a que el script avise que Instruments ya graba (`notifyutil -p mx.iracheta.orbital.go`; dos minutos como
    /// mucho). Con la Mac ocupada Instruments tardaba más que la espera fija y se perdía la ronda (25 nov 2026).
    nonisolated(unsafe) private static var went = false
    private static func waitForGo() async {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in MacDrive.went = true },
                                        "mx.iracheta.orbital.go" as CFString, nil, .deliverImmediately)
        for _ in 0..<600 where !went { try? await Task.sleep(for: .milliseconds(200)) }
        log.notice("go \(went ? "Instruments graba" : "sin aviso", privacy: .public)")
    }

    /// `scroll <puntos> <segundos>`: desliza la lista que se ve (la más grande de la ventana) a paso parejo, como la rueda del
    /// mouse sostenida; negativo sube. Para medir los tirones al deslizar sin permiso de accesibilidad (25 nov 2026).
    static func scroll(by distance: Double, seconds: Double) async {
        guard let window = AppWindows.keyWindow,
              let view = biggestScroll(in: window) else { log.notice("scroll sin lista"); return }
        let start = view.contentOffset.y
        let top = -view.adjustedContentInset.top, bottom = max(top, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
        log.notice("scroll \(Int(view.frame.width))x\(Int(view.frame.height)) de \(Int(view.contentSize.height)) desde \(Int(start))")
        // Cuadro por cuadro (CADisplayLink), como la rueda: cada cuadro mueve la lista a donde va según el reloj, y se anota cuánto
        // se atrasó cada uno. «tirones» = ms atrasados por segundo de deslizar (Apple: < 5 se siente fluido, > 10 se nota).
        let r = await ScrollDriver.run(seconds: seconds) { p in view.contentOffset.y = min(bottom, max(top, start + distance * p)) }
        log.notice("frames \(r.frames, privacy: .public) tirones \(Int(r.hitchPerSecond), privacy: .public) peor \(Int(r.worst), privacy: .public) pesados \(r.heavy, privacy: .public) hz \(r.hz, privacy: .public)")
    }

    /// La lista de enfrente: de las que se ven y ocupan buena parte de la ventana, la que está más arriba (la ficha, si está
    /// abierta; si no, la pestaña que ves).
    private static func biggestScroll(in root: UIView) -> UIScrollView? {
        func visible(_ v: UIView) -> Bool {
            var view: UIView? = v
            while let u = view { if u.isHidden || u.alpha < 0.01 || u.layer.opacity < 0.01 { return false }; view = u.superview }
            return true
        }
        let enough = root.bounds.width * root.bounds.height * 0.15
        var front: UIScrollView?
        func walk(_ v: UIView) {
            if let s = v as? UIScrollView, s.contentSize.height > s.bounds.height + 1, s.bounds.width * s.bounds.height >= enough, visible(s) { front = s }
            for sub in v.subviews { walk(sub) }
        }
        walk(root)
        return front
    }

    /// Mueve algo cada cuadro durante `seconds` y cuenta los cuadros atrasados.
    @MainActor private final class ScrollDriver: NSObject {
        struct Result { var frames = 0, heavy = 0, hz = 0; var worst = 0.0, hitchPerSecond = 0.0 }
        private var link: CADisplayLink?, first: CFTimeInterval = 0, last: CFTimeInterval = 0, lost: CFTimeInterval = 0
        private var result = Result(), seconds = 0.0, step: @MainActor (Double) -> Void = { _ in }, done: CheckedContinuation<Result, Never>?
        static func run(seconds: Double, step: @escaping @MainActor (Double) -> Void) async -> Result {
            let d = ScrollDriver(); d.seconds = seconds; d.step = step
            return await withCheckedContinuation { c in
                d.done = c
                let link = CADisplayLink(target: d, selector: #selector(tick(_:)))
                link.add(to: .main, forMode: .common); d.link = link
            }
        }
        @objc private func tick(_ link: CADisplayLink) {
            let frame = max(link.targetTimestamp - link.timestamp, 1.0 / 120)
            if first == 0 { first = link.timestamp; result.hz = Int((1 / frame).rounded()) }
            if last > 0 {
                let gap = link.timestamp - last
                result.worst = max(result.worst, gap * 1000)
                if gap > frame * 1.5 { lost += gap - frame; result.heavy += 1 }
            }
            last = link.timestamp; result.frames += 1
            let p = min(1, (link.timestamp - first) / seconds)
            step(p)
            guard p >= 1 else { return }
            link.invalidate(); self.link = nil
            result.hitchPerSecond = lost * 1000 / max(0.001, last - first)
            done?.resume(returning: result); done = nil
        }
    }

    /// `snap <nombre>`: la ventana a un PNG en la carpeta temporal de la app (para comparar cómo se ve antes y después sin
    /// permiso de grabar la pantalla; el vidrio sale sin su refracción).
    static func snap(_ name: String) {
        guard let window = AppWindows.keyWindow else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macsnap-\(name).png")
        try? image.pngData()?.write(to: url)
        log.notice("snap \(url.path, privacy: .public)")
    }

    static func body(_ name: StaticString) { log.notice("body \(name, privacy: .public)") }
    static func state(_ name: StaticString) { log.notice("state \(name, privacy: .public)") }
}
#endif
