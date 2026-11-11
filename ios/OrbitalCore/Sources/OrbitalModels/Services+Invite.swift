import Foundation
import OrbitalCore
import OrbitalAddons

/// CX4-A, CX5, CX7-A, CX8-A y TEC-30: el nombre de este aparato al conectar, la invitación de tu iPhone para tu iPad, quién
/// puede quitar a quién, «Darle su propia conexión» y «Tu TV es nueva». La Mac nunca habla con tu TV (CX1-B): todo esto se
/// apaga con `capabilities.console`.
extension Services {
    nonisolated static let deviceNameKey = "orbital.device-name"
    static let tvNameKey = "orbital.tv-name"

    // MARK: CX7-A · el nombre de este aparato

    /// Lo que se ofrece en «¿Cómo se llama este aparato?»: el que ya escribiste; si no, «iPhone de <tu nombre>» (Ajustes ›
    /// Tu perfil, o tu Trakt); si no, «iPhone» o «iPad».
    public func suggestedDeviceName(traktName: String? = nil) -> String {
        if let saved = kv.data(Self.deviceNameKey).flatMap({ String(data: $0, encoding: .utf8) }), !saved.isEmpty { return saved }
        let kind = platform == "ipad" ? "iPad" : platform == "mac" ? "Mac" : "iPhone"
        let person = [appSettings.displayName, traktName ?? ""].map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        guard let person else {
            let own = device?.name.trimmingCharacters(in: .whitespaces) ?? ""   // el que da iOS (con el permiso del nombre, el real)
            return own.isEmpty ? kind : String(own.prefix(Self.deviceNameLimit))
        }
        let first = person.split(separator: " ").first.map(String.init) ?? person
        return String("\(kind) de \(first)".prefix(Self.deviceNameLimit))
    }
    public static let deviceNameLimit = 60

    /// Guarda el nombre que se usará (≤ 60, sin espacios de sobra) y lo devuelve; vacío: la sugerencia.
    @discardableResult
    func rememberDeviceName(_ name: String?) -> String {
        let clean = String((name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.deviceNameLimit))
        guard !clean.isEmpty else { return suggestedDeviceName() }
        kv.set(Self.deviceNameKey, data: Data(clean.utf8))
        return clean
    }

    /// Cómo se llama tu TV (lo dijo al emparejar); si no se sabe, su dirección.
    public var tvName: String {
        if let saved = kv.data(Self.tvNameKey).flatMap({ String(data: $0, encoding: .utf8) }), !saved.isEmpty { return saved }
        return orbital.base?.host ?? ""
    }

    // MARK: TEC-30 · «Tu TV es nueva»

    func noteTVID(_ id: String) {
        guard !id.isEmpty else { return }
        guard let known = secrets.get(SecretKey.orbitalTVID), !known.isEmpty else { secrets.set(SecretKey.orbitalTVID, id); return }
        if known != id { orbitalAuth.report(.unknownTV) }
    }

    /// La frase de arriba de Tu Orbital: qué pasó, en palabras.
    public enum RescanReason: Equatable, Sendable { case removed, newTV, needsOwnConnection }
    public var rescanReason: RescanReason? {
        guard orbitalNeedsRescan else { return nil }
        switch orbitalAuth.problem {
        case .removed?: return .removed
        case .unknownTV?: return .newTV
        default: return .needsOwnConnection
        }
    }

    // MARK: CX5 · quién puede quitar a quién

    /// El iPhone quita a cualquiera; los demás aparatos, solo a sí mismos (la TV, a todos, desde su pantalla).
    public func canRemove(_ device: OrbitalPairedDevice) -> Bool { device.isThis || platform == "iphone" }

    // MARK: CX8-A · «Darle su propia conexión»

