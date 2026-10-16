#if DEBUG
import SwiftUI
import QuartzCore
import Darwin
import MachO

/// Banco de pruebas del mosaico (CEN-49, solo Debug): con `-demo -demo-tab 1 -demo-mosaic-bench` el mosaico se
/// desplaza solo (como un arrastre real: llama a `scrollBy` en cada fotograma) y luego cambia de foco cada medio
/// segundo, y al final imprime «MOSAIC-BENCH …» con los fotogramas (media, p95, peor, saltos) y cuántas veces se
/// evaluó el `body` del mosaico y de sus piezas. Mide el hilo principal, que es donde se «traba» la interfaz.
@MainActor
enum MosaicBench {
    static var counts: [String: Int] = [:]

    /// Se llama desde los `body`: cuenta evaluaciones por nombre.
    static func tick(_ name: String) -> Bool { counts[name, default: 0] += 1; return true }

    /// Memoria que el sistema le cuenta a la app (la que mira jetsam), en MB.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Un hilo que avisa si el principal lleva más de 1 s sin atender (el «cuelgue» que ve el usuario).
    private nonisolated(unsafe) static var heartbeat = Date()
    private nonisolated(unsafe) static var maxStall = 0.0
    static func startWatchdog() {
        Task { @MainActor in while !Task.isCancelled { heartbeat = Date(); try? await Task.sleep(nanoseconds: 100_000_000) } }   // ds-exception: banco de pruebas de Debug, no es diseño
        Thread.detachNewThread {
            while true {
                Thread.sleep(forTimeInterval: 0.25)
                let stall = Date().timeIntervalSince(heartbeat)
                if stall > maxStall { maxStall = stall }
                if stall > 1 { print(String(format: "MOSAIC-BENCH watchdog: el hilo principal lleva %.1f s sin atender", stall)); fflush(stdout) }
            }
        }
    }

    static func runIfRequested(_ runtime: MosaicRuntime, focus: @escaping (Int, Int) -> Void) async {
        guard Demo.mosaicBench else { return }
        startWatchdog()
        while runtime.isEmpty { try? await Task.sleep(nanoseconds: 200_000_000) }   // ds-exception: banco de pruebas de Debug, no es diseño
        try? await Task.sleep(nanoseconds: 4_000_000_000)   // ds-exception: banco de pruebas de Debug, no es diseño
        await phase("scroll", seconds: 8, runtime: runtime) { dt, t in
            let direction: Double = Int(t / 2) % 2 == 0 ? 1 : -1
            runtime.scrollBy(direction * 700 * dt)
        }
        runtime.endScroll()
        try? await Task.sleep(nanoseconds: 1_000_000_000)   // ds-exception: banco de pruebas de Debug, no es diseño
        var n = 0
        await phase("focus", seconds: 6, runtime: runtime) { _, t in
            if Int(t * 2) > n { n = Int(t * 2); focus(n % 4, n / 4 % 3) }
        }
        print("MOSAIC-BENCH done"); fflush(stdout)
    }

    private static func phase(_ name: String, seconds: Double, runtime: MosaicRuntime, step: @escaping (Double, Double) -> Void) async {
        counts = [:]
        print("MOSAIC-BENCH start \(name)")
        let driver = Driver(seconds: seconds, onFrame: step)
        await driver.run()
        let d = driver.deltas.sorted()
        guard !d.isEmpty else { return }
        let budget = driver.budget
        let avg = d.reduce(0, +) / Double(d.count)
        func pct(_ p: Double) -> Double { d[min(d.count - 1, Int(Double(d.count) * p))] * 1000 }
        let hitches = d.filter { $0 > budget * 1.5 }.count
        let tiles = runtime.columns.reduce(0) { $0 + $1.tiles.count }
        defer { fflush(stdout) }
        print(String(format: "MOSAIC-BENCH %@ frames=%d fps=%.1f avg=%.1fms p50=%.1fms p95=%.1fms p99=%.1fms max=%.1fms hitches=%d (>%.1fms) liveTiles=%d mem=%.0fMB stall=%.1fs bodies=%@",
                     name, d.count, 1 / avg, avg * 1000, pct(0.5), pct(0.95), pct(0.99), d.last! * 1000, hitches, budget * 1.5 * 1000, tiles, footprintMB(), maxStall, "\(counts.sorted { $0.key < $1.key })"))
    }

    @MainActor private final class Driver: NSObject {
        let seconds: Double
        let onFrame: (Double, Double) -> Void
        var deltas: [Double] = []
        var budget = 1.0 / 60
        private var link: CADisplayLink?
        private var last = 0.0, start = 0.0
        private var continuation: CheckedContinuation<Void, Never>?
        init(seconds: Double, onFrame: @escaping (Double, Double) -> Void) { self.seconds = seconds; self.onFrame = onFrame }

        func run() async {
            await withCheckedContinuation { c in
                continuation = c
                let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
                link.add(to: .main, forMode: .common)
                self.link = link
            }
        }

        @objc private func frame(_ l: CADisplayLink) {
            if start == 0 { start = l.timestamp; last = l.timestamp; budget = l.targetTimestamp - l.timestamp; return }
            let dt = l.timestamp - last; last = l.timestamp
            deltas.append(dt)
            onFrame(dt, l.timestamp - start)
            if l.timestamp - start >= seconds { l.invalidate(); continuation?.resume(); continuation = nil }
        }
    }
}
#endif
