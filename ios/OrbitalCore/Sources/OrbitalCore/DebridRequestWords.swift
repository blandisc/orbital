import Foundation
import OrbitalAddons

/// Cómo se dice cada estado de un pedido a Real-Debrid (R13), igual en la ficha, en «Seguir viendo», en «Tus pedidos» y en
/// el aviso. Cada estado lleva palabra e ícono, no solo color (A1). Todos los textos viven aquí: las pantallas piden `title`,
/// `detail` y `symbol`. `tr` traduce al idioma de la app.
public enum DebridRequestWords {
    // pendiente: «Bajando en Real-Debrid · » y «Real-Debrid no lo dejó bajar» son de design/vocabulario.json › causas (los
    // dice también la TV); los otros cuatro estados, de la propuesta v5 (R13), acordados con la TV como sus seis estados.
    /// El renglón principal: «Bajando en Real-Debrid · 42 %», «En cola»…
    public static func title(_ request: DebridRequest, _ tr: (String) -> String = { $0 }) -> String {
        switch request.state {
        case .queued: tr("En cola")
        case .downloading: UnavailableCause.downloading(percent: request.percent).title(tr)
        case .noPeers: tr("Sin gente que lo comparta")
        case .refused: UnavailableCause.debridRefused.title(tr)
        case .tooMany: tr("Muchas descargas activas")
        case .ready: tr("Listo")
        case .gone: tr("Pedido cancelado")   // la lápida no se enseña; por si acaso, lo que pasó
        }
    }

    /// El renglón corto de la lista («Bajando · 42 %»).
    public static func short(_ request: DebridRequest, _ tr: (String) -> String = { $0 }) -> String {
        request.state == .downloading ? String(format: tr("Bajando · %lld %%"), request.percent) : title(request, tr)
    }

    /// El renglón de abajo: qué pasa y qué sigue, sin prometer.
    public static func detail(_ request: DebridRequest, now: Date, _ tr: (String) -> String = { $0 }) -> String {
        if request.isStalled(now: now) { return tr("Sigue sin bajar · ¿probar otra versión?") }
        return switch request.state {
        case .queued: tr("Real-Debrid lo recibió y espera turno")
        case .downloading: tr("Te aviso cuando esté listo")
        case .noPeers: tr("Puede tardar días · prueba otra versión")
        case .refused: tr("Prueba otra versión")
        case .tooMany: tr("Cancela otra descarga para hacer lugar")
        case .ready: tr("Ya arranca al instante")
        case .gone: ""
        }
    }

    /// «Lo pediste en iPhone · hace 6 min» (quién y cuándo, R12). Lo de otra cuenta de Real-Debrid (`otherAccount`) nunca
    /// es «lo pediste»: «Lo pidió la TV · …» o, si lo pidió otro aparato, «Lo pidió iPad · …».
    public static func since(_ request: DebridRequest, now: Date, otherAccount: Bool = false, _ tr: (String) -> String = { $0 }) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(request.createdAt) / 60))
        let ago = minutes < 60 ? String(format: tr("hace %lld min"), max(1, minutes))
            : minutes < 24 * 60 ? String(format: tr("hace %lld h"), minutes / 60)
            : minutes < 48 * 60 ? tr("hace 1 día") : String(format: tr("hace %lld días"), minutes / (24 * 60))
        // Lo pidió la TV (su libreta, S2/S4): se dice así, no «lo pediste en TV».
        if request.device == "TV" || (otherAccount && request.device.isEmpty) { return String(format: tr("Lo pidió la TV · %@"), ago) }
        if otherAccount { return String(format: tr("Lo pidió %@ · %@"), request.device, ago) }
        return String(format: tr("Lo pediste en %@ · %@"), request.device, ago)
    }

    /// ¿Un problema? (el ícono va en ámbar): rechazado, sin gente, demasiadas descargas o atorado.
    public static func isTrouble(_ request: DebridRequest, now: Date) -> Bool {
        [.refused, .noPeers, .tooMany].contains(request.state) || request.isStalled(now: now)
    }

    /// El ícono de cada estado (SF Symbols).
    public static func symbol(_ state: DebridRequest.State) -> String {
        switch state {
        case .queued: "hourglass"
        case .downloading: "arrow.down.circle"
        case .noPeers: "person.2.slash"
        case .refused: "nosign"
        case .tooMany: "exclamationmark.triangle"
        case .ready: "checkmark.circle"
        case .gone: "xmark.circle"
        }
    }
}

public extension UnavailableCause {
    /// Lo que dijo Real-Debrid al pedirlo, como causa (R7): la clave, tu cuenta o el archivo. nil si no es una causa (la red,
    /// «más despacio»: se dice aparte) o si es un estado del pedido («Muchas descargas activas»).
    static func from(_ error: RDRequestError) -> UnavailableCause? {
        switch error {
        case .noKey, .invalidKey: .reconnectDebrid
        case .notPremium: .noPremium
        case .refused: .debridRefused
        case .tooManyActive, .slowDown, .notFound, .network, .unexpected: nil
        }
    }
}

public extension RDRequestError {
    /// En palabras, para el aviso cuando no es una causa.
    func words(_ tr: (String) -> String = { $0 }) -> String {
        switch self {
        case .tooManyActive: tr("Muchas descargas activas")
        case .slowDown: tr("Real-Debrid pide esperar un momento")
        default: tr("No pude hablar con Real-Debrid")
        }
    }
}
