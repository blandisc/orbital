import Foundation

/// Por qué no hay una versión que arranque ya, en palabras y con UNA salida (D5, R1, R7). Las causas van en el orden de
/// `design/vocabulario.json › causas` (la primera que aplique gana), el mismo de la TV; la ficha y el reproductor dicen lo
/// mismo. Todos los textos viven aquí y solo aquí: las pantallas piden `title`, `detail` y `action`.
public enum UnavailableCause: Equatable, Sendable {
    /// 1 · Real-Debrid lo está bajando y se sabe cuánto lleva (la libreta de pedidos, Fase 2: aún no se usa).
    case downloading(percent: Int)
    /// 2 · Aún no se estrena (`day`: «el viernes 6»).
    case unreleased(day: String)
    /// 3 · No se pudo ni buscar (`reason`: el error en palabras).
    case cannotSearch(reason: String)
    /// 4 · Tu Premium venció.
    case debridExpired
    /// 5 · La cuenta es gratuita.
    case noPremium
    /// 6 · Real-Debrid ya no reconoce tu clave.
    case reconnectDebrid
    /// 7 · Real-Debrid no lo dejó bajar (derechos reclamados, límite, archivo que no pudo abrir…).
    case debridRefused
    /// 8 · Ningún complemento contestó.
    case addonsOffline
    /// 9 · No hay complementos de video prendidos.
    case noAddonsOn
    /// 10 · Real-Debrid todavía no lo tiene (`language`: el idioma que quieres: «es-419», «en»).
    case notInDebrid(language: String)
    /// 11 · Nadie lo tiene todavía en internet.
    case nobodyHasIt

    /// La única salida de cada causa.
    public enum Action: Equatable, Sendable {
        /// Abre real-debrid.com en el navegador.
        case renew
        /// Abre Ajustes (Cuentas o Complementos).
        case settings
        case retry
        /// Elegir otra versión (Versión).
        case otherVersion
    }

    // pendiente: texto de la tabla común con la TV — ya está en design/vocabulario.json › causas (3 nov 2026); si cambia ahí,
    // cambia aquí y en la TV.
    /// El título, en español (la clave del catálogo de textos). `tr` traduce al idioma de la app.
    public func title(_ tr: (String) -> String = { $0 }) -> String {
        switch self {
        case .downloading(let percent): String(format: tr("Bajando en Real-Debrid · %lld %%"), percent)
        case .unreleased(let day): String(format: tr("Aún no se estrena · sale %@"), day)
        case .cannotSearch: tr("No puedo buscar versiones")
        case .debridExpired: tr("Tu Real-Debrid venció")
        case .noPremium: tr("Tu cuenta no tiene Premium")
        case .reconnectDebrid: tr("Vuelve a conectar Real-Debrid")
        case .debridRefused: tr("Real-Debrid no lo dejó bajar")
        case .addonsOffline: tr("No pude conectar con tus complementos")
        case .noAddonsOn: tr("No tienes complementos prendidos")
        case .notInDebrid: tr("Real-Debrid todavía no lo tiene")
        case .nobodyHasIt: tr("Nadie lo tiene todavía en internet")
        }
    }

    /// El renglón de abajo (nil si la causa no lleva).
    /// `languageName` dice un idioma en palabras («es-419» → «latino»).
    public func detail(_ tr: (String) -> String = { $0 }, languageName: (String) -> String = { $0 }) -> String? {
        switch self {
        case .downloading: tr("Te aviso cuando esté listo")
        case .unreleased: tr("Cuando salga, aparece aquí")
        case .cannotSearch(let reason): reason
        case .debridExpired, .noPremium, .reconnectDebrid: nil
        case .debridRefused: tr("Prueba otra versión")
        case .addonsOffline: tr("Revisa Internet e inténtalo de nuevo")
        case .noAddonsOn: tr("Ajustes › Complementos")
        case .notInDebrid(let language):
            String(format: tr("Lo puede bajar por ti, de preferencia en %@; tarda según cuánta gente lo comparte"), languageName(language))
        case .nobodyHasIt: tr("Suele aparecer en unas horas o días · vuelve a buscar más tarde")
        }
    }

    public var action: Action? {
        switch self {
        case .debridExpired, .noPremium: .renew
        case .reconnectDebrid, .noAddonsOn: .settings
        case .debridRefused: .otherVersion
        case .addonsOffline, .cannotSearch: .retry
        case .downloading, .unreleased, .notInDebrid, .nobodyHasIt: nil
        }
    }

    /// El nombre del botón de la salida.
    public static func label(_ action: Action, _ tr: (String) -> String = { $0 }) -> String {
        switch action {
        case .renew: tr("Renovar")
        case .settings: tr("Ajustes")
        case .retry: tr("Reintentar")
        case .otherVersion: tr("Elegir otra versión")
        }
    }

    /// Cómo está tu cuenta para decir la causa: lo que contestó Real-Debrid ahora o, si no, lo guardado.
    public enum Account: Equatable, Sendable { case ok, expired, free, invalidKey, unknown }

    /// La causa que toca, en el orden de la tabla. `notice`: el aviso de Torrentio de este video (si hubo); `account`: tu
    /// Real-Debrid; `language`: el que quieres, en palabras. nil si no se sabe nada mejor que el mensaje de siempre.
    public static func first(notice: StreamNotice?, account: Account, language: String) -> UnavailableCause? {
        // 4 a 6: lo de tu cuenta va primero (con la cuenta vencida, todo lo demás falla igual).
        switch account {
        case .expired: return .debridExpired
        case .free: return .noPremium
        case .invalidKey: return .reconnectDebrid
        case .ok, .unknown: break
        }
        switch notice {
        case .access?, .blocked?, .infringing?, .limits?, .downloadFailed?: return .debridRefused
        case .downloading?: return .notInDebrid(language: language)
        case nil: return nil
        }
    }
}
