import Foundation
import OrbitalCore

/// Qué tan rápido arranca una fuente, sin prometer de más: solo se sabe que es al instante si Real-Debrid ya la tiene.
public enum SourceSpeed: Sendable, Equatable {
    /// Ya está en Real-Debrid ([RD+]): arranca al instante.
    case inRealDebrid
    /// Pasa por Real-Debrid pero aún no la tiene: la tiene que bajar antes (puede tardar en abrir).
    case realDebridMustDownload
    /// No se sabe (no pasa por Real-Debrid o el complemento no lo dice).
    case unknown

    public init(_ source: Source) {
        if source.cached { self = .inRealDebrid }
        else if source.debrid { self = .realDebridMustDownload }
        else { self = .unknown }
    }
}

/// «Todas las fuentes»: la lista completa y plana (para quien quiere ver todo), agrupada por calidad, con filtros y orden,
/// y honesta con lo que se sabe de cada una (si Real-Debrid ya la tiene, cómo sabemos su idioma).
public enum AllSources {
    public struct Filter: Equatable, Sendable {
        /// Solo las que ya están en Real-Debrid (arrancan al instante).
        public var onlyInRealDebrid: Bool
        /// Un idioma sin variante («es», «en»): coincide con «es-419» y «es-ES».
        public var language: String?
        /// También las grabaciones de cine y los tráileres (al final de su calidad, atenuadas).
        public var showHidden: Bool

        public init(onlyInRealDebrid: Bool = false, language: String? = nil, showHidden: Bool = false) {
            self.onlyInRealDebrid = onlyInRealDebrid; self.language = language; self.showHidden = showHidden
        }

        /// Cuántos filtros están puestos («Filtrar · 2»).
        public var activeCount: Int { (onlyInRealDebrid ? 1 : 0) + (language != nil ? 1 : 0) + (showHidden ? 1 : 0) }
    }

    public enum Order: String, CaseIterable, Sendable {
        /// El orden de la recomendación (el mismo puntaje que elige la que arranca sola).
        case recommended
        /// Las más chicas primero (sin tamaño, al final).
        case smallest
        /// Las de más semillas primero (sin semillas, al final).
        case mostSeeders
    }

    /// Una calidad con sus fuentes: las primeras `shown` y cuántas más hay.
    public struct Group: Equatable, Sendable, Identifiable {
        public var id: String { quality }
        /// «4K», «1080p», «720p», «480p» u «Otras» (sin resolución).
        public var quality: String
        public var total: Int
        public var shown: [Source]
        public var more: Int
    }

    /// Cómo sabemos un idioma, en lo que importa al que elige: comprobado, lo dice el nombre o el sitio, o se supone.
    public enum EvidenceKind: Sendable, Equatable {
        case checked, name, site, assumed

        public init(_ evidence: AudioLanguage.Evidence) {
            switch evidence {
            case .checked: self = .checked
            case .name: self = .name
            case .site: self = .site
            case .original, .unknown, .maybe: self = .assumed
            }
        }
    }

    public static let qualities = ["4K", "1080p", "720p", "480p", "Otras"]

    public static func quality(_ s: Source) -> String {
        switch s.resolution.lowercased() {
        case "4k", "2160p": "4K"
        case "1080p", "1440p": "1080p"
        case "720p": "720p"
        case "480p": "480p"
        default: "Otras"
        }
    }

    /// Las grabaciones de cine y los tráileres (las mismas que esconde «Elegir versión»). «¿Otro título?» no se esconde: se marca.
    public static func isHidden(_ s: Source) -> Bool { s.tags.contains("CAM") || s.tags.contains("Tráiler") }

    /// La marca de una oculta («CAM», «Tráiler»), para decir por qué va atenuada.
    public static func hiddenTag(_ s: Source) -> String? { ["CAM", "Tráiler"].first(where: s.tags.contains) }

    /// ¿Pasa los filtros de Real-Debrid e idioma? (Ocultas aparte: ver `showHidden`.)
    static func passes(_ s: Source, _ filter: Filter) -> Bool {
        if filter.onlyInRealDebrid && !s.cached { return false }
        if let language = filter.language, !languageCodes(s).contains(where: { $0 == language || $0.hasPrefix(language + "-") }) { return false }
        return true
    }

