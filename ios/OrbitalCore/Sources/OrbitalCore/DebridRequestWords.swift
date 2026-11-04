import Foundation
import OrbitalAddons

/// Cómo se dice cada estado de un pedido a Real-Debrid (R13), igual en la ficha, en «Seguir viendo», en «Tus pedidos» y en
/// el aviso. Cada estado lleva palabra e ícono, no solo color (A1). Todos los textos viven aquí: las pantallas piden `title`,
/// `detail` y `symbol`. `tr` traduce al idioma de la app.
public enum DebridRequestWords {
    // pendiente: «Bajando en la nube · » y «Real-Debrid no lo dejó bajar» son de design/vocabulario.json › causas (los
    // dice también la TV; «la nube» va pendiente en la TV, RX4-A); los otros cuatro estados, de la propuesta v5 (R13),
    // acordados con la TV como sus seis estados.
    /// El renglón principal: «Bajando en la nube · 42 %», «En cola»…
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

    /// El renglón de abajo: qué pasa y qué sigue, sin prometer. IOS-8: «Te aviso cuando esté listo» solo si este aparato va
    /// a avisar (`notifies`: con permiso y pedido desde aquí); si no, «Ábrelo aquí para ver cuánto lleva».
    public static func detail(_ request: DebridRequest, now: Date, notifies: Bool = true, _ tr: (String) -> String = { $0 }) -> String {
        if request.isStalled(now: now) { return tr("Sigue sin bajar · ¿probar otra versión?") }
        return switch request.state {
        case .queued: tr("La nube lo recibió y espera turno")
        case .downloading: notifies ? tr("Te aviso cuando esté listo") : tr("Ábrelo aquí para ver cuánto lleva")
        case .noPeers: tr("Puede tardar días · prueba otra versión")
        case .refused: tr("Prueba otra versión")
        case .tooMany: tr("Cancela otra descarga para hacer lugar")
        case .ready: tr("Ya arranca al instante")
        case .gone: ""
        }
    }

    /// RX2-A · qué tan lejos está, sin prometer de más: a partir de lo que ha avanzado desde que se pidió (el promedio, que
    /// cuenta también lo que esperó en cola, así que nunca promete menos de lo que va a tardar). Sin avance suficiente que
    /// medir (menos de 3 % o menos de un minuto), en cola o atorado: no se sabe.
    public enum Pace: Equatable, Sendable { case minutes, underAnHour, hours, overADay, unknown }

    public static func pace(_ request: DebridRequest, now: Date) -> Pace {
        guard request.state == .downloading, (3..<100).contains(request.percent), !request.isStalled(now: now) else { return .unknown }
        let elapsed = now.timeIntervalSince(request.createdAt)
        guard elapsed >= 60 else { return .unknown }
        let left = elapsed * Double(100 - request.percent) / Double(request.percent)
        switch left {
        case ..<(15 * 60): return .minutes
        case ..<(60 * 60): return .underAnHour
        case ..<(24 * 60 * 60): return .hours
        default: return .overADay
        }
    }

    /// RX2-A · el renglón de la hoja de un pedido en camino: «A este paso, falta menos de una hora. Te aviso.» o, si no se
    /// puede medir, «Suele tardar de minutos a horas.». «Te aviso» solo si este aparato va a avisar (IOS-8). Lo que no va en
    /// camino (sin gente, muchas descargas, atorado, listo) dice lo de siempre (`detail`).
    public static func paceLine(_ request: DebridRequest, now: Date, notifies: Bool, _ tr: (String) -> String = { $0 }) -> String {
        guard [.queued, .downloading].contains(request.state), !request.isStalled(now: now) else {
            return detail(request, now: now, notifies: notifies, tr)
        }
        let pace = switch pace(request, now: now) {
        case .minutes: tr("A este paso, faltan unos minutos.")
        case .underAnHour: tr("A este paso, falta menos de una hora.")
        case .hours: tr("A este paso, faltan unas horas.")
        case .overADay: tr("A este paso, falta más de un día.")
        case .unknown: tr("Suele tardar de minutos a horas.")
        }
        return notifies ? pace + " " + tr("Te aviso.") : pace
    }

    /// «Lo pediste en iPhone · hace 6 min» (quién y cuándo, R12). Lo de otra cuenta de Real-Debrid (`otherAccount`) nunca
    /// es «lo pediste»: «Lo pidió la TV · … · con otra cuenta de Real-Debrid» o, si lo pidió otro aparato, «Lo pidió iPad · …».
    public static func since(_ request: DebridRequest, now: Date, otherAccount: Bool = false, _ tr: (String) -> String = { $0 }) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(request.createdAt) / 60))
        let ago = minutes < 60 ? String(format: tr("hace %lld min"), max(1, minutes))
            : minutes < 24 * 60 ? String(format: tr("hace %lld h"), minutes / 60)
            : minutes < 48 * 60 ? tr("hace 1 día") : String(format: tr("hace %lld días"), minutes / (24 * 60))
        // Lo pidió la TV (su libreta, S2/S4): se dice así, no «lo pediste en TV».
        // IOS-19: lo de otra cuenta lo dice, como la TV («· con otra cuenta de Real-Debrid»).
        let other = otherAccount ? " · " + tr("con otra cuenta de Real-Debrid") : ""
        if request.device == "TV" || (otherAccount && request.device.isEmpty) { return String(format: tr("Lo pidió la TV · %@"), ago) + other }
        if otherAccount { return String(format: tr("Lo pidió %@ · %@"), request.device, ago) + other }
        return String(format: tr("Lo pediste en %@ · %@"), request.device, ago)
    }

    /// ¿Un problema? (el ícono va en ámbar): rechazado, sin gente, demasiadas descargas o atorado.
    public static func isTrouble(_ request: DebridRequest, now: Date) -> Bool {
        [.refused, .noPeers, .tooMany].contains(request.state) || request.isStalled(now: now)
    }

    /// P1-A · los dos grupos de «Tus pedidos»: lo que todavía falta y lo que ya terminó (bien o mal). Como las descargas de
    /// iOS: nunca pierdes de vista lo que todavía no está.
    public enum Group: Sendable, Equatable, CaseIterable {
        /// «Bajando»: en cola, bajando, sin gente que lo comparta, muchas descargas activas.
        case pending
        /// «Ya terminaron»: listo o Real-Debrid no lo dejó bajar.
        case finished
    }

    public static func group(_ state: DebridRequest.State) -> Group {
        switch state {
        case .queued, .downloading, .noPeers, .tooMany: .pending
        case .ready, .refused, .gone: .finished
        }
    }

    /// Los pedidos en sus grupos, en el orden de la lista y sin grupos vacíos. Lo de otra cuenta va donde diga su estado.
    public static func grouped(_ requests: [DebridRequest]) -> [(group: Group, requests: [DebridRequest])] {
        Group.allCases.compactMap { g in
            let these = requests.filter { group($0.state) == g }
            return these.isEmpty ? nil : (g, these)
        }
    }

    /// P2-B · la hoja del pedido ofrece «Probar otra versión» solo cuando ayuda: Real-Debrid no lo dejó bajar, nadie lo
    /// comparte o lleva 24 h sin avanzar.
    public static func suggestsOtherVersion(_ request: DebridRequest, now: Date) -> Bool {
        [.refused, .noPeers].contains(request.state) || request.isStalled(now: now)
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
