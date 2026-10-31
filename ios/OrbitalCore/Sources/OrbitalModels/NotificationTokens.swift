import Foundation

/// Los avisos de NotificationCenter que escucha un modelo: se dejan de escuchar cuando el modelo se va (al irse esta bolsa).
/// Antes los tokens nunca se quitaban: cada Inicio o Para ti que se armaba de nuevo dejaba su observador en el centro
/// (auditoría, 31 oct 2026, C4). Es una clase aparte porque el `deinit` de un modelo (@MainActor) no puede leer sus
/// propiedades; esta sí se puede soltar desde cualquier hilo.
final class NotificationTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []
    private let center: NotificationCenter

    init(center: NotificationCenter = .default) { self.center = center }

    /// Escucha `name` en el hilo principal mientras viva la bolsa.
    func observe(_ name: Notification.Name, _ handler: @escaping @Sendable (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main, using: handler)
        lock.withLock { tokens.append(token) }
    }

    var count: Int { lock.withLock { tokens.count } }

    deinit { for token in tokens { center.removeObserver(token) } }
}