    /// Los códigos de audio de una fuente (con variante si la hay).
    static func languageCodes(_ s: Source) -> [String] { s.audio.isEmpty ? s.languages : s.audio.map(\.code) }

    /// Ordena sin perder el orden de la recomendación entre iguales; lo que no se sabe (tamaño o semillas en 0) va al final.
    public static func sorted(_ sources: [Source], order: Order) -> [Source] {
        let indexed = Array(sources.enumerated())
        switch order {
        case .recommended:
            return sources
        case .smallest:
            return indexed.sorted { a, b in
                let x = a.element.size, y = b.element.size
                if (x == 0) != (y == 0) { return y == 0 }
                return x != y ? x < y : a.offset < b.offset
            }.map(\.element)
        case .mostSeeders:
            return indexed.sorted { a, b in
                let x = a.element.seeders, y = b.element.seeders
                if (x == 0) != (y == 0) { return y == 0 }
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        }
    }

    /// Los grupos por calidad (4K, 1080p, 720p, 480p, Otras; solo los que tienen algo), cada uno con sus primeras
    /// `shownPerGroup`. Las ocultas, si se piden, al final de su calidad.
    public static func groups(_ ranked: [Source], filter: Filter = Filter(), order: Order = .recommended, shownPerGroup: Int = 3) -> [Group] {
        let passing = sorted(ranked.filter { passes($0, filter) }, order: order)
        let visible = passing.filter { !isHidden($0) }
        let list = filter.showHidden ? visible + passing.filter(isHidden) : visible
        return qualities.compactMap { q in
            let items = list.filter { quality($0) == q }
            guard !items.isEmpty else { return nil }
            let shown = Array(items.prefix(max(shownPerGroup, 0)))
            return Group(quality: q, total: items.count, shown: shown, more: items.count - shown.count)
        }
    }

    /// Cuántas hay con estos filtros: las que se ven (sin ocultas) y las ocultas (grabaciones de cine y tráileres).
    public static func count(_ ranked: [Source], filter: Filter = Filter()) -> (shown: Int, hidden: Int) {
        let passing = ranked.filter { passes($0, filter) }
        let hidden = passing.filter(isHidden).count
        return (passing.count - hidden, hidden)
    }

    /// Los idiomas (sin variante) que hay para filtrar, de los que más fuentes tienen a los que menos.
    public static func languages(in ranked: [Source]) -> [String] {
        var counts: [String: Int] = [:], order: [String] = []
        for s in ranked where !isHidden(s) {
            var seen = Set<String>()
            for code in languageCodes(s) {
                let base = String(code.split(separator: "-").first ?? Substring(code))
                guard seen.insert(base).inserted else { continue }
                if counts[base] == nil { order.append(base) }
                counts[base, default: 0] += 1
            }
        }
        return order.enumerated().sorted { a, b in
            let x = counts[a.element] ?? 0, y = counts[b.element] ?? 0
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
    }

    /// El audio de una fuente con cómo lo sabemos, idioma por idioma (sin repetir: el mejor indicio de cada código).
    public static func languageEvidence(_ s: Source) -> [(code: String, kind: EvidenceKind)] {
        let audio = s.audio.isEmpty ? s.languages.map { AudioLanguage($0, .maybe) } : s.audio
        var out: [(code: String, kind: EvidenceKind)] = []
        var best: [String: AudioLanguage.Evidence] = [:]
        for a in audio {
            if let e = best[a.code] { if a.evidence < e { best[a.code] = a.evidence } } else { best[a.code] = a.evidence; out.append((a.code, .assumed)) }
        }
        return out.map { ($0.code, EvidenceKind(best[$0.code] ?? .maybe)) }
    }

    /// El nombre del archivo, si el complemento lo da y no es el mismo que el de la versión.
    public static func fileName(_ s: Source) -> String? {
        guard let name = s.stream["behaviorHints"]?["filename"]?.nonEmptyString, name != s.release else { return nil }
        return name
    }

    /// El nombre técnico para copiar: el de la versión o, si no hay, el del archivo.
    public static func copyName(_ s: Source) -> String { s.release.isEmpty ? (fileName(s) ?? "") : s.release }

    /// La insignia de imagen que va en el renglón (una sola: la mejor; `hdr` ya viene de mejor a peor: DV, HDR10+, HDR).
    public static func hdrBadge(_ s: Source) -> String? { s.hdr.first }
}
