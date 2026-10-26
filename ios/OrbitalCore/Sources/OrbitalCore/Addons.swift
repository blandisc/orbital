import Foundation

/// Complementos de Stremio: el protocolo, sin depender de la app ni de la cuenta.
///
///     GET {base}/manifest.json                  -> nombre, recursos, tipos, idPrefixes, catálogos
///     GET {base}/catalog/{tipo}/{id}.json       -> {"metas": [...]}
///     GET {base}/meta/{tipo}/{id}.json          -> {"meta": {...}}
///     GET {base}/stream/{tipo}/{video}.json     -> {"streams": [...]}
///     GET {base}/subtitles/{tipo}/{video}.json  -> {"subtitles": [...]}
public enum AddonResource { public static let all = ["catalog", "meta", "stream", "subtitles"] }

public struct AddonRule: Sendable, Equatable {
    public var types: [String]           // vacío = cualquier tipo
    public var idPrefixes: [String]?     // nil = cualquier id
}

public struct Addon: Sendable, Equatable {
    public var name: String
    public var url: String               // transportUrl: …/manifest.json
    public var rules: [String: AddonRule]
    public var catalogs: [JSON]

    public var base: String {
        if let range = url.range(of: "/manifest.json", options: .backwards) { return String(url[..<range.lowerBound]) }
        return url
    }

    public func handles(_ resource: String, kind: String, itemID: String? = nil) -> Bool {
        guard let rule = rules[resource] else { return false }
        if !rule.types.isEmpty && !rule.types.contains(kind) { return false }
        guard let itemID, let prefixes = rule.idPrefixes else { return true }
        return prefixes.contains { itemID.hasPrefix($0) }
    }
}

public enum Addons {
    /// La URL del manifiesto tal como la pegarías: con o sin `/manifest.json`, o el enlace `stremio://` de «Instalar».
    /// Solo http(s): un complemento no puede apuntar a un archivo local.
    public static func manifestURL(_ input: String) -> String? {
        var url = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.lowercased().hasPrefix("stremio://") { url = "https://" + url.dropFirst("stremio://".count) }
        let lower = url.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        if url.hasSuffix("/manifest.json") { return url }
        while url.hasSuffix("/") { url.removeLast() }
        return url + "/manifest.json"
    }

    /// Las URLs de tus complementos, normalizadas y sin repetir (lo que no es una URL se ignora).
    public static func cleanURLs(_ values: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for value in values {
            if let url = manifestURL(value), seen.insert(url).inserted { out.append(url) }
        }
        return out
    }

    private static func texts(_ value: JSON?) -> [String] { (value?.array ?? []).compactMap(\.nonEmptyString) }

    /// Un complemento a partir de su manifiesto; nil si no sirve (manifiesto raro, sin recursos que usemos, URL no http).
    public static func parseManifest(_ manifest: JSON?, url: String?) -> Addon? {
        guard let manifest, manifest.object != nil, let url, url.hasPrefix("http://") || url.hasPrefix("https://") else { return nil }
        let types = texts(manifest["types"])
        let prefixes: [String]? = { let p = texts(manifest["idPrefixes"]); return p.isEmpty ? nil : p }()
        var rules: [String: AddonRule] = [:]
        for resource in manifest["resources"]?.array ?? [] {
            // Un recurso es un nombre o {"name", "types", "idPrefixes"} con reglas propias.
            let name: String, own: JSON?
            if let s = resource.string { name = s; own = nil }
            else if let s = resource["name"]?.string { name = s; own = resource }
            else { continue }
            guard AddonResource.all.contains(name) else { continue }
            let ownTypes = texts(own?["types"]), ownPrefixes = texts(own?["idPrefixes"])
            rules[name] = AddonRule(types: ownTypes.isEmpty ? types : ownTypes, idPrefixes: ownPrefixes.isEmpty ? prefixes : ownPrefixes)
        }
        guard !rules.isEmpty else { return nil }
        let name = manifest["name"]?.string.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "Addon"
        let catalogs = (manifest["catalogs"]?.array ?? []).filter { $0.object != nil }
        return Addon(name: name, url: url, rules: rules, catalogs: catalogs)
    }
}

