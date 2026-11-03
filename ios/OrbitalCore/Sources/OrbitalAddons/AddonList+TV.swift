import Foundation

/// Tu lista y la de tu TV, la misma (S1, S3, S6): qué complemento de aquí es cuál de allá, juntar lo que cambió en la TV y
/// armar lo que se le manda. Sin red: `AddonTVSync` (OrbitalModels) hace las peticiones.
///
/// - Cada aparato cambia solo su propio prendido (`enabled[device]`: su id con llave, K1; si no, su plataforma); se lee
///   `enabled[id] ?? enabled[plataforma] ?? lo de fábrica`. El de la TV nunca se manda.
/// - Torrentio viaja como opciones; cada lado arma su dirección con su clave.
/// - Lo traído de Stremio que la TV ya tiene viaja por su id, sin dirección; uno nuevo, con su dirección: sin llave por
///   aparato solo si no lleva clave (`AddonShare.canTravel`); con llave (K1), también con clave.
/// - Las direcciones de la TV llegan tapadas (sirven para reconocer uno que este iPhone ya tiene); con llave, `?full=1`
///   trae las completas de los que este iPhone no tiene.
public struct AddonTVMerge: Equatable, Sendable {
    /// Las opciones de Torrentio que cambiaron en los dos lados: se quedó la de la TV (S3).
    public var conflicts: [String] = []
    /// Tus opciones de antes de juntar, para «Usar la de este iPhone».
    public var mine: AddonOptions?
    /// Algo de la TV cambió tu lista aquí.
    public var changed = false
    public init() {}
}

public struct AddonTVPlan: Equatable, Sendable {
    /// El cuerpo del PUT: {base_revision, changed_at, changed_by, addons, removed}.
    public var body: StoredJSON
    /// Hay algo que la TV todavía no tiene. false = ya son iguales (no se manda nada).
    public var needsPut: Bool
    /// Los que se quedan en este iPhone porque su dirección lleva una clave.
    public var waitingForKeys: [String]
    /// Los de la TV que este iPhone no tiene ni puede usar (S5): se enseñan, no se guardan.
    public var tvOnly: [SharedAddon]
    public var links: [String: String]
}

extension AddonList {
    /// La entrada de la TV de cada complemento de aquí: `links` (lo ya acordado), la plantilla (lo que viene con Orbital) o
    /// la dirección tapada igual a la de aquí tapada.
    public func link(_ tv: SharedAddonList, links: [String: String]) -> [String: String] {
        var out = links
        let tvIDs = Set(tv.addons.map(\.id))
        for addon in installed where out[addon.id].map(tvIDs.contains) != true {
            if case .recommended(let template) = addon.origin {
                if let match = tv.addons.first(where: { $0.template == template }) { out[addon.id] = match.id }
            } else if let url = resolvedURL(addon) {
                let masked = AddonShare.tvMasked(url)
                if let match = tv.addons.first(where: { $0.origin == "stremio" && $0.url == masked }) { out[addon.id] = match.id }
            }
        }
        return out
    }

    /// Junta lo que cambió en la TV desde `base` (la última en que quedaron de acuerdo): las opciones de Torrentio una por una,
    /// lo que quitaste allá y el orden. Si los dos cambiaron lo mismo, gana la TV y se dice cuál (S3). Sin `base` (la primera
    /// vez), lo de aquí manda en el orden (S1: la TV toma tu lista) y en las opciones gana lo que no esté como vino.
    public func absorb(_ tv: SharedAddonList, base: SharedAddonList?, links: [String: String]) -> AddonTVMerge {
        var merge = AddonTVMerge()
        fromTV {
            mergeTorrentio(tv, base: base, into: &merge)
            let baseRemoved = Set(base?.removed ?? [])
            let gone = Set(tv.removed).subtracting(baseRemoved)
            for addon in installed where !addon.isBuiltIn {
                if let id = links[addon.id], gone.contains(id) { remove(addon.id); merge.changed = true }
            }
            if let base { mergeOrder(tv, base: base, links: links, into: &merge) }
        }
        return merge
    }

    private func mergeTorrentio(_ tv: SharedAddonList, base: SharedAddonList?, into merge: inout AddonTVMerge) {
        guard let mine = torrentio, let theirs = tv.addons.first(where: { $0.template == AddonCatalog.torrentio.id })?.options else { return }
        let local = AddonShare.canonical(mine.options ?? TorrentioConfig.recommended)
        let remote = AddonShare.canonical(AddonShare.options(theirs))
        let start = base?.addons.first(where: { $0.template == AddonCatalog.torrentio.id })?.options
        let before = AddonShare.canonical(start.map(AddonShare.options) ?? TorrentioConfig.recommended)
        guard local != remote else { return }
        var result = local
        for key in Set(local.keys).union(remote.keys) where local[key] != remote[key] {
            if local[key] == before[key] { result[key] = remote[key] }   // solo cambió en la TV
            else if remote[key] != before[key] { result[key] = remote[key]; merge.conflicts.append(key) }   // los dos: gana la TV
        }
        guard result != local else { return }
        merge.mine = mine.options
        var options = AddonShare.options(result)
        options.extra = mine.options?.extra ?? [:]
        setOptions(mine.id, options)
        merge.conflicts.sort()
        merge.changed = true
    }

