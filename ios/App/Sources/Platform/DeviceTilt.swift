import CoreMotion
import UIKit

/// Hacia dónde está inclinado el teléfono, con el acelerómetro (como YouTube e Infuse): el reproductor gira solo aunque
/// tengas puesto el candado de rotación (iOS no avisa del giro con el candado). Solo mientras el reproductor está abierto.
@MainActor
final class DeviceTilt {
    enum Pose: Equatable { case portrait, landscapeLeft, landscapeRight }
    private let motion = CMMotionManager()
    private var candidate: Pose?
    private var since = Date()
    private(set) var pose: Pose?
    var onChange: (Pose) -> Void = { _ in }

    static let threshold = 0.72, hold: TimeInterval = 0.35, interval = 0.1

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = Self.interval
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let g = data?.gravity else { return }
            MainActor.assumeIsolated { self.read(x: g.x, y: g.y) }
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }

    private func read(x: Double, y: Double) {
        // Bien inclinado hacia un lado (no plano sobre la mesa): x manda la horizontal, y la vertical.
        let next: Pose?
        if x < -Self.threshold { next = .landscapeRight }        // la orilla izquierda hacia abajo: la pantalla gira a la derecha
        else if x > Self.threshold { next = .landscapeLeft }
        else if y < -Self.threshold { next = .portrait }
        else { next = nil }
        guard let next else { candidate = nil; return }
        if next != candidate { candidate = next; since = Date(); return }
        // Unas décimas en la misma postura (no un movimiento de paso).
        guard next != pose, Date().timeIntervalSince(since) >= Self.hold else { return }
        pose = next
        onChange(next)
    }
}