/// Tus complementos, en orden: primero los de tu cuenta de Stremio, luego los tuyos. La lista se recuerda
/// unos minutos (y solo unos segundos si algo no respondió) y se rearma si cambia la cuenta o los tuyos.
public actor AddonRegistry {
    public static let cacheSeconds: TimeInterval = 600
    public static let retryFailed: TimeInterval = 15

    private let http: HTTPClient
    private let account: StremioAPI?
    private let auth: @Sendable () -> String?
    private let own: @Sendable () -> [String]
    private let clock: @Sendable () -> Date
    private var cache: (expires: Date, key: [String], addons: [Addon])?
    /// La que ya se está pidiendo (la ficha y el reproductor la piden a la vez: una sola `addonCollectionGet`).
    private var loading: (key: [String], task: Task<[Addon], Error>)?
    /// Dónde se guarda la última lista buena (stale-while-revalidate): al abrir se usa al instante y se pide la nueva aparte.
    private let disk: URL?

    public init(http: HTTPClient, account: StremioAPI?, auth: @escaping @Sendable () -> String? = { nil },
                own: @escaping @Sendable () -> [String] = { [] }, disk: URL? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http; self.account = account; self.auth = auth; self.own = own; self.disk = disk; self.clock = clock
    }

    private func key() -> [String] { [auth() ?? ""] + Addons.cleanURLs(own()) }

    /// Sin cuenta que responda y sin complementos propios, lanza el error de la cuenta.
    public func addons() async throws -> [Addon] {
        let key = key()
        if let cache, cache.key == key, clock() < cache.expires { return cache.addons }
        if cache?.key != key, let saved = readDisk(key) {
            cache = (clock().addingTimeInterval(Self.retryFailed), key, saved)
            Task { _ = try? await self.load(key) }
            return saved
        }
        return try await load(key)
    }

    private func load(_ key: [String]) async throws -> [Addon] {
        if let loading, loading.key == key { return try await loading.task.value }
        let task = Task { try await self.fetch(key) }
        loading = (key, task)
        defer { if loading?.key == key { loading = nil } }
        return try await task.value
    }

    private func fetch(_ key: [String]) async throws -> [Addon] {
        var (entries, failed, error) = await fromAccount(key.first)
        var found = entries.compactMap { Addons.parseManifest($0["manifest"], url: $0["transportUrl"]?.string) }
        for url in key.dropFirst() where !found.contains(where: { $0.url == url }) {
            guard let target = URL(string: url) else { continue }
            do {
                let manifest = try await http.getJSON(target)
                if let addon = Addons.parseManifest(manifest, url: url) { found.append(addon); entries.append(["manifest": manifest ?? .null, "transportUrl": .string(url)]) }
            } catch { failed = true }
        }
        if let error, found.isEmpty { throw error }
        // Si algo no respondió (Wi‑Fi al despertar), la lista se recuerda solo unos segundos.
        let lifetime = failed ? Self.retryFailed : Self.cacheSeconds
        cache = (clock().addingTimeInterval(lifetime), key, found)
        if !failed { writeDisk(key, entries) }
        return found
    }

    private func fromAccount(_ authKey: String?) async -> ([JSON], Bool, Error?) {
        guard let authKey, !authKey.isEmpty, let account else { return ([], false, nil) }
        do {
            let result = try await account.addonCollection(authKey: authKey)
            return (result["addons"]?.array ?? [], false, nil)
        } catch { return ([], true, error) }
    }

    /// Un archivo por cuenta y lista propia (el nombre es un hash: la clave de la sesión no queda escrita).
    private func diskFile(_ key: [String]) -> URL? {
        disk?.appendingPathComponent("addons-" + SHA1.hex(Array(key.joined(separator: "\n").utf8)) + ".json")
    }

    private func readDisk(_ key: [String]) -> [Addon]? {
        guard let file = diskFile(key), let data = try? Data(contentsOf: file), let entries = JSON.parse(data)?.array else { return nil }
        let found = entries.compactMap { Addons.parseManifest($0["manifest"], url: $0["transportUrl"]?.string) }
        return found.isEmpty ? nil : found
    }

    private func writeDisk(_ key: [String], _ entries: [JSON]) {
        guard let disk, let file = diskFile(key) else { return }
        try? FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
        try? JSON.array(entries).serialized().write(to: file, options: .atomic)
    }

    public func serving(_ resource: String, kind: String, itemID: String? = nil) async throws -> [Addon] {
        try await addons().filter { $0.handles(resource, kind: kind, itemID: itemID) }
    }

    public func invalidate() {
        cache = nil; loading = nil
        if let disk { try? FileManager.default.removeItem(at: disk) }
    }
}