    /// Entró con el QR de antes (el token) y la TV ya da una conexión a cada aparato: se ofrece sin volver a escanear.
    public var canUpgradeConnection: Bool {
        capabilities.console && orbitalOn && tvPairing >= 2 && !orbital.hasDeviceKey && orbitalAuth.problem == nil
            && !(secrets.get(SecretKey.orbitalToken) ?? "").isEmpty
    }

    /// El sí de la TV: se guarda la llave, se borra el token y se conecta como siempre.
    func finishUpgrade(_ paired: OrbitalPairResult) async throws {
        try adopt(paired)
        try await connectOrbital(address: nil, token: nil)
    }

    // MARK: CX4-A · la invitación de tu iPhone para tu iPad

    /// La invitación que llegó por el llavero de iCloud (vencida o no): solo en un iPad que todavía no está conectado.
    public var pendingInvite: OrbitalInvite? {
        guard capabilities.console, platform == "ipad", !hasOrbitalDeviceKey else { return nil }
        return OrbitalInvite.decode(secrets.get(SecretKey.orbitalInvite))
    }

    static let inviteShownKey = "orbital.invite-shown"

    /// IOS-10 · al abrir la app en el iPad con una invitación vigente: true una sola vez por invitación (la app abre Ajustes,
    /// donde la tarjeta va primero). Así «La invitación sale al abrir Orbital en el iPad» es verdad.
    public func takeInviteToShow() -> Bool {
        guard let invite = pendingInvite, invite.isValid(at: now()) else { return false }
        let mark = Data(String(invite.expires.timeIntervalSince1970).utf8)
        guard kv.data(Self.inviteShownKey) != mark else { return false }
        kv.set(Self.inviteShownKey, data: mark)
        return true
    }

    /// «Conectar tu iPad» solo en un iPhone conectado con su propia conexión.
    public var canInviteIPad: Bool { platform == "iphone" && canShareKeysWithTV }

    /// La invitación que dejó este iPhone (si sigue).
    public var myInvite: OrbitalInvite? { platform == "iphone" ? OrbitalInvite.decode(secrets.get(SecretKey.orbitalInvite)) : nil }

    /// Pide a la TV una invitación (7 días, un aparato) y la deja en el llavero de iCloud para tu iPad.
    @discardableResult
    public func inviteIPad() async throws -> OrbitalInvite {
        guard canInviteIPad, let base = orbital.base else { throw OrbitalRemote.Failure.notConfigured }
        let got = try await orbital.invite(platform: "ipad")
        let invite = OrbitalInvite(code: got.code, expires: got.expires, address: base.absoluteString, tvName: tvName,
                                   tvID: secrets.get(SecretKey.orbitalTVID) ?? "", from: suggestedDeviceName())
        guard secrets.store(SecretKey.orbitalInvite, invite.encoded) else { throw OrbitalRemote.Failure.refused(Self.keychainLine) }
        changed()
        return invite
    }

    /// TEC-16 · al abrir: si la invitación de este iPhone va por la mitad (o venció), se renueva sola.
    public func renewInviteIfNeeded() async {
        guard let mine = myInvite, mine.needsRenewal(at: now()), canInviteIPad else { return }
        _ = try? await inviteIPad()
    }

    /// «Conectar» en el iPad: se canjea la invitación con su propio nombre; ya usada, se borra de iCloud (sirve para uno).
    public func acceptInvite(name: String?) async throws {
        guard let invite = pendingInvite else { throw OrbitalRemote.Failure.notConfigured }
        guard invite.isValid(at: now()) else { throw OrbitalRemote.Failure.refused(Self.inviteExpiredLine) }
        do { try await pairOrbital(address: invite.address, code: invite.code, name: name) }
        catch OrbitalRemote.Failure.refused(let why) where why == "Este código ya no sirve" { throw OrbitalRemote.Failure.refused(Self.inviteExpiredLine) }
        secrets.set(SecretKey.orbitalInvite, nil)
        changed()
    }
    public static let inviteExpiredLine = "Esta invitación ya no sirve. Abre Orbital en tu iPhone o escanea el código de tu TV."
}
