import Foundation

/// Por qué algo no llegó, dicho por su causa de verdad, y qué puede hacer quien usa la app. Antes casi todo terminaba en
/// «Revisa tu conexión» aunque el iPhone tuviera internet y el problema fuera Trakt, un complemento o Real-Debrid.
/// La tabla completa de escenarios (qué se ve en cada pantalla y cómo simularlo) vive en `docs/producto/modo-degradado.md`.
public enum Degraded: Equatable, Sendable {
    /// El iPhone no tiene internet. Lo guardado en el teléfono sigue: descargas, Seguir viendo, Mi lista.
    case offline
    /// Hay internet, pero ese servicio no contesta (caído, lento, error suyo).
    case down(Service)
    /// Falta conectarlo, o su sesión se cerró: la salida está en Ajustes.
    case notConnected(Service)

    public enum Service: String, Sendable, CaseIterable {
        case trakt, realDebrid, addons, orbital, tmdb
    }

    /// La salida que se ofrece con el aviso.
    public enum Action: Equatable, Sendable {
        /// Volver a intentar (la falla suele ser momentánea).
        case retry
        /// Ajustes, donde se conecta el servicio.
        case settings
        /// Descargas: lo que se ve sin internet.
        case downloads
    }

    /// La causa a partir de un error y de si el iPhone tiene red: sin red, siempre «sin internet» (aunque el error diga
    /// otra cosa); un 401/403 es la sesión; lo demás, que el servicio no contestó.
    public static func classify(_ error: Error?, service: Service, online: Bool) -> Degraded {
        if !online || isOffline(error) { return .offline }
        if let error, isAuth(error) { return .notConnected(service) }
        return .down(service)
    }

    /// Un error de «el iPhone no tiene red» (y no de «el servidor no contestó»).
    public static func isOffline(_ error: Error?) -> Bool {
        let offlineCodes: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff]
        if let error = error as? URLError { return offlineCodes.contains(error.code) }
        if let error = error as? NetworkError, let code = error.code { return offlineCodes.contains(code) }
        return false
    }

    /// Un error de sesión (la cuenta ya no deja entrar).
    public static func isAuth(_ error: Error) -> Bool {
        let text = "\(error)"
        return text.contains("HTTP 401") || text.contains("HTTP 403")
    }

    /// El título del aviso (en español: es su clave en el catálogo de textos).
    public var title: String {
        switch self {
        case .offline: "Sin internet"
        case .down(.trakt): "Trakt no contesta"
        case .down(.realDebrid): "Real-Debrid no contesta"
        case .down(.addons): "Tus complementos no contestan"
        case .down(.orbital): "Tu Orbital no contesta"
        case .down(.tmdb): "TMDB no contesta"
        case .notConnected(.trakt): "Conecta Trakt"
        case .notConnected(.realDebrid): "Falta conectar Real-Debrid"
        case .notConnected(.addons): "Faltan tus complementos"
        case .notConnected(.orbital): "Conecta tu Orbital"
        case .notConnected(.tmdb): "Falta la clave de TMDB"
        }
    }

    /// Qué pasa y qué sigue funcionando, en una o dos frases.
    public var detail: String {
        switch self {
        case .offline: "Lo que está en el iPhone sigue aquí: tus descargas, Seguir viendo y Mi lista. Lo que marques se sincroniza al volver la red."
        case .down(.trakt): "Hay internet, pero Trakt no responde. Lo tuyo está guardado en el iPhone y se sincroniza solo cuando vuelva."
        case .down(.realDebrid): "Hay internet, pero Real-Debrid no responde. Suele ser momentáneo; lo descargado sí se puede ver."
        case .down(.addons): "Hay internet, pero ninguno respondió. Suele ser momentáneo; si sigue, revisa tus complementos en Stremio."
        case .down(.orbital): "Revisa que la consola esté prendida y en la misma red que el iPhone."
        case .down(.tmdb): "Faltan algunas imágenes y colecciones; lo demás funciona."
        case .notConnected(.trakt): "Lo más popular, los géneros y tus recomendaciones vienen de Trakt. Conéctalo en Ajustes."
        case .notConnected(.realDebrid): "Con Real-Debrid se ven y se descargan las películas y series. Agrega tu cuenta en Ajustes."
        case .notConnected(.addons): "No hay complementos que den dónde verlo. Agrégalos en Stremio y vuelve a entrar."
        case .notConnected(.orbital): "Prende «Usar con tu Orbital» en Ajustes para ver lo de la consola."
        case .notConnected(.tmdb): "Sin ella faltan colecciones y pósters sin texto. Agrégala en Ajustes › Avanzado."
        }
    }

    /// La salida principal.
    public var action: Action {
        switch self {
        case .offline: .downloads
        case .down: .retry
        case .notConnected: .settings
        }
    }

    /// El texto del botón de la salida.
    public var actionTitle: String {
        switch action {
        case .retry: "Intentar de nuevo"
        case .settings: "Abrir Ajustes"
        case .downloads: "Tus descargas"
        }
    }

    /// El ícono (SF Symbol) que acompaña al aviso.
    public var symbol: String {
        switch self {
        case .offline: "wifi.slash"
        case .down: "exclamationmark.icloud"
        case .notConnected: "link.badge.plus"
        }
    }
}
