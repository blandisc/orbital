import Foundation
import OrbitalCore
import OrbitalAddons

/// Qué es el botón principal de la ficha (Fernando, 3 nov: «análisis de fondo… para que no encuentre yo más errores»). La
/// decisión vive aquí, no en la vista: la ficha la pinta y las pruebas de los escenarios comunes con la TV
/// (`tests/fixtures/rd-scenarios`) la leen igual. El orden es el de siempre de la ficha: lo de Real-Debrid, «Avisarme cuando
/// aparezca», la fecha de estreno y, al final, «Ver».
public enum TitlePrimary: Equatable, Sendable {
    /// «Ver» (o «Continuar») con la versión que va a sonar (`recommendedSource`).
    case watch
    /// «Pedirlo y avisarme» (R2-A): existe, pero Real-Debrid todavía no lo tiene (`debridOffer`).
    case request
    /// Ya lo pediste y sigue en camino: «Bajando en Real-Debrid · 42 %», «En cola»…
    case requested(DebridRequest)
    /// Lo pedido se atoró o Real-Debrid no lo dejó bajar: «Probar otra versión».
    case otherVersion(DebridRequest)
    /// «Avisarme cuando aparezca» (R15): nadie lo tiene todavía en internet.
    case notifyWhenAppears
    /// Un episodio que todavía no sale: «Sale el …».
    case airs(Date)
    /// No hay qué ver y no hay a quién pedirlo: «Ver» con la causa debajo (y su salida al tocarlo).
    case unavailable
}

extension TitleModel {
    /// El botón principal ahora. nil mientras no se sabe qué video toca.
    public func primary(now: Date = Date()) -> TitlePrimary? {
        guard continueVideoID != nil else { return nil }
        if continueAirs == nil, recommendedSource?.instant != true {
            if let request = debridRequest, request.state != .ready {
                return DebridRequestWords.suggestsOtherVersion(request, now: now) ? .otherVersion(request) : .requested(request)
            }
            if debridOffer != nil, sourceCheck != .offline { return .request }
        }
        // Nadie lo tiene o aún no se estrena: «Avisarme cuando aparezca» es su salida (antes, una película por estrenarse no
        // tenía ninguna).
        if sourceCheck == .none, unavailableCause == .nobodyHasIt || unavailableCause?.isUnreleased == true { return .notifyWhenAppears }
        if let airs = continueAirs { return .airs(airs) }
        return sourceCheck == .none || sourceCheck == .offline ? .unavailable : .watch
    }
}
