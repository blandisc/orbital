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
    /// FQ5-A (Fernando, 3 nov): tu TV ya lo tiene listo, pedido con otra cuenta de Real-Debrid (aquí no existe ese enlace): «Lo
    /// tiene tu TV con otra cuenta» con «Ver en la TV» (manda el título y el episodio, nunca el enlace) y aparte «Pedir a la
    /// nube aquí».
    case onTV(DebridRequest)
    /// «Avisarme cuando aparezca» (R15): nadie lo tiene todavía en internet.
    case notifyWhenAppears
    /// Un episodio que todavía no sale: «Sale el …».
    case airs(Date)
    /// No hay qué ver y no hay a quién pedirlo: «Ver» con la causa debajo (y su salida al tocarlo).
    case unavailable
}

/// Lo que dice «Ver» cuando no hay qué poner (la vista lo pinta; la decisión vive aquí para que una prueba diga qué sale en
/// cada versión, D1-B).
public enum PlayFallback: Equatable, Sendable {
    /// Un aviso con la causa de la tabla común y su salida.
    case cause(UnavailableCause)
    /// La primera vez sin Real-Debrid: la historia de Aprende (termina en «Conectar Real-Debrid»).
    case story(String)
    /// Sin internet en el aparato: «Sin internet · No pude buscar dónde verlo».
    case noInternet
}

extension TitleModel {
    /// ¿Esta versión ve al instante con Real-Debrid? Sin eso (Orbital, App Store) la ficha no enseña pedidos, la nube ni
    /// «Pedir a la nube» (D1-B).
    public var offersInstant: Bool { services.capabilities.instantStreams }

    /// El botón principal ahora. nil mientras no se sabe qué video toca.
    public func primary(now: Date = Date()) -> TitlePrimary? {
        guard continueVideoID != nil else { return nil }
        // Sin Real-Debrid en esta versión (Orbital) no hay pedidos ni «Lo tiene tu TV»: solo ver, avisar o la fecha (D1-B).
        if offersInstant, continueAirs == nil, recommendedSource?.instant != true {
            // «Muchas descargas activas» (error 21): Real-Debrid no lo agregó y nadie lo vuelve a pedir solo. Se ofrece pedirlo
            // otra vez (con esa línea), como la TV; antes quedaba «en camino» para siempre (escenarios comunes, 3 nov).
            if let request = debridRequest, request.state != .ready, request.state != .tooMany {
                return DebridRequestWords.suggestsOtherVersion(request, now: now) ? .otherVersion(request) : .requested(request)
            }
            if let tv = otherAccountReady { return .onTV(tv) }
            if debridOffer != nil, sourceCheck != .offline { return .request }
        }
        // Nadie lo tiene o aún no se estrena: «Avisarme cuando aparezca» es su salida (antes, una película por estrenarse no
        // tenía ninguna).
        if sourceCheck == .none, unavailableCause == .nobodyHasIt || unavailableCause?.isUnreleased == true { return .notifyWhenAppears }
        if let airs = continueAirs { return .airs(airs) }
        return sourceCheck == .none || sourceCheck == .offline ? .unavailable : .watch
    }

    /// «Ver» sin versiones (`sourceCheck` .none) o sin respuesta de nadie (.offline); `online`: el aparato tiene internet. Sin
    /// «ver al instante» en la versión (Orbital) nunca habla de Real-Debrid ni de complementos.
    public func playFallback(online: Bool = true) -> PlayFallback {
        if sourceCheck == .offline {
            guard online else { return .noInternet }
            // Ningún complemento contestó con red: son ellos (la causa 8 de la tabla común).
            return .cause(unavailableCause ?? UnavailableCause.addonsOffline.shown(instant: offersInstant))
        }
        // Si se sabe por qué (tu Real-Debrid venció, sin Premium, complementos apagados…), eso es lo que pasa, con su salida.
        if let cause = unavailableCause { return .cause(cause.shown(instant: offersInstant)) }
        guard offersInstant else { return .cause(.nobodyHasIt) }
        // Sin tu clave de Real-Debrid en la app casi no hay versiones que se vean aquí. D1: la primera vez, la historia.
        if !services.debrid.hasToken { return LearnModel(services).seen(LearnContent.instant.id) ? .cause(.reconnectDebrid) : .story(LearnContent.instant.id) }
        return .cause(.notInDebrid(language: recommendedLanguage ?? services.appSettings.audio))
    }
}
