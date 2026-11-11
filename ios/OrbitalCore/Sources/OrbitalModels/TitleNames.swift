import Foundation
import OrbitalCore

/// La regla del nombre que se enseña de una película o serie (revisión 2 del 11 nov 2026: «Dune» y «Duna», «The Office» y
/// «La Oficina» convivían en la misma pantalla). Es la misma de la TV (`TitleNames` en `orbital/library/localize.py`):
/// el nombre en el idioma de la app si ya se sabe (TMDB; si el título se hizo en ese idioma, su nombre original), y si no,
/// el que trae la fuente. En inglés, o sin clave de TMDB, todo queda como viene.
public enum DisplayTitle {
    /// El nombre que se enseña: el conocido en tu idioma o, sin él, el que llegó (sin espacios de sobra).
    public static func resolve(raw: String, known: String?) -> String {
        if let known = known?.trimmingCharacters(in: .whitespacesAndNewlines), !known.isEmpty { return known }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// El id de IMDb de un título a partir del de un episodio («tt0386676:2:5» → «tt0386676»); nil si no es de IMDb.
    public static func titleID(_ id: String?) -> String? {
        guard let id, id.hasPrefix("tt") else { return nil }
        let base = id.prefix { $0 != ":" }
        return base.count > 2 ? String(base) : nil
    }

    /// «movie»/«series» (y lo que mandan Trakt y la TV: «show», «episode», «tv»); nil si no se sabe.
    public static func kind(_ kind: String?) -> String? {
        switch kind?.lowercased() {
        case "movie", "film", "pelicula", "película": return "movie"
        case "series", "show", "tv", "episode", "serie": return "series"
        default: return nil
        }
    }
}

/// La puerta única del nombre de un título: toda vista que pinta el nombre de una película o serie (filas, pósters, ficha,
/// Guardado, Lo que ves, Buscar, el control, el reproductor, la pantalla bloqueada, widgets, Siri y VoiceOver) pasa por
/// aquí. Lo que no se sabe se pide en segundo plano (nunca hace esperar a una lista) y entra en el siguiente pintado, como
/// en la TV. `DesignRulesTests.testTitlesGoThroughOneDoor` vigila que nadie pinte el nombre crudo.
@MainActor
public final class TitleNames: ObservableModel {
    /// Pide el nombre en tu idioma (`Localizer.title`); nil si no hay que traducir o no se encontró.
    public typealias Lookup = @Sendable (_ kind: String, _ imdb: String) async -> String?
    /// Lo que ya se sabe al arrancar (memoria y disco del `Localizer`).
    public typealias Known = @Sendable () async -> [String: String]

    private var names: [String: String] = [:]
    private var asked: Set<String> = []
    private var language: String?
    private let currentLanguage: () -> String?
    private var lookup: Lookup
    private var known: Known
    private var arrived = false
    private let settle: Duration

    /// `language`: el idioma de TMDB en uso («es-MX»; nil = no se traduce). `settle`: cuánto se juntan los nombres que llegan
    /// antes de volver a pintar (uno por tanda, no uno por título).
    public init(language: @escaping () -> String?, lookup: @escaping Lookup, known: @escaping Known = { [:] },
                settle: Duration = .milliseconds(200)) {
        self.currentLanguage = language; self.lookup = lookup; self.known = known; self.settle = settle
        super.init()
        hydrate()
    }

    /// Sin traducir nada (vistas previas y pruebas de interfaz sin `Services`).
    public static func inert() -> TitleNames { TitleNames(language: { nil }, lookup: { _, _ in nil }) }

    /// El nombre que se enseña. `id`: el de IMDb del título (o de su episodio); `kind`: «movie»/«series» (sin él, solo se
    /// usa lo que ya se sabe).
    public func name(_ raw: String, id: String?, kind: String? = nil) -> String {
        track()
        syncLanguage()
        guard language != nil, let id = DisplayTitle.titleID(id) else { return DisplayTitle.resolve(raw: raw, known: nil) }
        if let hit = names[id] { return DisplayTitle.resolve(raw: raw, known: hit) }
        if let kind = DisplayTitle.kind(kind), !asked.contains(id) {
            asked.insert(id)
            let lookup = lookup
            Task { [weak self] in
                let found = await lookup(kind, id)
                self?.arrive(id: id, name: found)
            }
        }
        return DisplayTitle.resolve(raw: raw, known: nil)
    }

    /// Un nombre ya traducido (la ficha, Inicio): sirve para todo lo demás.
    public func remember(id: String?, name: String) {
        syncLanguage()
        guard language != nil, let id = DisplayTitle.titleID(id) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, names[id] != clean else { return }
        names[id] = clean
        changed()
    }

    /// Tras cambiar la clave de TMDB: lo de antes ya no vale.
    public func reset(lookup: @escaping Lookup, known: @escaping Known) {
        self.lookup = lookup; self.known = known
        names = [:]; asked = []
        hydrate()
        changed()
    }

    /// El nombre que ya se sabe, sin pedir nada (para pruebas y para quien solo quiere comparar).
    public func known(_ id: String?) -> String? { DisplayTitle.titleID(id).flatMap { names[$0] } }

    private func syncLanguage() {
        let now = currentLanguage()
        guard now != language else { return }
        language = now
        names = [:]; asked = []
        if now != nil { hydrate() }
    }

    private func hydrate() {
        language = currentLanguage()
        guard language != nil else { return }
        let known = known, lang = language
        Task { [weak self] in
            let found = await known()
            guard let self, self.language == lang, !found.isEmpty else { return }
            for (id, name) in found where self.names[id] == nil { self.names[id] = name }
            self.changed()
        }
    }

    private func arrive(id: String, name: String?) {
        // Sin nombre (sin red, o TMDB aún no lo tiene): se vuelve a preguntar en el siguiente pintado (Localizer guarda el fallo un rato).
        guard let name, !name.isEmpty else { asked.remove(id); return }
        guard names[id] != name else { return }
        names[id] = name
        guard !arrived else { return }
        arrived = true
        let settle = settle
        Task { [weak self] in
            try? await Task.sleep(for: settle)   // ds-exception: se juntan los nombres que llegan en una sola pasada
            guard let self else { return }
            self.arrived = false
            self.changed()
        }
    }
}
