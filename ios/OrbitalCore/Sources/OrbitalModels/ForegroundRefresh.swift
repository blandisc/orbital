import Foundation

/// Cuándo volver a pedir lo de la red al regresar a la app (calificaciones, biblioteca, estrenos, elecciones, recordatorio de
/// Real-Debrid). Antes se pedían cinco cosas cada vez que la app quedaba activa: también al bajar el Centro de control o una
/// notificación (la app ni se fue), al cambiar de app cada pocos segundos y, al abrir en frío, la biblioteca dos veces
/// (auditoría del 31 oct 2026, C5).
public struct ForegroundRefresh: Sendable {
    public enum Decision: Equatable, Sendable {
        /// La primera vez que la app queda activa: todo menos la biblioteca, que ya pide el arranque.
        case launch
        /// De regreso de segundo plano, y hace rato de la última vez: todo.
        case refresh
        /// No se fue de verdad (Centro de control, una notificación) o volvió hace poco: nada.
        case skip
    }

    /// Lo mínimo entre una vuelta y otra.
    public static let minimumGap: TimeInterval = 120

    private var seenActive = false
    private var backgrounded = false
    private var last: Date?

    public init() {}

    /// La app se fue a segundo plano (no solo «inactiva»).
    public mutating func wentToBackground() { backgrounded = true }

    public mutating func becameActive(at now: Date) -> Decision {
        defer { seenActive = true }
        if !seenActive, !backgrounded { last = now; return .launch }
        guard backgrounded else { return .skip }
        backgrounded = false
        if let last, now.timeIntervalSince(last) < Self.minimumGap { return .skip }
        last = now
        return .refresh
    }
}
