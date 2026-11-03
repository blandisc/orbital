import Foundation

/// La libreta de pedidos de este aparato (R12): sobrevive a reiniciar la app y nunca olvida uno que sigue en camino. Lo
/// terminado (listo, rechazado, demasiadas descargas o la lápida) se olvida 7 días después de su último cambio, como en la
/// TV; lo de otra cuenta, también aunque siga en camino (nadie aquí lo puede seguir). Se guarda en los ajustes de la app
/// (no lleva claves ni enlaces de Real-Debrid: los enlaces van atados a quien los pidió).
public final class DebridRequestBook: @unchecked Sendable {
    public static let key = "debrid-requests"
    public static let forgetFinishedAfter: TimeInterval = 7 * 24 * 3600
    /// El tope del contrato (`limits.entries`): de más, se olvida primero lo terminado más viejo.
    public static let maxEntries = 200
    private let vault: AddonVault
    private let lock = NSLock()
    private var cached: [DebridRequest]?

    public init(vault: AddonVault) { self.vault = vault }

    /// Todos, con las lápidas, el más reciente primero (para juntar con la TV).
    public var stored: [DebridRequest] { lock.withLock { load() }.sorted { $0.createdAt > $1.createdAt } }
    /// Los que se enseñan (sin las lápidas), el más reciente primero.
    public var all: [DebridRequest] { stored.filter { $0.state != .gone } }
    /// Los que siguen en camino y se pueden seguir desde esta cuenta.
    public func active(account: String?) -> [DebridRequest] { all.filter { $0.state.isActive && !$0.isOther(account: account) } }
    public var active: [DebridRequest] { all.filter { $0.state.isActive } }

    /// Por huella, con lápida o no.
    public func find(hash: String) -> DebridRequest? { lock.withLock { load().first { $0.hash == hash.lowercased() } } }

    /// El pedido de un video en tu cuenta (el más reciente que no fue rechazado; si todos lo fueron, el último). Nunca una
    /// lápida ni uno de otra cuenta.
    public func find(metaID: String, videoID: String?, account: String? = nil) -> DebridRequest? {
        let mine = all.filter { $0.covers(metaID: metaID, videoID: videoID) && !$0.isOther(account: account) }
        return mine.first { $0.state != .refused } ?? mine.first
    }

    /// Anota o reemplaza (por huella).
    public func put(_ request: DebridRequest) {
        lock.withLock {
            var list = load()
            if let i = list.firstIndex(where: { $0.hash == request.hash }) { list[i] = request } else { list.append(request) }
            save(list)
        }
    }

    /// Junta una entrada que llega de la TV: con la guardada (`DebridRequest.merge`) o, si es nueva, tal cual pero sin avisar
    /// nada aquí (solo avisa el aparato que la pidió). Devuelve lo que quedó.
    ///
    /// R14-B · `watchReady` (el iPhone): una nueva que todavía va en camino queda sin avisar (`notified` false), para avisar
    /// cuando quede lista; una que ya llega lista se marca avisada en silencio (al conectar, lo de antes no suena).
    @discardableResult
    public func absorb(_ incoming: DebridRequest, watchReady: Bool = false) -> DebridRequest {
        lock.withLock {
            var list = load()
            let out: DebridRequest
            if let i = list.firstIndex(where: { $0.hash == incoming.hash }) {
                out = DebridRequest.merge(list[i], incoming)
                guard out != list[i] else { return out }
                list[i] = out
            } else {
                var fresh = incoming
                fresh.notified = !(watchReady && fresh.state.isActive); fresh.nudged = true; fresh.pending = false
                list.append(fresh); out = fresh
            }
            save(list)
            return out
        }
    }

    public func update(hash: String, _ change: (inout DebridRequest) -> Void) {
        lock.withLock {
            var list = load()
            guard let i = list.firstIndex(where: { $0.hash == hash.lowercased() }) else { return }
            change(&list[i])
            save(list)
        }
    }

    public func remove(hash: String) { lock.withLock { save(load().filter { $0.hash != hash.lowercased() }) } }

