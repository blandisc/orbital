import Foundation
import OrbitalCore

/// Una fuente para mostrar en la lista (sin URL: lleva tu clave de Real-Debrid).
public struct SourceRow: Equatable, Identifiable, Sendable {
    public var id: Int
    public var headline: String          // «1080p · Español · x265»
    public var recommended: Bool
    public var cached: Bool              // «Al instante»
    public var sizeGB: Double?           // nil si no se sabe
    public var heavy: Bool               // más de lo que conviene con datos móviles
    public var hdr: [String]
    public var tags: [String]
    public var addon: String
    /// Para las insignias (como Infuse): la resolución y el sonido (Atmos, TrueHD, 7.1…).
    public var resolution = ""
    public var audio: [String] = []
    /// El nombre del archivo (para quien lo quiera ver: mantener presionada la fuente).
    public var release = ""
    /// Se puede bajar (un archivo, no una lista HLS/DASH).
    public var downloadable = true
    /// La que más conviene guardar en el teléfono (1080p, ligera), cuando no es la recomendada para ver.
    public var bestToSave = false
    /// El grupo en la hoja: «4K», «1080p», «720p» u «Otras».
    public var group: String {
        switch resolution.lowercased() {
        case "4k", "2160p": return "4K"
        case "1080p", "1440p": return "1080p"
        case "720p": return "720p"
        default: return "Otras"
        }
    }
}

