import Foundation
import OrbitalCore
import OrbitalAddons

/// K1 · qué dijo tu TV de la llave de este aparato: la pide (`device_key_required`) o lo quitó (`device_removed`). Cualquiera
/// de las dos enseña la frase tranquila «Vuelve a escanear el código de tu TV» con «Escanear». Si la TV lo quitó, la llave
/// se borra del llavero en ese momento (ya no sirve).
public final class OrbitalAuthState: @unchecked Sendable {
    private let lock = NSLock()
    private var current: OrbitalRemote.Failure?
    private let secrets: SecretsStore
    var onChange: (@Sendable () -> Void)?

    init(secrets: SecretsStore) { self.secrets = secrets }

    public var problem: OrbitalRemote.Failure? { lock.withLock { current } }

    func report(_ failure: OrbitalRemote.Failure) {
        // `unknownTV` (TEC-30): la llave se queda, para mandarla al volver a emparejar y que la TV reemplace el renglón.
        guard failure == .needsKey || failure == .removed || failure == .unknownTV else { return }
        if failure == .removed { secrets.set(SecretKey.orbitalDeviceKey, nil) }
        let changed = lock.withLock { () -> Bool in defer { current = failure }; return current != failure }
        if changed { onChange?() }
    }

    func clear() {
        let changed = lock.withLock { () -> Bool in defer { current = nil }; return current != nil }
        if changed { onChange?() }
    }
}

/// Lo que este aparato escribe en `enabled` de la lista de complementos compartida.
public struct AddonDevice: Equatable, Sendable {
    /// «iphone», «ipad» o «mac».
    public var platform: String
    /// El id que le dio la TV al emparejar (K1); nil sin llave.
    public var id: String?
    public init(platform: String, id: String? = nil) { self.platform = platform; self.id = id }
    /// La llave de `enabled` que este aparato escribe: su id con llave; sin ella, la plataforma (lo de antes de K1).
    public var key: String { id ?? platform }
}

extension Services {
    /// Tu Orbital con lo que haya: la llave de este aparato (K1) o el token del túnel. Apagada (o en la Mac), sin configurar.
    nonisolated static func makeOrbital(http: HTTPClient, settings: SettingsStore, secrets: SecretsStore, device: OrbitalRemote.Device?,
                                        allows: Bool, auth: OrbitalAuthState) -> OrbitalRemote {
        let on = allows && settings.value.orbitalEnabled
        var remote = OrbitalRemote(http: http, address: on ? settings.value.orbitalAddress : "", token: on ? secrets.get(SecretKey.orbitalToken) ?? "" : "",
                                   device: device, deviceKey: on ? secrets.get(SecretKey.orbitalDeviceKey) : nil)
        remote.authProblem = { auth.report($0) }
        return remote
    }

    /// El nombre y lo que aporta un complemento, de su manifiesto (para guardar uno de la TV con `?full=1`).
    nonisolated static func manifestReader(http: HTTPClient) -> @Sendable (String) async -> (name: String, resources: [String])? {
        { url in
            guard let target = URL(string: url), let json = try? await http.getJSON(target),
                  let addon = Addons.parseManifest(json, url: url) else { return nil }
            return (addon.name, addon.rules.keys.sorted())
        }
    }

    /// ¿Este aparato tiene su llave para tu Orbital?
    public var hasOrbitalDeviceKey: Bool { orbitalOn && orbital.hasDeviceKey }

    /// La frase «Vuelve a escanear el código de tu TV» con «Escanear»: la TV pidió la llave o quitó este aparato, o anuncia
    /// llaves por aparato (`pairing: 2`) y este solo tiene el token de antes.
    public var orbitalNeedsRescan: Bool {
        guard orbitalOn else { return false }
        if orbitalAuth.problem != nil { return true }
        return tvPairing >= 2 && !orbital.hasDeviceKey && !(secrets.get(SecretKey.orbitalToken) ?? "").isEmpty
    }

    /// «Pasar a la TV» y «Usar la de la TV» (K1): solo con llave y con una TV que reparte llaves. En Plus o sin TV, nunca.
    public var canShareKeysWithTV: Bool { hasOrbitalDeviceKey && tvPairing >= 2 && orbitalAuth.problem == nil }

    /// El QR v2: cambia el código por la llave de este aparato, la guarda en el llavero (solo de este aparato), borra el token
    /// del túnel y conecta como siempre. Lanza con el motivo en palabras («Este código ya no sirve»).
    /// `name` (CX7-A): el que escribiste al conectar; si no, el guardado o la sugerencia. Si este aparato ya tenía llave, va
    /// en `Authorization` para que la TV reemplace su renglón (TEC-32).
    @discardableResult
    public func pairOrbital(address: String, code: String, name: String? = nil) async throws -> String {
        guard allowsOrbital else { return "" }
        let open = OrbitalRemote(http: http, address: address, token: "", device: device)
        let name = rememberDeviceName(name)
        let old = secrets.get(SecretKey.orbitalDeviceKey)
        let paired = try await open.pair(code: code, name: name, platform: platform, replacing: old)
        try adopt(paired)
        try await connectOrbital(address: address, token: nil)
        return paired.tvName
    }

    /// La llave nueva al llavero (solo de este aparato); el token del túnel ya no le sirve (K1-13). Si el llavero no la acepta,
    /// no se borra nada (TEC-5).
    func adopt(_ paired: OrbitalPairResult) throws {
        guard secrets.store(SecretKey.orbitalDeviceKey, paired.key) else { throw OrbitalRemote.Failure.refused(Self.keychainLine) }
        secrets.set(SecretKey.orbitalToken, nil)
        secrets.set(SecretKey.orbitalTVID, paired.tvID.isEmpty ? nil : paired.tvID)   // la TV con que se acaba de emparejar
        if !paired.tvName.isEmpty { kv.set(Self.tvNameKey, data: Data(paired.tvName.utf8)) }
        orbitalAuth.clear()
    }
    static let keychainLine = "No pude guardar la conexión en este aparato. Inténtalo otra vez."

    /// Lo que leyó la cámara o el enlace que abrió la app, v1 o v2. Devuelve lo que se trajo de tu Orbital («TMDB», «Trakt»).
    @discardableResult
    public func pair(_ link: OrbitalPairing, name: String? = nil) async throws -> [String] {
        switch link {
        case .token(let address, let token):
            secrets.set(SecretKey.orbitalDeviceKey, nil)   // un código v1: la TV es de antes de las llaves
            orbitalAuth.clear()
            return try await connectOrbital(address: address, token: token)
        case .code(let address, let code):
            try await pairOrbital(address: address, code: code, name: name)
            return []
        }
    }

    /// Quitaste este aparato en Tu Orbital: se olvidan su llave y el token, y queda sin emparejar (la dirección se queda).
    public func forgetThisDevice() {
        secrets.set(SecretKey.orbitalDeviceKey, nil)
        secrets.set(SecretKey.orbitalToken, nil)
        orbitalAuth.clear()
        changed()
    }
}