    /// Olvida lo terminado de hace más de una semana (lo que sigue en camino, nunca) y lo de otra cuenta sin cambios en una
    /// semana aunque siga en camino. Con más de `maxEntries`, lo terminado más viejo primero.
    public func prune(now: Date, account: String? = nil) {
        lock.withLock {
            let list = load()
            var kept = list.filter { entry in
                let old = now.timeIntervalSince(entry.updatedAt) >= Self.forgetFinishedAfter
                return !(old && (!entry.state.isActive || entry.isOther(account: account)))
            }
            if kept.count > Self.maxEntries {
                let finished = kept.filter { !$0.state.isActive }.sorted { $0.updatedAt < $1.updatedAt }
                let drop = Set(finished.prefix(kept.count - Self.maxEntries).map(\.hash))
                kept.removeAll { drop.contains($0.hash) }
            }
            if kept.count != list.count { save(kept) }
        }
    }

    private func load() -> [DebridRequest] {
        if let cached { return cached }
        let list = vault.data(Self.key).map(Self.decodeEach) ?? []
        cached = list
        return list
    }
    private func save(_ list: [DebridRequest]) {
        cached = list
        vault.setData(Self.key, try? Self.encoder.encode(list))
    }

    /// Cada entrada por separado: una mala se salta, no tira la lista (contrato, `GET /api/realdebrid/requests`).
    public static func decodeEach(_ data: Data) -> [DebridRequest] {
        (try? decoder.decode([Lenient].self, from: data))?.compactMap(\.value) ?? []
    }
    private struct Lenient: Decodable {
        let value: DebridRequest?
        init(from decoder: Decoder) throws { value = try? DebridRequest(from: decoder) }
    }

    /// La libreta de este aparato (con lo que nunca viaja).
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; e.outputFormatting = [.sortedKeys]
        e.userInfo[DebridRequest.localKey] = true
        return e
    }()
    /// Lo que viaja a la TV (sin `updated` ni lo de este aparato).
    public static let wireEncoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; e.outputFormatting = [.sortedKeys]; return e
    }()
    public static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()
}

/// Lo que contesta la TV en `GET /api/realdebrid/requests`: `{version: 1, account, requests: [entry]}`. `account` es la
/// cuenta de Real-Debrid de la TV (nil sin Real-Debrid).
public struct DebridRequestPull: Equatable, Sendable {
    public var version: Int
    public var account: String?
    public var requests: [DebridRequest]
    public init(version: Int = 1, account: String?, requests: [DebridRequest]) { self.version = version; self.account = account; self.requests = requests }

    /// Del cuerpo de la respuesta; cada entrada por separado (una mala se salta). nil si no tiene esa forma.
    public static func parse(_ data: Data) -> DebridRequestPull? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let rows = json["requests"] as? [Any] else { return nil }
        let account = (json["account"] as? String) ?? (json["account"] as? NSNumber)?.stringValue
        let list = (try? JSONSerialization.data(withJSONObject: rows)).map(DebridRequestBook.decodeEach) ?? []
        return DebridRequestPull(version: (json["version"] as? NSNumber)?.intValue ?? 1, account: account?.isEmpty == false ? account : nil, requests: list)
    }
}

/// Por donde la libreta se junta con la de la TV (contrato › `routes`): `GET /api/realdebrid/requests` para leer la suya y
/// `POST /api/realdebrid/requests` con la entrada completa (sin `updated` ni lo de este aparato) para anotar lo que pidió
/// o lo que cambió aquí. La TV junta por huella y nunca le pide nada a Real-Debrid. La implementación de verdad es
/// `OrbitalRemoteDebridRequestSync`; la app usa `NoDebridRequestSync` hasta que el corte S2 de la TV esté en main.
public protocol DebridRequestSync: Sendable {
    /// La libreta de la TV (nil si no hay TV, no contesta o no tiene esa ruta).
    func pull() async -> DebridRequestPull?
    /// Manda una entrada a la TV; devuelve la que quedó guardada allá (nil si no se pudo).
    func push(_ request: DebridRequest) async -> DebridRequest?
}

public struct NoDebridRequestSync: DebridRequestSync {
    public init() {}
    public func pull() async -> DebridRequestPull? { nil }
    public func push(_ request: DebridRequest) async -> DebridRequest? { nil }
}