/// La lista de fuentes de un episodio o película: una sola, ordenada para ver (la recomendada primero), y en cada una se
/// puede ver o descargar. La que más conviene guardar (ligera) se marca aparte.
@MainActor
public final class SourcesModel: ObservableModel {
    public private(set) var rows: [SourceRow] = [] { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    /// «Elegir versión»: las filas por idioma (el tuyo, el original y las variantes de español), los demás idiomas y cuántas
    /// se esconden (grabadas en el cine, tráileres).
    public private(set) var languageRows: [LanguageRow] = [] { didSet { changed() } }
    public private(set) var moreLanguages: [LanguageRow] = [] { didSet { changed() } }
    public private(set) var hiddenCount = 0 { didSet { changed() } }
    /// Lo que pediste (para decir «tu idioma» y el nombre de cada uno).
    public private(set) var prefs = Preferences()
    var limitGB = 5.0
    private var sources: [Source] = []
    private let services: Services
    private var loadCount = 0
    private let kind: String, videoID: String, metaID: String

    public init(_ services: Services, kind: String, metaID: String, videoID: String) {
        self.services = services; self.kind = kind; self.metaID = metaID; self.videoID = videoID
        super.init()
    }

    public func load(onCellular: Bool = false) async {
        isLoading = true
        // Solo la última carga apaga el indicador (una vieja que se cancela no lo quita a media espera).
        loadCount += 1
        let ticket = loadCount
        defer { if ticket == loadCount { isLoading = false } }
        let settings = services.appSettings
        let prefs = services.titlePrefs.languages(for: metaID, settings: settings, onCellular: onCellular).prefs
        self.prefs = prefs
        limitGB = settings.warnCellularOverGB
        let found: [Source]
        do { found = try await services.finder.find(kind: kind, videoID: videoID, prefs: prefs, purpose: .watch) }
        catch where !Task.isCancelled {
            sources = []; rows = []; languageRows = []; moreLanguages = []; hiddenCount = 0
            self.error = (error as? StreamFinderError)?.description ?? "No pude buscar fuentes. Intenta de nuevo."
            return
        }
        catch { return }
        guard !Task.isCancelled, ticket == loadCount else { return }
        sources = found
        let grouped = Self.languageRows(found, prefs: prefs, limitGB: settings.warnCellularOverGB)
        languageRows = grouped.main; moreLanguages = grouped.more; hiddenCount = grouped.hidden
        error = sources.isEmpty ? "Real-Debrid aún no tiene este título. Los estrenos suelen aparecer unas horas después." : nil
        let limit = Int64(settings.warnCellularOverGB * 1e9)
        let canSave = { (s: Source) in s.playbackURL.map { !["m3u8", "mpd"].contains($0.pathExtension.lowercased()) } ?? false }
        // Para guardar: el mismo puntaje que usa «Descargar» (1080p, HEVC, tamaño moderado), solo si no es la de ver.
        let toSave = sources.filter(canSave).max { Streams.score($0, prefs: prefs, kind: kind, purpose: .download) < Streams.score($1, prefs: prefs, kind: kind, purpose: .download) }
        rows = sources.enumerated().map { i, s in
            let langs = s.languages.prefix(2).map { Streams.languageName($0, in: services.appSettings.uiLanguage) }.joined(separator: " + ")
            let headline = [s.resolution.isEmpty ? "SD" : s.resolution, langs, s.tags.first(where: { ["REMUX", "WEB-DL", "BluRay"].contains($0) }), s.tags.contains("x265") ? "x265" : nil]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return SourceRow(id: s.index, headline: headline, recommended: i == 0, cached: s.cached, sizeGB: s.size > 0 ? Double(s.size) / 1e9 : nil,
                             heavy: Int64(s.size) > limit, hdr: s.hdr, tags: s.tags.filter { $0 != "x265" && !["REMUX", "WEB-DL", "BluRay", "Atmos", "5.1"].contains($0) }, addon: s.addon,
                             resolution: s.resolution, audio: s.audioBadges, release: s.release,
                             downloadable: canSave(s), bestToSave: i != 0 && s.index == toSave?.index)
        }
    }

    /// La fuente elegida, para reproducir o descargar.
    public func source(_ id: Int) -> Source? { sources.first { $0.index == id } }

    /// Todas, en el orden de la recomendación (incluidas las ocultas): «Todas las fuentes».
    public var ranked: [Source] { sources }
    /// La recomendada (la primera que no es de cine ni tráiler; si todas lo son, la primera).
    public var recommendedIndex: Int? { (sources.first { !Self.hidden($0) } ?? sources.first)?.index }
}

// MARK: «Elegir versión»: por idioma y calidad
/// Una calidad dentro de un idioma: la mejor versión de esa calidad y cuántas más hay.
public struct VersionOption: Identifiable, Equatable, Sendable {
    public var id: Int                    // el índice de la fuente
    public var quality: String            // «4K», «1080p», «720p», «SD»
    public var sizeGB: Double?
    public var cached: Bool
    /// «DV · Atmos»: lo que la distingue.
    public var badges: [String]
    /// Cómo sabemos que trae este idioma.
    public var evidence: AudioLanguage.Evidence
    /// Los otros idiomas que trae («en» en una «Dual-Lat»).
    public var alsoHas: [String]
    public var release: String
    public var site: String
    public var downloadable: Bool
    public var heavy: Bool
    public var recommended: Bool
    /// Las demás de este idioma y calidad (sus índices), en orden.
    public var others: [Int]
    /// «¿Otro título?»: el nombre dice otro año.
    public var otherTitle: Bool
    /// Pasa por Real-Debrid (si no está en `cached`, Real-Debrid aún la tiene que bajar).
    public var debrid = false
    /// Qué tan rápido arranca, sin prometer de más.
    public var speed: SourceSpeed { cached ? .inRealDebrid : debrid ? .realDebridMustDownload : .unknown }
}

/// Una fila de «Elegir versión»: un idioma con sus calidades (solo las que existen).
public struct LanguageRow: Identifiable, Equatable, Sendable {
    public var id: String { code }
    public var code: String               // «es-419», «es-ES», «es», «en»…
    public var yours: Bool                // el idioma que pediste
    public var original: Bool             // el idioma original del título
    /// Toda la fila es «tal vez» (ninguna versión lo dice seguro).
    public var allMaybe: Bool { options.allSatisfy { $0.evidence == .maybe } }
    public var options: [VersionOption]
}

extension SourcesModel {
    static let qualityOrder = ["4K", "1080p", "720p", "SD"]
    static func quality(_ s: Source) -> String {
        switch s.resolution.lowercased() {
        case "4k", "2160p": return "4K"
        case "1080p", "1440p": return "1080p"
        case "720p": return "720p"
        default: return "SD"
        }
    }

    /// Las grabadas en el cine y los tráileres no se ofrecen (se cuentan aparte).
    static func hidden(_ s: Source) -> Bool { s.tags.contains("CAM") || s.tags.contains("Tráiler") }

    /// La fila en que va un idioma: lo «tal vez» del español va a «Español (no dice cuál)»; lo demás, a su idioma.
    static func rowCode(_ a: AudioLanguage) -> String {
        if a.base == "es" { return a.evidence.solid ? a.code : "es" }
        return a.base
    }

