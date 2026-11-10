import Foundation
import OrbitalCore

/// «Tu nota» de cada película o serie (G6, gestor ola 3, Fernando, 10 nov 2026: «Vamos con todo y tus sugerencias… si no
/// tienes VIP, se guarda en el iPhone»). Con Trakt VIP vive en tu Trakt (privada, hasta 500 letras, también sin red: espera en
/// la cola); sin VIP, solo en este iPhone. Si un día tienes VIP, las del iPhone pasan solas a Trakt.
@MainActor
public final class NotesModel: ObservableModel {
    let services: Services
    /// nil: aún no se sabe (sin red y sin respuesta guardada).
    public private(set) var vip: Bool? { didSet { if vip != oldValue { changed() } } }
    private var remote: [String: (id: Int, text: String)] = [:]
    static let vipKey = "trakt-vip", localKey = "notes-local"

    public init(_ services: Services) {
        self.services = services
        vip = services.kv.data(Self.vipKey).flatMap { String(data: $0, encoding: .utf8) }.map { $0 == "1" }
        super.init()
    }

    /// Dónde se guarda, para decirlo bajo la nota.
    public var savesInTrakt: Bool { vip == true }

    /// IMDb → [texto, «movie» o «series»] (la serie hace falta para subirla a Trakt si un día eres VIP).
    private var local: [String: [String]] {
        get { services.kv.data(Self.localKey).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:] }
        set { services.kv.set(Self.localKey, data: try? JSONEncoder().encode(newValue)) }
    }

    /// Tu nota de este título ("" si no hay).
    public func note(_ imdb: String) -> String {
        track()
        if let pending = services.traktOutbox.pendingNotes[imdb] { return pending }
        return remote[imdb]?.text ?? local[imdb]?.first ?? ""
    }

    /// Pregunta a Trakt si eres VIP y trae tus notas; con VIP, sube las que estaban solo en el iPhone.
    public func load() async {
        guard let trakt = services.trakt, trakt.linked, let isVIP = try? await trakt.isVIP() else { return }
        vip = isVIP
        services.kv.set(Self.vipKey, data: (isVIP ? "1" : "0").data(using: .utf8))
        guard isVIP else { return }
        if let found = try? await trakt.myNotes() { remote = found; changed() }
        let moving = local
        guard !moving.isEmpty else { return }
        for (imdb, value) in moving where remote[imdb] == nil {
            services.traktOutbox.enqueue(.note(imdb: imdb, series: value.last == "series", String((value.first ?? "").prefix(Trakt.noteLimit))))
        }
        local = [:]
        await services.traktOutbox.flush(trakt)
        if let found = try? await trakt.myNotes() { remote = found; changed() }
    }

    /// Guarda (o, vacía, borra) tu nota. Con VIP va a Trakt (sin red, espera); sin VIP, al iPhone.
    public func save(_ imdb: String, series: Bool, text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if vip == true {
            let limited = String(clean.prefix(Trakt.noteLimit))
            services.traktOutbox.enqueue(.note(imdb: imdb, series: series, limited))
            changed()
            await services.traktOutbox.flush(services.trakt)
            if services.traktOutbox.pendingNotes[imdb] == nil {   // ya llegó
                if limited.isEmpty { remote[imdb] = nil } else { remote[imdb] = (remote[imdb]?.id ?? 0, limited) }
                if let trakt = services.trakt, let found = try? await trakt.myNotes() { remote = found }
            }
        } else {
            var all = local
            all[imdb] = clean.isEmpty ? nil : [clean, series ? "series" : "movie"]
            local = all
        }
        changed()
    }
}
