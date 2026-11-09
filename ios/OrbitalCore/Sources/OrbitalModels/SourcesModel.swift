import Foundation
import OrbitalCore
import OrbitalAddons

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
    /// «Hay que pedirlas · tardan»: las que Real-Debrid aún no tiene y no salen ya como la mejor de su idioma y calidad (ahí
    /// las tapaba la que arranca al instante). Fernando, 3 nov, probando la 1729: «no encuentro nada que no esté al instante».
    public private(set) var toRequest: [RequestableVersion] = [] { didSet { changed() } }
    /// C8: los complementos que no contestaron a tiempo o se saltaron (sus versiones no están en la lista), por su nombre.
    public private(set) var quiet: [String] = [] { didSet { if oldValue != quiet { changed() } } }
    /// Lo que pediste (para decir «tu idioma» y el nombre de cada uno).
    public private(set) var prefs = Preferences()
    var limitGB = 5.0
    private var sources: [Source] = []
    /// Lo que existe para pedir y la lista de Real-Debrid no trae (Torrentio sin Real-Debrid, R4): solo para «Hay que
    /// pedirlas · tardan» y para pedirlas, nunca para ver.
    private var requestable: [Source] = []
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
            sources = []; requestable = []; rows = []; languageRows = []; moreLanguages = []; hiddenCount = 0; toRequest = []
            // Ningún complemento contestó: con internet son ellos, no tu conexión (`Degraded`).
            self.error = error is StreamFinderError
                ? (services.isOnline() ? "Tus complementos no contestan: hay internet, pero ninguno respondió. Intenta en un rato." : StreamFinderError.unreachable.description)
                : "No pude buscar versiones. Intenta de nuevo."
            return
        }
        catch { return }
        guard !Task.isCancelled, ticket == loadCount else { return }
        quiet = await services.finder.quiet(kind: kind, videoID: videoID)
        sources = found
        // N2-A: lo que ya pediste y sigue en camino (un paquete pedido desde otro episodio también) dice cómo va, no «Por pedir».
        let requests = services.debridRequests
        let inCloud = Dictionary(found.compactMap { s in s.torrent.flatMap { t in requests.request(hash: t.hash).flatMap { $0.state.isActive ? (s.index, $0.percent) : nil } } },
                                 uniquingKeysWith: { a, _ in a })
        var grouped = Self.languageRows(found, prefs: prefs, limitGB: settings.warnCellularOverGB)
        grouped.main = Self.marking(grouped.main, inCloud); grouped.more = Self.marking(grouped.more, inCloud)
        languageRows = grouped.main; moreLanguages = grouped.more; hiddenCount = grouped.hidden
        // Invariante 1 (la ficha y «Versión» no se contradicen): si tu lista no trae nada que pedir (Real-Debrid no tiene nada o tu
        // Torrentio solo da lo que ya está), la ficha ofrece «Pedir a la nube» con lo que existe sin Real-Debrid; aquí también.
        let extra = await Self.requestableAside(found, services: services, kind: kind, videoID: videoID, metaID: metaID, prefs: prefs)
        guard !Task.isCancelled, ticket == loadCount else { return }
        requestable = extra
        toRequest = Self.toRequest(found + extra, shown: grouped.main + grouped.more, prefs: prefs, limitGB: settings.warnCellularOverGB, inCloud: Set(inCloud.keys))
        error = !sources.isEmpty ? nil : toRequest.isEmpty ? "Real-Debrid aún no tiene este título. Los estrenos suelen aparecer unas horas después."
            : "Real-Debrid aún no tiene este título."   // y abajo, «Hay que pedirlas»
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
    public func source(_ id: Int) -> Source? { sources.first { $0.index == id } ?? requestable.first { $0.index == id } }

    /// Lo que se puede pedir aparte de tu lista, en los mismos casos en que la ficha ofrece «Pedir a la nube» con lo que existe
    /// sin Real-Debrid (`TitleModel.offerToRequest`, R4): tu lista no trae ninguna que pedir, nada arranca al instante y tu
    /// cuenta puede pedir (vencida, sin Premium o con la clave vieja, la salida es otra). Los torrents de Torrentio sin
    /// Real-Debrid que no están ya en tu lista ni los rechazó Real-Debrid, marcados «por bajar».
    static func requestableAside(_ found: [Source], services: Services, kind: String, videoID: String, metaID: String, prefs: Preferences) async -> [Source] {
        let requests = services.debridRequests
        guard requests.canRequest, !found.contains(where: { !$0.instant && !hidden($0) && !$0.refused && $0.torrent != nil }),
              !(toPlay(found, resume: nil, family: nil)?.instant ?? false) else { return [] }
        let account = UnavailableCause.Account.from(nil, saved: services.debrid.saved, now: services.now())
        guard account == .ok || account == .unknown,
              !(await services.finder.notices(kind: kind, videoID: videoID)).contains(where: \.aboutTheAccount) else { return [] }
        guard let all = await requests.torrents(kind: kind, videoID: videoID, prefs: prefs) else { return [] }
        let known = Set(found.compactMap { $0.torrent?.hash }).union(requests.requester.refused(metaID: metaID))
        let indices = Set(found.map(\.index))
        return all.compactMap { s in
            guard let hash = s.torrent?.hash, !known.contains(hash), !indices.contains(s.index), !hidden(s) else { return nil }
            var s = s
            s.debrid = true; s.cached = false
            return s
        }
    }

    /// Todas, en el orden de la recomendación (incluidas las ocultas): «Todas las fuentes».
    public var ranked: [Source] { sources }
    /// La recomendada (la primera que no es de cine ni tráiler; si todas lo son, la primera).
    public var recommendedIndex: Int? { (sources.first { !Self.hidden($0) } ?? sources.first)?.index }

    /// Lo que pone «Ver» de la ficha y el reproductor sin una versión elegida («Ver ahora» del aviso de listo): una sola regla
    /// para los dos. Lo que pediste y ya está va primero (Fernando, 3 nov: «análisis de fondo… para que no encuentre yo más
    /// errores»: la de «Continuar» le ganaba a la que pediste); luego la versión con que lo dejaste, la de su misma familia
    /// en el siguiente episodio y, al final, la recomendada (nunca una de cine o un tráiler si hay otra).
    public static func toPlay(_ found: [Source], resume: String?, family: String?) -> Source? {
        // Ni de cine ni tráiler, ni lo que Real-Debrid no dejó bajar (FQ2-A), si hay otra.
        let usable = found.contains { !hidden($0) && !$0.refused } ? found.filter { !hidden($0) && !$0.refused }
            : found.contains { !hidden($0) } ? found.filter { !hidden($0) } : found
        if let ready = usable.first(where: \.requested) { return ready }
        // La de «Continuar», salvo que sea de otro título (Fernando, 8 nov: recordaba la de «The Clone Wars» en la de 2003).
        if let resume, let same = found.first(where: { $0.key == resume && !$0.isOtherTitle }) { return same }
        let first = usable.first
        if let family, let same = usable.first(where: { $0.binge == family && $0.score > (first?.score ?? 0) - 700 }) { return same }
        return first
    }
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
    /// «¿Otro título?»: el nombre dice otro año (o «¿Otro episodio?»: trae otra temporada, `otherEpisode`).
    public var otherTitle: Bool
    /// «¿Otro episodio?»: el archivo o el nombre dicen otra temporada.
    public var otherEpisode = false
    /// Pasa por Real-Debrid (si no está en `cached`, Real-Debrid aún la tiene que bajar).
    public var debrid = false
    /// La pediste y Real-Debrid ya la terminó: «Al instante · la pediste».
    public var requested = false
    /// N2-A: la pediste (aquí, en la TV con tu cuenta o un paquete desde otro episodio) y sigue en camino: «Bajando · 40 %»;
    /// tocarla abre el pedido, nunca lo pide otra vez. `cloudPercent`: cuánto lleva.
    public var inCloud = false
    public var cloudPercent = 0
    /// Real-Debrid no la dejó bajar (FQ2-A): «Real-Debrid no lo dejó bajar», nunca la recomendada ni «por pedir».
    public var refused = false
    /// De qué complemento viene (Torrentio, Comet u otro): el ícono chico junto a la calidad.
    public var from: Streams.AddonKind = .other
    /// Qué tan rápido arranca, sin prometer de más.
    public var speed: SourceSpeed { cached ? .inRealDebrid : debrid ? .realDebridMustDownload : .unknown }
}

