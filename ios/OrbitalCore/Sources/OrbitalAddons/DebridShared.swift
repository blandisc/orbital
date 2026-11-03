import Foundation
import CryptoKit

/// CX2-A · tu clave de Real-Debrid entre tus aparatos Apple. Cada aparato usa SU clave (la del llavero de este aparato) y
/// deja una copia en el llavero de iCloud (si lo usas). Nada cambia solo: si la copia compartida es de otra cuenta, se
/// pregunta («Tu iPad cambió la clave de Real-Debrid · Usar la nueva / Seguir con la de este iPhone»); si es la misma cuenta,
/// se queda la que funciona. Se compara la cuenta (`GET /user`), nunca las últimas letras.
public struct SharedDebridKey: Codable, Equatable, Sendable, CustomStringConvertible {
    /// La clave; vacía si es la marca de «Quitar de todos tus aparatos Apple».
    public var key: String
    /// Qué aparato la puso: «iphone», «ipad» o «mac» (para no prometer «tu iPhone» si vino del iPad, UX-19).
    public var from: String
    /// Con «De todos tus aparatos Apple»: la huella (SHA-256) de la clave quitada; los aparatos que la usaban la quitan.
    public var removed: String?

    public init(key: String, from: String, removed: String? = nil) { self.key = key; self.from = from; self.removed = removed }
    public var description: String { "sharedDebridKey(from: \(from), key: •••, removed: \(removed != nil))" }

    static func decode(_ raw: String?) -> SharedDebridKey? {
        guard let raw, !raw.isEmpty else { return nil }
        if let data = raw.data(using: .utf8), let parsed = try? JSONDecoder().decode(SharedDebridKey.self, from: data) { return parsed }
        return raw.contains("{") ? nil : SharedDebridKey(key: raw, from: "")
    }

    public var encoded: String { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }

    static func fingerprint(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Lo que este aparato tiene que decir de la copia compartida.
public enum SharedDebrid: Equatable, Sendable {
    case none
    /// Sin clave aquí, y tus aparatos Apple tienen una que sirve: «Usar la clave de tus aparatos Apple» (junto a «Pega tu
    /// clave», nunca en su lugar). `from` es quién la puso.
    case offer(from: String, account: DebridStatus)
    /// La compartida es de otra cuenta que la de aquí: se pregunta.
    case differs(from: String, shared: DebridStatus, local: DebridStatus?)
    /// La de aquí ya no servía y la compartida es de la misma cuenta: se tomó sin preguntar (UX-10).
    case adopted(from: String)
    /// Otro aparato eligió «De todos tus aparatos Apple» y aquí se usaba esa misma clave: se quitó.
    case removedEverywhere(from: String)
}

extension DebridAccount {
    /// La copia compartida (nil si no hay o si el llavero de iCloud todavía no la trae).
    public nonisolated var sharedKey: SharedDebridKey? { SharedDebridKey.decode(vaultRef.secret(AddonKeys.sharedRealDebridToken)) }

    nonisolated func publishShared(_ key: String) {
        guard !key.isEmpty else { return }
        _ = vaultRef.storeSecret(AddonKeys.sharedRealDebridToken, SharedDebridKey(key: key, from: platform).encoded)
    }

    nonisolated func retireShared(_ key: String) {
        guard let shared = sharedKey else { return }
        let mark = SharedDebridKey(key: "", from: platform, removed: SharedDebridKey.fingerprint(shared.key.isEmpty ? key : shared.key))
        _ = vaultRef.storeSecret(AddonKeys.sharedRealDebridToken, mark.encoded)
        markSharedSeen(mark.encoded)
    }

    nonisolated func markSharedSeen(_ value: String) { _ = vaultRef.storeSecret(AddonKeys.sharedRealDebridSeen, value) }
    nonisolated var sharedSeen: String? { vaultRef.secret(AddonKeys.sharedRealDebridSeen) }

    static func sameAccount(_ a: DebridStatus?, _ b: DebridStatus) -> Bool {
        guard let a else { return false }
        if let x = a.userID, let y = b.userID { return x == y }
        return !a.username.isEmpty && a.username == b.username
    }

    /// Al abrir la app, al volver a ella y al abrir tu cuenta (TEC-6: lo de iCloud puede llegar en cualquier momento).
    public func checkShared() async -> SharedDebrid {
        let local = vaultRef.secret(AddonKeys.realDebridToken) ?? ""
        guard let shared = sharedKey else {
            // Lo de antes de CX2-A (migración): la clave de este aparato se queda y, además, se deja la copia compartida.
            if !local.isEmpty { publishShared(local) }
            return .none
        }
        if let removed = shared.removed {
            guard !local.isEmpty, SharedDebridKey.fingerprint(local) == removed, sharedSeen != shared.encoded else { return .none }
            remove()
            markSharedSeen(shared.encoded)
            return .removedEverywhere(from: shared.from)
        }
        if local == shared.key { markSharedSeen(shared.key); return .none }
        if !local.isEmpty, sharedSeen == shared.key { return .none }
        guard let theirs = try? await provider.status(token: shared.key) else { return .none }   // no sirve o no contestó: nada que ofrecer
        guard !local.isEmpty else { return theirs.isPremium ? .offer(from: shared.from, account: theirs) : .none }
        switch await checkNow() {
        case .status(let mine):
            if Self.sameAccount(mine, theirs) { markSharedSeen(shared.key); return .none }   // la misma cuenta y las dos sirven
            return .differs(from: shared.from, shared: theirs, local: mine)
        case .invalidToken:
            if Self.sameAccount(saved, theirs) {
                save(token: shared.key, status: theirs, share: false)
                return .adopted(from: shared.from)
            }
            return .differs(from: shared.from, shared: theirs, local: nil)
        case .unreachable, .noKey: return .none
        }
    }

    /// «Usar la nueva» / «Usar la clave de tus aparatos Apple»: se comprueba y se guarda en este aparato.
    public func useShared() async throws -> DebridStatus {
        guard let shared = sharedKey, !shared.key.isEmpty else { throw DebridError.unexpected }
        let status = try await provider.status(token: shared.key)
        guard save(token: shared.key, status: status, share: false) else { throw DebridError.unexpected }
        return status
    }

    /// «Seguir con la de este iPhone»: no se vuelve a preguntar por esta copia.
    public nonisolated func keepLocal() {
        if let shared = sharedKey { markSharedSeen(shared.key.isEmpty ? shared.encoded : shared.key) }
    }
}
