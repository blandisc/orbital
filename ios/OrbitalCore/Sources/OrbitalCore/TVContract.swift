import Foundation

/// F1 · lo que tu Orbital de la tele dice de sí misma en `/api/ping` y `/api/companion`: `api` (la versión del contrato) y
/// `capabilities` (lo que sabe hacer, con nombres estables: `orbital/companion.py` › `CAPABILITIES`). Una TV de antes no manda
/// `api`: entonces no se sabe nada y todo se intenta como siempre.
public struct TVContract: Sendable, Equatable {
    public var api: Int?
    public var capabilities: Set<String>?

    public init(api: Int? = nil, capabilities: Set<String>? = nil) { self.api = api; self.capabilities = capabilities }

    /// Una TV de antes (o que aún no contesta).
    public static let unknown = TVContract()

    /// El número de contrato que entiende este iPhone (el de `API_VERSION` en `orbital/companion.py` el día que se escribió esta
    /// app). Una TV con uno mayor es más nueva que el iPhone: lo que falte es porque el iPhone quedó atrás.
    public static let supportedAPI = 1

    /// ¿Esta TV habla un contrato más nuevo que el que entiende este iPhone?
    public var isNewerThanThisPhone: Bool { (api ?? 0) > Self.supportedAPI }

    /// Qué decir cuando falta algo: si la TV es más nueva, quien debe actualizarse es el iPhone (antes siempre se culpaba a la TV).
    public var missingLine: String { isNewerThanThisPhone ? OrbitalRemote.phoneUpdateLine : OrbitalRemote.updateLine }

    /// ¿Esta TV ya dice qué sabe hacer?
    public var isKnown: Bool { api != nil && capabilities != nil }

    /// ¿La TV sabe hacer `capability`? Sin anuncio (TV de antes) se supone que sí: se intenta y su respuesta manda.
    public func supports(_ capability: String) -> Bool {
        guard isKnown, let capabilities else { return true }
        return capabilities.contains(capability)
    }

    static func parse(_ json: JSON?) -> TVContract {
        guard let api = json?["api"]?.intValue else { return .unknown }
        return TVContract(api: api, capabilities: Set((json?["capabilities"]?.array ?? []).compactMap(\.nonEmptyString)))
    }

    /// La capacidad que cubre una ruta del iPhone (sin la barra inicial). nil: la ruta no depende de una capacidad (`api/ping`,
    /// `api/companion`, emparejar).
    public static func capability(for path: String) -> String? {
        let path = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if let exact = exact[path] { return exact }
        for (prefix, capability) in prefixes where path.hasPrefix(prefix) { return capability }
        return nil
    }

    private static let exact: [String: String] = [
        "api/stremio/play": "play_on_tv", "api/voice": "voice", "api/voice/hints": "voice_hints",
        "api/companion/now": "now_playing", "api/companion/input": "remote_input", "api/companion/text": "remote_text",
        "api/companion/player": "player_control", "api/companion/game": "game_control", "api/companion/console": "console_state",
        "api/companion/choices": "choices_sync", "api/companion/resume": "resume_sync", "api/companion/inbox/ack": "inbox",
        "api/devices": "device_keys", "api/devices/invite": "device_invite", "api/realdebrid": "realdebrid_share",
        "api/realdebrid/requests": "realdebrid_requests", "api/opensubtitles": "opensubtitles_share", "api/addons": "addons",
    ]
    /// En orden: lo más largo primero.
    private static let prefixes: [(String, String)] = [
        ("api/devices/upgrade", "device_upgrade"), ("api/devices/", "device_keys"), ("api/foryou", "foryou"), ("api/art/", "art"),
    ]
}

/// Lo último que anunció cada TV (por su dirección), mientras la app está abierta. Se renueva en cada `check()` y `keys()`.
public final class TVContractBook: @unchecked Sendable {
    public static let shared = TVContractBook()
    private let lock = NSLock()
    private var byBase: [String: TVContract] = [:]
    public init() {}

    public func contract(for base: URL?) -> TVContract {
        guard let base else { return .unknown }
        return lock.withLock { byBase[base.absoluteString] ?? .unknown }
    }

    func record(_ contract: TVContract, for base: URL?) {
        guard let base else { return }
        lock.withLock { byBase[base.absoluteString] = contract }
    }
}

extension OrbitalRemote {
    /// ¿Contesta y acepta el token? De paso guarda qué dice saber hacer (F1); una TV de antes no lo dice.
    @discardableResult
    public func check() async throws -> TVContract {
        let contract = TVContract.parse(try await send("api/ping", method: "GET", body: nil))
        contracts.record(contract, for: base)
        return contract
    }

    /// Lo último que anunció esta TV (`.unknown` si es de antes o aún no contesta).
    public var contract: TVContract { contracts.contract(for: base) }

    /// ¿La TV conectada sabe hacer esto? Con una TV de antes, sí (se intenta como siempre).
    public func supports(_ capability: String) -> Bool { contract.supports(capability) }

    /// Lo que se dice cuando la TV no anuncia (o no tiene) lo que se pidió y la TV es la vieja.
    public static let updateLine = "Tu Orbital de la tele necesita actualizarse para esto."
    /// Lo mismo cuando la TV es más nueva que este iPhone (su contrato `api` es mayor que `TVContract.supportedAPI`).
    public static let phoneUpdateLine = "Actualiza Orbital en este iPhone para usar esto."

    /// ¿Es uno de los dos avisos de «falta actualizar» (quien llama lo toma como «esta TV no lo tiene»)?
    public static func isUpdateLine(_ line: String) -> Bool { line == updateLine || line == phoneUpdateLine }

    /// Las rutas del control completo: sin ellas el pad se esconde (`Failure.outdated`).
    static let padPaths: Set<String> = ["api/companion/input", "api/companion/text", "api/voice/hints"]
}