/// Una versión que Real-Debrid aún no tiene, con la fila de su idioma («Hay que pedirlas · tardan»).
public struct RequestableVersion: Identifiable, Equatable, Sendable {
    public var code: String
    public var option: VersionOption
    public var id: Int { option.id }
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

    public init(code: String, yours: Bool, original: Bool, options: [VersionOption]) {
        self.code = code; self.yours = yours; self.original = original; self.options = options
    }
}

extension SourcesModel {
    static let qualityOrder = ["4K", "1080p", "720p", "SD"]
    public static func quality(_ s: Source) -> String {
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
                      otherTitle: s.tags.contains(Streams.otherTitleTag) || s.tags.contains(Streams.otherEpisodeTag) || s.otherTitle,
                      otherEpisode: s.tags.contains(Streams.otherEpisodeTag), debrid: s.debrid, requested: s.requested, refused: s.refused, from: Streams.addonKind(s))
    }

    /// Lo que se puede pedir y no se ve ya como chip: una por idioma y calidad (la mejor), en el orden de la recomendación,
    /// hasta `limit`. Sin cine ni tráileres. Con Torrentio + Real-Debrid son las «[RD download]».
    /// `inCloud` (N2-A): lo que ya pediste y sigue en camino no se vuelve a ofrecer (su lugar sí cuenta, como el de un chip).
    public static func toRequest(_ ranked: [Source], shown: [LanguageRow], prefs: Preferences, limitGB: Double, limit: Int = 6,
                                 inCloud: Set<Int> = []) -> [RequestableVersion] {
        let onChips = Set(shown.flatMap { $0.options.filter { $0.speed == .realDebridMustDownload }.map(\.id) }).union(inCloud)
        var seen = Set<String>(), out: [RequestableVersion] = []
        for s in ranked where !s.cached && s.debrid && !hidden(s) && !s.refused && s.torrent != nil {
            let audio = Streams.playingLanguage(s, prefs) ?? s.audio.first
            let code = audio.map(rowCode) ?? "und"
            guard seen.insert("\(code)|\(quality(s))").inserted, !onChips.contains(s.index) else { continue }
            out.append(RequestableVersion(code: code, option: option(s, code: code, evidence: audio?.evidence ?? .maybe, limitGB: limitGB, recommended: false)))
            if out.count == limit { break }
        }
        return out
    }

    /// N2-A: marca en las filas lo que ya pediste y sigue en camino (índice de la fuente → cuánto lleva).
    static func marking(_ rows: [LanguageRow], _ inCloud: [Int: Int]) -> [LanguageRow] {
        guard !inCloud.isEmpty else { return rows }
        return rows.map { row in
            var row = row
            for i in row.options.indices where !row.options[i].cached {
                if let percent = inCloud[row.options[i].id] { row.options[i].inCloud = true; row.options[i].cloudPercent = percent }
            }
            return row
        }
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
                if audio.evidence == .original || source.originalLanguage.map({ rowCode(AudioLanguage($0, .name)) }) == code { originals.insert(code) }
            }
        }
        let want = prefs.wanted
        func row(_ code: String) -> LanguageRow {
            let byQuality = cells[code] ?? [:]
            var options: [VersionOption] = qualityOrder.compactMap { q in
                // La de otro título nunca va de primera si hay otra.
                guard let list = byQuality[q]?.sorted(by: { a, b in
                    let x = a.tags.contains(Streams.otherTitleTag) || a.tags.contains(Streams.otherEpisodeTag)
                    let y = b.tags.contains(Streams.otherTitleTag) || b.tags.contains(Streams.otherEpisodeTag)
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
        // Tu orden de idiomas (Fernando, 3 nov: latino → el original → inglés → castellano): las filas van en ese orden.
        let languageOrder = prefs.order
        func rank(_ r: LanguageRow) -> Int {
            // Con «cualquier español» las que dicen cuál van antes que la que no lo dice.
            if r.code == want, want.count > 2 || !want.hasPrefix("es") { return 0 }
            if r.yours { return r.code == "es" ? 2 : 1 }
            // El español que no dice cuál, si quieres una variante: puede ser la tuya (después de ella, antes que lo demás).
            if r.code == "es", want.hasPrefix("es") { return 2 }
            if let place = languageOrder.firstIndex(where: { $0 == "original" ? r.original : $0 == r.code }) { return 3 + place }
            if r.original { return 15 }
            if r.code.hasPrefix("es") { return 20 }   // latino, castellano y español, aunque prefieras otro idioma (como la TV)
            return 30
        }
        let count = { (r: LanguageRow) in r.options.reduce(0) { $0 + 1 + $1.others.count } }
        let sorted = rows.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : count(a.element) != count(b.element) ? count(a.element) > count(b.element) : a.offset < b.offset
        }.map(\.element)
        return (sorted.filter { rank($0) < 30 }, sorted.filter { rank($0) == 30 }, ranked.count - visible.count)
    }
}
