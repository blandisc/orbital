import Foundation
import OrbitalCore
import OrbitalAddons

/// CX5, CX7-A, CX8-A y TEC-30: el nombre de este aparato al conectar, quién puede quitar a quién, «Darle su propia conexión» y
/// «Tu TV es nueva». Solo el iPhone habla con tu TV (CX1-B, PA5-A): todo esto se apaga con `capabilities.console`. La
/// invitación de tu iPhone para tu iPad (CX4-A) se quitó el 23 nov 2026 (PA5-A: el iPad no se conecta a la TV).
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
}