    /// Una versión para enseñar en el idioma `code`.
    static func option(_ s: Source, code: String, evidence: AudioLanguage.Evidence, limitGB: Double, recommended: Bool, others: [Int] = []) -> VersionOption {
        VersionOption(id: s.index, quality: quality(s), sizeGB: s.size > 0 ? Double(s.size) / 1e9 : nil, cached: s.cached,
                      badges: s.qualitySummary.filter { $0 != s.resolution }, evidence: evidence,
                      alsoHas: s.audio.map(rowCode).filter { $0 != code }, release: s.release, site: s.site,
                      downloadable: s.playbackURL.map { !["m3u8", "mpd"].contains($0.pathExtension.lowercased()) } ?? false,
                      heavy: Double(s.size) / 1e9 > limitGB, recommended: recommended, others: others,
                      otherTitle: s.tags.contains(Streams.otherTitleTag), debrid: s.debrid)
    }

    /// Las demás versiones de ese idioma y calidad («Otras 2 en latino 1080p»), en orden.
    public func others(of option: VersionOption, in row: LanguageRow) -> [VersionOption] {
        option.others.compactMap { id in
            guard let s = source(id) else { return nil }
            let evidence = s.audio.filter { Self.rowCode($0) == row.code }.map(\.evidence).min() ?? .maybe
            return Self.option(s, code: row.code, evidence: evidence, limitGB: limitGB, recommended: false)
        }
    }

    /// Las filas, ya ordenadas: el tuyo, el original, las variantes de español y luego los demás (por cuántas versiones tienen).
    /// SD solo se ofrece si ese idioma no tiene nada mejor.
    public static func languageRows(_ ranked: [Source], prefs: Preferences, limitGB: Double) -> (main: [LanguageRow], more: [LanguageRow], hidden: Int) {
        // Si todo es de cine o tráiler, se enseña igual (si no, la hoja quedaba vacía y «Ver» reproducía una de esas).
        let visible = ranked.contains { !hidden($0) } ? ranked.filter { !hidden($0) } : ranked
        let recommended = visible.first?.index
        var cells: [String: [String: [Source]]] = [:], evidence: [String: [Int: AudioLanguage.Evidence]] = [:], order: [String] = []
        var originals = Set<String>()
        for source in visible {
            var placed = Set<String>()   // una versión, una vez por fila (con «es» y «es-419 tal vez» salía dos veces)
            for audio in source.audio {
                let code = rowCode(audio)
                if cells[code] == nil { order.append(code) }
                if placed.insert(code).inserted { cells[code, default: [:]][quality(source), default: []].append(source) }
                if evidence[code, default: [:]][source.index].map({ audio.evidence < $0 }) ?? true { evidence[code, default: [:]][source.index] = audio.evidence }
                if audio.evidence == .original { originals.insert(code) }
            }
        }
        let want = prefs.wanted
        func row(_ code: String) -> LanguageRow {
            let byQuality = cells[code] ?? [:]
            var options: [VersionOption] = qualityOrder.compactMap { q in
                // La de otro título nunca va de primera si hay otra.
                guard let list = byQuality[q]?.sorted(by: { a, b in
                    let x = a.tags.contains(Streams.otherTitleTag), y = b.tags.contains(Streams.otherTitleTag)
                    return x == y ? false : !x
                }), let best = list.first else { return nil }
                return option(best, code: code, evidence: evidence[code]?[best.index] ?? .maybe, limitGB: limitGB,
                              recommended: best.index == recommended, others: list.dropFirst().map(\.index))
            }
            // SD solo si no hay nada mejor, salvo que sea la recomendada (la que reproduce «Ver» siempre se ve).
            if options.count > 1 { options.removeAll { $0.quality == "SD" && !$0.recommended } }
            let yours = code == want || (want.count == 2 && code.hasPrefix(want))
            return LanguageRow(code: code, yours: yours, original: originals.contains(code), options: options)
        }
        let rows = order.map(row).filter { !$0.options.isEmpty }
        func rank(_ r: LanguageRow) -> Int {
            // Con «cualquier español» las que dicen cuál van antes que la que no lo dice.
            if r.code == want, want.count > 2 || !want.hasPrefix("es") { return 0 }
            if r.yours { return r.code == "es" ? 2 : 1 }
            if r.original { return 2 }
            if r.code.hasPrefix("es") { return 3 }   // latino, castellano y español, aunque prefieras otro idioma (como la TV)
            return 4
        }
        let count = { (r: LanguageRow) in r.options.reduce(0) { $0 + 1 + $1.others.count } }
        let sorted = rows.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : count(a.element) != count(b.element) ? count(a.element) > count(b.element) : a.offset < b.offset
        }.map(\.element)
        return (sorted.filter { rank($0) < 4 }, sorted.filter { rank($0) == 4 }, ranked.count - visible.count)
    }
}
