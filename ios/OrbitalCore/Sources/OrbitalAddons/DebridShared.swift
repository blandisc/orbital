import Foundation
import CryptoKit

/// CX2-A · tu clave de tu nube entre tus aparatos Apple (Real-Debrid y, desde el 21 nov 2026, también TorBox o AllDebrid:
/// Fernando, «que la que yo usé en mi iPhone se sincronice vía iCloud con Mac y iPad»). Cada aparato usa SU clave (la del llavero de este aparato) y
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
    /// IOS-11 · el nombre del aparato que la puso («iPad de Fernando»); nil en una copia de antes.
    public var name: String?
    /// De qué nube es («torbox»); nil en una copia de antes (era de Real-Debrid).
    public var service: String?
    public var cloud: DebridService { service.flatMap { DebridService(rawValue: $0) } ?? .realDebrid }
    /// Cuándo la pusiste (segundos desde 1970); nil en una copia de antes del 22 nov 2026: no se sabe si es la más reciente.
    public var at: Double?

    public init(key: String, from: String, removed: String? = nil, name: String? = nil, service: DebridService = .realDebrid, at: Date? = nil) {
        self.key = key; self.from = from; self.removed = removed; self.name = name
        self.service = service == .realDebrid ? nil : service.rawValue
        self.at = at?.timeIntervalSince1970
    }
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
    /// clave», nunca en su lugar). `from` es quién la puso: su nombre («iPad de Fernando») o, en una copia de antes, su tipo.
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

    nonisolated func publishShared(_ key: String, service cloud: DebridService) {
        guard !key.isEmpty else { return }
        _ = vaultRef.storeSecret(AddonKeys.sharedRealDebridToken, SharedDebridKey(key: key, from: platform, name: deviceName(), service: cloud, at: clock()).encoded)
    }

    nonisolated func retireShared(_ key: String) {
        guard let shared = sharedKey else { return }
        let mark = SharedDebridKey(key: "", from: platform, removed: SharedDebridKey.fingerprint(shared.key.isEmpty ? key : shared.key), name: deviceName(),
                                   service: shared.key.isEmpty ? service : shared.cloud)   // la marca dice de qué nube es la clave quitada
        _ = vaultRef.storeSecret(AddonKeys.sharedRealDebridToken, mark.encoded)
        markSharedSeen(mark.encoded)
    }

    nonisolated func markSharedSeen(_ value: String) { _ = vaultRef.storeSecret(AddonKeys.sharedRealDebridSeen, value) }
    nonisolated var sharedSeen: String? { vaultRef.secret(AddonKeys.sharedRealDebridSeen) }

    /// La cuenta de aquí ya no da enlaces: venció o es gratuita.
    static func stopped(_ status: DebridStatus, now: Date) -> Bool {
        switch status.state(now: now) { case .expired, .free: true; case .active, .expiringSoon: false }
    }

    /// Cuándo se puso la clave de este aparato (pegada aquí o tomada de tus aparatos); nil si es de antes del 22 nov 2026.
    nonisolated var savedAt: Double? { vaultRef.data(AddonKeys.debridSavedAt).flatMap { Double(String(decoding: $0, as: UTF8.self)) } }

    static func sameAccount(_ a: DebridStatus?, _ b: DebridStatus) -> Bool {
        guard let a else { return false }
        if let x = a.userID, let y = b.userID { return x == y }
        return !a.username.isEmpty && a.username == b.username
    }

    /// Al abrir la app, al volver a ella y al abrir tu cuenta (TEC-6: lo de iCloud puede llegar en cualquier momento).
    public func checkShared() async -> SharedDebrid {
        guard let shared = sharedKey else {
            // Lo de antes de CX2-A (migración): la clave de este aparato se queda y, además, se deja la copia compartida.
            if let mine = vaultRef.debridToken(service) { publishShared(mine, service: service) }
            return .none
        }
        // La copia es de la nube que la puso; aquí se compara con la clave de esa misma nube.
        let cloud = shared.cloud
        let local = vaultRef.debridToken(cloud) ?? ""
        if let removed = shared.removed {
            guard cloud == service, !local.isEmpty, SharedDebridKey.fingerprint(local) == removed, sharedSeen != shared.encoded else { return .none }
            remove()
            markSharedSeen(shared.encoded)
            return .removedEverywhere(from: shared.from)
        }
        // IOS-11: quién la puso, con su nombre si lo trae («iPad de Fernando»); si no, su tipo («ipad»).
        let who = shared.name.flatMap { $0.isEmpty ? nil : $0 } ?? shared.from
        // 22 nov 2026 (Fernando: «si yo cambio de clave en iPhone, automáticamente debería de cambiarse allá… no preguntar…
        // el default es el último que agregué en un aparato»): la clave más reciente de tus aparatos Apple es la que usan todos,
        // aunque la de aquí todavía sirva. La de antes queda en este aparato para «Volver a la clave anterior».
        if cloud == service, local == shared.key { markSharedSeen(shared.key); return .none }   // ya es la de aquí
        if sharedSeen == shared.key { return .none }   // aquí ya se decidió: volviste a la anterior o la quitaste solo de aquí
        // La de aquí se puso después que la copia (iCloud aún trae la de antes): se queda la de aquí.
        if let at = shared.at, let mine = savedAt, mine >= at { return .none }
        let current = vaultRef.debridToken(service)
        guard let theirs = try? await providers(cloud).status(token: shared.key) else { return .none }   // no sirve o no contestó: se queda la de aquí
        // 22 nov 2026 · una copia sin fecha es de antes (p. ej. tu Real-Debrid de hace semanas, si pusiste TorBox en una versión
        // que todavía no la compartía): no se sabe si es la más reciente. Si la de aquí funciona, se queda y se comparte con fecha
        // (así tus otros aparatos la toman); solo se toma la de antes si la de aquí ya no sirve y la de antes sí.
        if shared.at == nil, let current {
            switch await checkNow() {
            case .status(let mine) where !Self.stopped(mine, now: now()):
                publishShared(current, service: service)
                return .none
            case .unreachable, .noKey: return .none
            case .status, .invalidToken: guard theirs.isPremium else { return .none }
            }
        }
        let before = current.map { SharedDebridKey(key: $0, from: platform, service: service) }
        guard save(token: shared.key, status: theirs, share: false, service: cloud, savedAt: shared.at) else { return .none }
        if let before, before.key != shared.key || before.cloud != cloud { storePrevious(before) }
        return .adopted(from: who)
    }

    /// La clave que este aparato usaba antes de tomar la de tus aparatos Apple (solo de este aparato, nunca en iCloud).
    public nonisolated var previousKey: SharedDebridKey? {
        SharedDebridKey.decode(vaultRef.secret(AddonKeys.previousDebridToken)).flatMap { $0.key.isEmpty ? nil : $0 }
    }

    nonisolated func storePrevious(_ key: SharedDebridKey?) { _ = vaultRef.storeSecret(AddonKeys.previousDebridToken, key?.encoded) }

    /// «Volver a la clave anterior»: se comprueba, se usa aquí y la que se dejó queda como la anterior (se puede ir y volver).
    /// La copia de tus aparatos Apple no cambia y este aparato no la vuelve a tomar hasta que pongas otra en alguno.
    public func usePrevious() async throws -> DebridStatus {
        guard let previous = previousKey else { throw DebridError.unexpected }
        let status = try await providers(previous.cloud).status(token: previous.key)
        let current = vaultRef.debridToken(service).map { SharedDebridKey(key: $0, from: platform, service: service) }
        guard save(token: previous.key, status: status, share: false, service: previous.cloud) else { throw DebridError.unexpected }
        if let shared = sharedKey, !shared.key.isEmpty { markSharedSeen(shared.key) }
        storePrevious(current)
        return status
    }

    /// «Usar la nueva» / «Usar la clave de tus aparatos Apple»: se comprueba y se guarda en este aparato.
    public func useShared() async throws -> DebridStatus {
        guard let shared = sharedKey, !shared.key.isEmpty else { throw DebridError.unexpected }
        // La copia dice de qué nube es: se prueba contra esa y esa queda como la tuya.
        let status = try await providers(shared.cloud).status(token: shared.key)
        guard save(token: shared.key, status: status, share: false, service: shared.cloud) else { throw DebridError.unexpected }
        return status
    }

    /// «Seguir con la de este iPhone»: no se vuelve a preguntar por esta copia.
    public nonisolated func keepLocal() {
        if let shared = sharedKey { markSharedSeen(shared.key.isEmpty ? shared.encoded : shared.key) }
    }
}