    /// El orden: si solo cambió en la TV, se toma; si cambió en los dos, gana la TV. Los de aquí que la TV no tiene se quedan
    /// en su lugar.
    private func mergeOrder(_ tv: SharedAddonList, base: SharedAddonList, links: [String: String], into merge: inout AddonTVMerge) {
        let list = installed
        let common = Set(list.compactMap { links[$0.id] }).intersection(tv.addons.map(\.id)).intersection(base.addons.map(\.id))
        let local = list.compactMap { links[$0.id] }.filter(common.contains)
        let remote = tv.addons.map(\.id).filter(common.contains)
        let before = base.addons.map(\.id).filter(common.contains)
        guard local != remote, remote != before else { return }
        if local != before { merge.conflicts.append("order") }
        let slots = list.indices.filter { links[list[$0].id].map(common.contains) == true }
        let byShared = Dictionary(list.compactMap { a in links[a.id].map { ($0, a) } }, uniquingKeysWith: { a, _ in a })
        update { items in
            for (slot, shared) in zip(slots, remote) { if let addon = byShared[shared] { items[slot] = addon } }
        }
        merge.changed = true
    }

    /// Lo que se le manda a la TV desde `tv` (la última lista que dio): tu orden, tu prendido, tus opciones de Torrentio y lo
    /// que quitaste. `newID` da el id de uno nuevo (nunca un hash de su dirección: puede llevar clave).
    /// `device`: la llave de este aparato en `enabled` (nunca «tv»); `platform`: la de antes de K1, para leer; `deviceKey`:
    /// habla con su llave por aparato (lo que lleva clave también viaja).
    public func plan(for tv: SharedAddonList, links: [String: String], device: String, platform: String? = nil, deviceKey: Bool = false,
                     changedBy: String, now: Date, newID: () -> String = { UUID().uuidString.lowercased() }) -> AddonTVPlan {
        let device = device == "tv" ? (platform ?? "iphone") : device   // un aparato nunca escribe el prendido de la TV
        var links = link(tv, links: links)
        let byID = Dictionary(tv.addons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var items: [StoredJSON] = [], sent: [String] = [], waiting: [String] = []
        var differs = false
        for addon in installed {
            var entry: SharedAddon
            if case .recommended(let template) = addon.origin {
                // Lo que viene con Orbital solo viaja si la TV lo tiene (Comet lo tiene desde 41a18774; una TV vieja sin él, se queda aquí).
                guard let id = links[addon.id], byID[id] != nil else { continue }
                entry = SharedAddon(id: id, origin: "orbital", template: template, name: addon.name, order: items.count)
                if template == AddonCatalog.torrentio.id {
                    entry.options = AddonShare.wire(addon.options ?? TorrentioConfig.recommended)
                    let theirs = byID[id]?.options.map { AddonShare.canonical(AddonShare.options($0)) }
                    if theirs != AddonShare.canonical(addon.options ?? TorrentioConfig.recommended) { differs = true }
                }
            } else if let id = links[addon.id], byID[id] != nil {
                entry = SharedAddon(id: id, origin: "stremio", name: addon.name, order: items.count)   // sin dirección: no cambia
            } else if let url = resolvedURL(addon), AddonShare.canTravel(url, withDeviceKey: deviceKey) {
                let id = links[addon.id] ?? newID()
                links[addon.id] = id
                entry = SharedAddon(id: id, origin: "stremio", url: url, name: addon.name, order: items.count)
                differs = true
            } else {
                if resolvedURL(addon) != nil { waiting.append(addon.name) }
                continue
            }
            entry.enabled = [device: addon.enabled]
            if byID[entry.id]?.isEnabled(device: device, platform: platform) != addon.enabled { differs = true }
            items.append(entry.json)
            sent.append(entry.id)
        }
        let sentSet = Set(sent)
        if tv.addons.map(\.id).filter(sentSet.contains) != sent.filter({ byID[$0] != nil }) { differs = true }
        let removed = removedIDs.compactMap { links[$0] }.sorted()
        if !Set(removed).isSubset(of: tv.removed) { differs = true }
        let stamp = ISO8601DateFormatter().string(from: now)
        let body: StoredJSON = .object(["base_revision": .number(Double(tv.revision)), "changed_at": .string(stamp),
                                        "changed_by": .string(String(changedBy.prefix(60))), "addons": .array(items),
                                        "removed": .array(removed.map(StoredJSON.string))])
        let mine = Set(links.values)
        let tvOnly = tv.addons.filter { !mine.contains($0.id) && $0.origin == "stremio" }
        return AddonTVPlan(body: body, needsPut: differs, waitingForKeys: waiting, tvOnly: tvOnly, links: links)
    }

    /// K1 · uno de la TV que este iPhone no tenía, ya con su dirección completa (`?full=1`): se guarda como los traídos (la
    /// dirección en el llavero, nunca en los ajustes), con el prendido que la TV dice para este aparato. Devuelve su id aquí.
    @discardableResult
    public func adoptFromTV(_ shared: SharedAddon, url: String, name: String, resources: [String], device: String, platform: String?) -> String? {
        guard url.lowercased().hasPrefix("https://"), !url.contains(AddonRedaction.mask), !shared.isTVFiles, !resources.isEmpty else { return nil }
        var id: String?
        fromTV {
            let added = add(url: url, name: shared.name.isEmpty ? name : shared.name, resources: resources, origin: .imported)
            setEnabled(added, shared.isEnabled(device: device, platform: platform) ?? true)
            id = added
        }
        return id
    }

    /// «Usar la de este iPhone» tras un choque (S3): tus opciones de antes vuelven y se mandan.
    public func restoreTorrentio(_ options: AddonOptions) {
        guard let id = torrentio?.id else { return }
        setOptions(id, options)
    }
}
