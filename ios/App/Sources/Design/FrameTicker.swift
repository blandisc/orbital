import SwiftUI
import OrbitalCore
import OrbitalModels

/// Una función por cuadro de pantalla (`CADisplayLink`, hasta 120 Hz), para las inercias del mosaico.

/// Llama a una función en cada cuadro de la pantalla (`CADisplayLink`, hasta 120 Hz) con el tiempo desde el anterior,
/// hasta que la función devuelve `false` o se detiene. Una pausa fija (`Task.sleep`) no cae con los cuadros y se veía trabado.
@MainActor
final class FrameTicker {
    private var link: CADisplayLink?
    private var onFrame: ((Double) -> Bool)?
    private var last: CFTimeInterval = 0
    private lazy var target = Target(self)

    var isRunning: Bool { link != nil }

    func start(_ frame: @escaping (Double) -> Bool) {
        stop()
        onFrame = frame
        last = 0
        let link = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() { link?.invalidate(); link = nil; onFrame = nil }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = last == 0 ? link.duration : link.targetTimestamp - last
        last = link.targetTimestamp
        if onFrame?(dt) == false { stop() }
    }

    /// `CADisplayLink` retiene a su destino: un objeto aparte (con referencia débil) para no retener al reloj.
    @MainActor private final class Target: NSObject {   // `CADisplayLink` llama en el hilo principal
        weak var owner: FrameTicker?
        init(_ owner: FrameTicker) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
    }
}
