import Foundation
import OrbitalCore
import OrbitalAddons

public struct EpisodeRow: Equatable, Identifiable {
    public var id: String                  // el video id
    public var season: Int
    public var number: Int
    public var title: String               // en tu idioma
    public var hasTitle: Bool
    public var overview: String
    public var thumbnail: String?
    public var watched: Bool
    public var progress: Double?           // a medias
    public var timeLeft: String
    public var leftMinutes: Int
    public var download: DownloadState?
    /// Todavía no sale: cuándo (nil = ya salió o no se sabe). Se ve con su fecha y no se puede reproducir ni bajar.
    public var airs: Date? = nil
    /// El idioma del nombre o de la sinopsis cuando no es el tuyo (no había traducción): la ficha dice «En inglés».
    public var titleLanguage: String? = nil
    public var overviewLanguage: String? = nil
    /// Lo que se marca una vez en el renglón: el idioma colado del nombre o, si no, el de la sinopsis.
    public var foreignLanguage: String? { (hasTitle ? titleLanguage : nil) ?? (overview.isEmpty ? nil : overviewLanguage) }
}

/// Lo que se sabe de las fuentes del video de «Ver» antes de abrir el reproductor.
public enum SourceCheck: Equatable, Sendable { case unknown, available, none, offline }

/// La ficha de una película o serie: datos en tu idioma, temporadas y episodios con su estado (visto, a medias,
/// descargado), Mi lista (Stremio), watchlist (Trakt) y las acciones de ver y descargar.
@MainActor
public final class TitleModel: ObservableModel {
    public override var observesByProperty: Bool { true }   // V9: cada parte de la ficha se pinta con lo que lee (`@Tracked`)
    public private(set) var kind: String
    public private(set) var metaID: String
    @Tracked(always: true) public private(set) var title = ""
    @Tracked(always: true) public private(set) var originalTitle = ""
    @Tracked(always: true) public private(set) var info = MetaInfo(year: "", rating: "", genres: [], description: "", logo: nil, runtime: "")
    @Tracked(always: true) public private(set) var credits = Credits(cast: [], directors: [], writers: [], released: "", awards: "", country: "")
    @Tracked(always: true) public private(set) var poster: String? = nil
    @Tracked(always: true) public private(set) var background: String? = nil
    @Tracked(always: true) public private(set) var seasons: [Season] = []
    @Tracked public private(set) var selectedSeason = 1
    /// Ya se puso la temporada de entrada (o la elegiste tú): de aquí en adelante no salta sola.
    private var seasonSettled = false
    @Tracked(always: true) public private(set) var rows: [EpisodeRow] = []
    /// En Mi lista (el teléfono, al día con tu watchlist de Trakt).
    @Tracked(always: true) public private(set) var inLibrary = false
    /// Tus listas de Trakt y si este título está en cada una («Guardar en…»); `nil` mientras no se han pedido.
    @Tracked(always: true) public private(set) var lists: [SavedList]? = nil
    @Tracked(always: true) public private(set) var loadingLists = false
    /// ¿Está guardado en algún lado? (Mi lista, tu watchlist o una de tus listas): el botón dice «Guardado».
    public var isSaved: Bool { inLibrary || (lists.map { $0.contains(where: \.contains) } ?? inSomeList) }
    /// Está en alguna de tus listas de Trakt (sin abrir «Guardar en…»; al abrirla manda lo que diga cada lista).
    @Tracked(always: true) public private(set) var inSomeList = false
    @Tracked(always: true) public private(set) var traktAvailable = false
    /// Está en tus favoritos de Trakt (el corazón de la ficha). Va aparte de «Guardar»: no cuenta para «Guardada».
    @Tracked(always: true) public private(set) var isFavorite = false
    /// El corazón solo se enseña con Trakt conectado y un título con IMDb (Trakt no conoce los demás).
    public var canFavorite: Bool { traktAvailable && metaID.hasPrefix("tt") }
    /// Cambios del corazón que aún no contesta Trakt: una lectura que llega mientras tanto no lo regresa a como estaba.
    private var favoriteWrites = 0
    /// Cuántas veces se ha tocado «Mi lista»: una lectura de lo tuyo que salió antes de un toque trae el valor viejo y no lo
    /// pisa (al abrir la ficha llegaban los episodios de Trakt y «Mi lista» se regresaba sola).
    private var libraryEdits = 0
    @Tracked(always: true) public private(set) var isLoading = false
    @Tracked(always: true) public private(set) var error: String? = nil
    @Tracked(always: true) public private(set) var message: String? = nil
    /// La sinopsis que dio tu Orbital (en español cuando puede) y si su logo es oscuro (se pinta blanco); nil si no hay consola.
    @Tracked(always: true) public private(set) var consoleOverview: String? = nil
    /// La ficha rica de TMDB (elenco con foto, saga, tráiler…); nil sin clave de TMDB o mientras llega.
    @Tracked(always: true) public private(set) var extras: TitleExtras? = nil
    /// «Lo mejor disponible» entre las fuentes del episodio o película que toca (como el encabezado de Infuse).
    /// Lo mejor que hay (para «Disponible: 4K · Dolby Vision» en los detalles).
    @Tracked(always: true) public private(set) var bestSource: Source? = nil
    /// La que va a sonar al tocar «Ver»: la recomendada (idioma, calidad y tamaño; la primera de «Elegir la fuente»). Su
    /// calidad es la que dice el botón (antes decía la mejor, 4K, y luego sonaba la recomendada en 1080p).
    @Tracked(always: true) public private(set) var recommendedSource: Source? = nil
    /// En qué idioma va a sonar la recomendada («es-419»): «Ver» dice «Latino · 1080p» (nada a escondidas).
    @Tracked(always: true) public private(set) var recommendedLanguage: String? = nil
    /// N5-A: la de un idioma que va antes en tu orden y no ganó «Ver» porque aquí no se ve bien (la ficha lo dice en una línea).
    @Tracked public private(set) var poorFit: PoorFit? = nil
    /// Si ya se sabe que no hay fuentes (o no hay red), «Ver» lo dice en vez de abrir un reproductor que va a fallar.
    @Tracked(always: true) public internal(set) var sourceCheck: SourceCheck = .unknown
    /// Por qué no hay qué ver, si se sabe algo mejor que «no hay» (D5): «Tu Real-Debrid venció» con «Renovar», «No tienes
    /// complementos prendidos»…; nil si hay versiones o no se sabe.
    @Tracked public internal(set) var unavailableCause: UnavailableCause? = nil
    /// «Pedirlo y avisarme» (R2-A, R4): la versión que existe pero Real-Debrid todavía no tiene, lista para pedir; nil si la
    /// recomendada arranca al instante, si no hay qué pedir o sin clave de Real-Debrid.
    @Tracked public internal(set) var debridOffer: DebridOffer? = nil
    /// FQ1-A (Fernando, 3 nov): «Ver» arranca ya en otro idioma de tu orden y el tuyo existe pero hay que pedirlo: al lado,
    /// «Pedir a la nube en latino» con esta versión.
    @Tracked public internal(set) var wantedOffer: DebridOffer? = nil
    /// La calificación de Trakt (0–10), si alguien votó.
    @Tracked(always: true) public private(set) var traktRating: Double? = nil

    let services: Services
    /// Si Torrentio sin Real-Debrid contestó que no hay ningún torrent (por título): la causa 11.
    @Tracked var lookupEmpty: [String: Bool] = [:]
    /// Las huellas que Torrentio dio para cada video (la última búsqueda): un paquete pedido desde otro episodio las comparte.
    @Tracked var listedHashes: [String: Set<String>] = [:]
    @Tracked private(set) var meta: JSON? = nil           // la ficha ORIGINAL
    @Tracked private var localized: JSON? = nil
    /// Lo tuyo de este título en el teléfono (dónde ibas, lo visto, Mi lista).
    @Tracked private var entry: LibraryEntry? = nil
    @Tracked private(set) var watched = Set<String>()   // lo visto (ids de video); lo lee «¿Cuándo la viste?» (TitleModel+Watched)
    @Tracked private var downloadStates: [String: DownloadState] = [:]
    @Tracked private var downloadProgress: [String: Double] = [:]
    /// Cómo va la descarga de un video de este título (nil: no se ha pedido).
    public func downloadState(_ videoID: String?) -> DownloadState? { videoID.flatMap { downloadStates[$0] } }
    /// Cuánto lleva (0…1) una descarga en curso de este título.
    public func downloadFraction(_ videoID: String?) -> Double? { videoID.flatMap { downloadProgress[$0] } }

    /// Mientras la ficha está abierta: cada cambio de las descargas (avance, terminó, falló) se ve al momento.
    public func followDownloads() async {
        for await items in services.downloads.makeUpdates() { applyDownloads(items) }
    }

    private func applyDownloads(_ items: [DownloadItem]) {
        // Puede haber dos versiones del mismo video («Bajar también esta»): por video se enseña la que más importa (la que
        // está bajando antes que la terminada). Antes se armaba con claves únicas y con dos versiones la app se cerraba.
        var chosen: [String: DownloadItem] = [:]
        for item in items where item.metaID == metaID {
            if let current = chosen[item.videoID], Self.rank(current.state) <= Self.rank(item.state) { continue }
            chosen[item.videoID] = item
        }
        let states = chosen.mapValues(\.state)
        let progress = chosen.compactMapValues(\.progress)
        guard states != downloadStates || progress != downloadProgress else { return }
        let stateChanged = states != downloadStates
        downloadStates = states; downloadProgress = progress
        if stateChanged { buildRows() }   // el avance solo: ya avisó `downloadProgress` (V9)
    }

    /// Qué versión de un video se enseña en la ficha: la que bajando, luego en cola, en pausa, lista y, al final, la fallida.
    static func rank(_ state: DownloadState) -> Int {
        switch state {
        case .downloading: 0
        case .queued: 1
        case .paused: 2
        case .done: 3
        case .failed: 4
        }
    }

    public init(_ services: Services, kind: String, metaID: String, hint: (title: String, poster: String?)? = nil) {
        self.services = services; self.kind = kind; self.metaID = metaID
        super.init()
        // El título que se muestra puede venir traducido: el ORIGINAL (lo que se guarda en Stremio) solo sale de Cinemeta, al cargar.
        if let hint { title = hint.title; poster = hint.poster }
        // Si Trakt está conectado se sabe ya (sin red): «Guardar» va a tu watchlist desde el primer toque, no a Mi lista
        // mientras llega `refreshState`.
        traktAvailable = services.trakt?.linked ?? false
        // El fondo de metahub se conoce por el id: el arte empieza a bajar al abrir, no después de Cinemeta y la traducción
        // (3 a 5 viajes de red en una serie). Si Cinemeta trae otro, se cambia al llegar.
        if metaID.hasPrefix("tt") { background = String(format: ForYou.metahubBackground, metaID) }
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        // Lo tuyo en Stremio (avance, vistos) se pide a la vez que la ficha: no espera a Cinemeta ni a la traducción.
        let watch = services.watch, id = metaID
        let state = Task { await watch.entry(metaID: id) }
        // Los complementos, a la vez que la ficha y lo tuyo: las fuentes ya no esperan a `addonCollectionGet` al final.
        let finder = services.finder
        Task { await finder.warmAddons() }
        // Las fuentes, en cuanto se sabe qué video toca (película: ya; serie: con lo tuyo o la ficha): no esperan a la traducción
        // ni al resto de la ficha. `loadBestSource` luego se une a esta misma petición (o la encuentra ya guardada).
        let cinemeta = services.cinemeta, introDB = services.introDB, kind = kind
        Task {
            // Película: el video es ella misma (salvo un `video_id` raro guardado), así que no espera a lo tuyo. Serie: el
            // episodio sale de lo tuyo y adivinarlo sería pedir fuentes de otro episodio.
            if kind == "movie" { Task { await finder.warm(kind: kind, videoID: id) } }
            let mine = await state.value
            var video = Self.continueVideoID(kind: kind, metaID: id, entry: mine, seasons: [])
            if video == nil, let meta = try? await cinemeta.meta(kind: kind, id: id) {
                video = Self.continueVideoID(kind: kind, metaID: id, entry: mine, seasons: CinemetaParsing.seasons(meta))
            }
            if let video { introDB.warm(videoID: video); await finder.warm(kind: kind, videoID: video) }   // «Saltar intro» listo al reproducir
        }
        do {
            let original = try await services.cinemeta.meta(kind: kind, id: metaID)
            meta = original
            // Arte y póster en cuanto llega Cinemeta; el texto traducido llega después.
            poster = CinemetaParsing.medium(original["poster"]?.string) ?? poster
            // Si Cinemeta no trae fondo, tampoco hay en metahub: se cae al póster (no a un hueco).
            if let art = original["background"]?.string, !art.isEmpty { background = art } else { background = nil }
            let local = await services.localizer.meta(kind: kind, meta: original)
            localized = local
            title = local["name"]?.string ?? original["name"]?.string ?? title
            originalTitle = original["name"]?.string ?? title
            if local["name"]?.string != original["name"]?.string { services.titleNames.remember(id: metaID, name: title) }
            info = CinemetaParsing.describe(local)
            credits = CinemetaParsing.credits(local)
            seasons = CinemetaParsing.seasons(local)
            error = nil
        } catch where !Task.isCancelled {
            // Con internet no se culpa a la conexión: es Cinemeta (de donde sale la ficha) el que no contestó.
            self.error = services.isOnline() ? "No pude cargar la ficha: el servicio de las fichas no contesta. Intenta en un rato." : "No pude cargar la ficha. Revisa tu conexión."
        } catch {}   // cancelado al salir: sin error falso
        await refreshState(prefetched: await state.value)
        // Los episodios que viste en otro aparato (Trakt), aunque la serie no esté entre las recientes: llegan y se repinta.
        if kind == "series", metaID.hasPrefix("tt"), services.trakt?.linked == true {
            let sync = services.sync, id = metaID, name = originalTitle
            Task { [weak self] in await sync.pullShow(imdb: id, name: name); await self?.refreshState() }
        }
    }

    /// El logo; nil (va el nombre) si está hecho en tu idioma: el de metahub dice «Even the Wind Is Afraid» (Fernando, 3 nov).
    public var logo: String? { localized?[Localizer.nativeKey]?.bool == true ? nil : info.logo ?? Artwork.logoURL(metaID: metaID) }

    /// La sinopsis de la ficha: la que el iPhone tradujo con TMDB (en el idioma de la app); la de tu Orbital solo si aquí no
    /// hay clave de TMDB; si no, la de Cinemeta de siempre. Antes la de la consola ganaba siempre (y siempre en español).
    public var overview: String { services.tmdb.configured ? info.description : consoleOverview ?? info.description }

    /// Pide a tu Orbital la sinopsis y el tipo de logo (`/api/foryou/details`). Sin consola o sin respuesta no cambia nada.
    /// Lo de la ficha rica: TMDB (elenco, saga, tráiler…; la clasificación en la escala de `uiLanguage`) y la de Trakt, a la vez.
    public func loadExtras() async {
        guard metaID.hasPrefix("tt") else { return }
        let tmdb = services.tmdb, trakt = services.trakt, kind = kind, metaID = metaID, region = services.appSettings.region, language = services.appSettings.uiLanguage
        // La calificación de Trakt: la misma que ya se enseñó en Inicio o en una lista (`TraktRatings`); solo se pide si no hay.
        let known = TraktRatings.known(metaID)
        if let known { traktRating = known }
        async let rating = known == nil ? try? trakt?.rating(kind: kind, imdb: metaID) : nil
        if tmdb.configured, let id = try? await tmdb.findID(imdb: metaID, kind: kind) {
            extras = try? await tmdb.extras(kind: kind, tmdbID: id, region: region, metadataLanguage: language)
        }
        if known == nil { traktRating = TraktRatings.note(metaID, await rating?.rating) }
    }

    /// Busca las fuentes del video que toca (el mismo pedido que «Elegir fuente», así luego sale de la caché) y se queda con
    /// la mejor para el encabezado. Sin fuentes o sin red, no se enseña nada.
    public func loadBestSource(onCellular: Bool = false) async {
        guard let videoID = continueVideoID else { return }
        let prefs = services.titlePrefs.languages(for: metaID, settings: services.appSettings, onCellular: onCellular).prefs
        do {
            await services.freshenDebrid()   // RC1: con código, la llave al día antes de pedir versiones
            let found = try await services.finder.find(kind: kind, videoID: videoID, prefs: prefs, purpose: .watch)
            guard !Task.isCancelled else { return }
            listedHashes[videoID] = Set(found.compactMap { $0.torrent?.hash })
            // La veías en otro idioma (inglés): ese dice qué va a sonar y si te queda, no el de Ajustes (Fernando, 6 nov).
            var prefs = prefs
            if let heard = PlaybackRules.languageCode(services.titlePrefs.resumeChoice(metaID: metaID, videoID: videoID)?.audio?.language), !heard.isEmpty { prefs.audio = heard }
            // Todo lo de «Ver» de una vez: un solo repintado de la ficha, no uno por campo (tirones al desplazarte).
            coalescing {
                bestSource = Source.best(found)
                // «Ver» dice lo que de verdad va a sonar: la versión con que lo dejaste (ese video), o la de su misma familia en el
                // siguiente episodio; si no, la recomendada (lo mismo que elige el reproductor).
                let resume = services.titlePrefs.resumeChoice(metaID: metaID, videoID: videoID)?.source
                let family = services.titlePrefs.lastChoice(metaID: metaID)?.binge
                recommendedSource = SourcesModel.toPlay(found, resume: resume, family: family)
                recommendedLanguage = recommendedSource.flatMap { Streams.playingLanguage($0, prefs)?.code }
                if let ready = recommendedSource, ready.instant, let url = ready.playbackURL { StreamWarmup.warm(url, parallel: ready.resolution == "4K") }   // ST5
                poorFit = recommendedSource.flatMap { Streams.poorFit(found, playing: $0, prefs: prefs, kind: kind) }
                sourceCheck = !found.isEmpty ? .available : services.isOnline() ? .none : .offline   // sin red, «no hay» no es cierto
            }
            // Lo que falta se pide (R4): si la recomendada no arranca al instante (o no hay ninguna), qué torrent existe.
            let wanted = recommendedSource.map { !$0.instant } ?? true
            var offer = wanted && sourceCheck != .offline ? await offerToRequest(videoID: videoID, prefs: prefs, found: found) : nil
            guard !Task.isCancelled else { return }
            let why = sourceCheck == .none ? await cause(videoID: videoID, language: prefs.wanted, offer: offer) : nil
            // Con tu cuenta vencida, sin Premium o con la clave vieja no se puede pedir nada: la salida es esa («Renovar»), no
            // «Pedirlo y avisarme» (que fallaría). Análisis de fondo con la TV, 3 nov.
            if let why, why.blocksRequests { offer = nil }
            let aside = await wantedAside(videoID: videoID, prefs: prefs, found: found)
            coalescing { debridOffer = offer; wantedOffer = aside; unavailableCause = why }
        } catch {
            // Sin red puede fallar antes de preguntarle a los complementos (al leer cuáles tienes): también es «sin conexión»
            // (antes se quedaba «Buscando versión…» para siempre).
            if !Task.isCancelled { sourceCheck = error is StreamFinderError || Degraded.isOffline(error) || !services.isOnline() ? .offline : .unknown }
            // Hay internet y ningún complemento contestó: son ellos (la causa 8), no tu conexión. Si falló otra cosa (leer tus
            // complementos), no se pudo ni buscar (la causa 3), con el error en palabras.
            if sourceCheck == .offline && services.isOnline() { unavailableCause = UnavailableCause.addonsOffline.shown(instant: offersInstant) }
            else if sourceCheck == .unknown && services.isOnline() && !Task.isCancelled {
                unavailableCause = .cannotSearch(reason: UserMessages.humanize(String(describing: error))); sourceCheck = .none
            } else { unavailableCause = nil }
        }
    }

    /// Un título de TMDB (recomendación, saga, filmografía) → su id de IMDb, para abrir su ficha.
    public static func imdbID(of title: TmdbTitle, services: Services) async -> String? {
        try? await services.tmdb.details(kind: title.kind, tmdbID: title.tmdbID, urgent: true).imdb
    }

    /// «4 de 10 vistos» de la temporada elegida.
    public var seasonProgress: (watched: Int, total: Int) { (rows.filter(\.watched).count, rows.count) }

    /// Respaldo sin clave de TMDB en el iPhone: la sinopsis en español que calcula tu Orbital. Con clave, el iPhone no le
    /// pregunta nada a la consola (el tono del logo lo mide `LogoTone` aquí mismo).
    public func loadConsoleDetails() async {
        let remote = services.orbital
        guard !services.tmdb.configured, remote.isConfigured, metaID.hasPrefix("tt") else { return }
        guard let json = try? await remote.foryouDetails(key: "video:\(metaID)", kind: kind) else { return }
        if let text = json["overview"]?.nonEmptyString?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { consoleOverview = text }
    }

    /// Lo que cambia viendo, descargando o marcando: lo tuyo en el teléfono, Trakt y las descargas.
    public func refreshState() async { await refreshState(prefetched: nil) }

    /// Lo tuyo en el teléfono, Trakt y las descargas: las consultas a la vez.
    private func refreshState(prefetched: LibraryEntry?? = nil) async {
        let forYou = services.forYou, downloads = services.downloads, watch = services.watch, id = metaID
        async let linked = forYou.traktLinked
        async let listed = forYou.listKeys()
        async let favorites = forYou.favoriteKeys()
        async let queue = downloads.all
        let edits = libraryEdits
        if let prefetched { entry = prefetched } else { entry = await watch.entry(metaID: id) }
        watched = entry?.seen ?? []
        if edits == libraryEdits { inLibrary = entry?.inList ?? false }
        traktAvailable = await linked
        inSomeList = await listed.contains(metaID)
        let onTraktFavorites = await favorites.contains(metaID)
        let favorite = services.traktOutbox.pending(target: TraktOutbox.favorites, imdb: metaID) ?? onTraktFavorites
        if favoriteWrites == 0 { isFavorite = favorite }
        applyDownloads(await queue)
        settleSeason()
        buildRows()
    }

    /// La temporada salta sola solo al abrir la ficha; luego manda la tuya (Fernando, 9 nov: volver de ver la cambiaba).
    private func settleSeason() {
        guard !seasons.isEmpty else { return }
        if !seasonSettled, let state = entry?.videoID, kind == "series", let season = seasons.first(where: { $0.episodes.contains { $0.id == state } }) {
            selectedSeason = season.season
        } else if !seasons.contains(where: { $0.season == selectedSeason }) {
            selectedSeason = seasons.first { !$0.isSpecials }?.season ?? seasons.first?.season ?? 1
        }
        seasonSettled = true
    }

    public func select(season: Int) { seasonSettled = true; selectedSeason = season; buildRows() }

    private func buildRows() {
        let current = entry?.nextUp == false ? entry?.videoID : nil
        let progress = entry?.progress, left = max(0, (entry?.duration ?? 0) - (entry?.position ?? 0))
        rows = (seasons.first { $0.season == selectedSeason }?.episodes ?? []).map { ep in
            let ongoing = ep.id == current && progress != nil && (entry?.duration ?? 0) > 0
            let seasonNumber = selectedSeason
            return EpisodeRow(id: ep.id, season: seasonNumber, number: ep.episode, title: ep.title, hasTitle: ep.hasTitle, overview: ep.overview, thumbnail: ep.thumbnail,
                              watched: watched.contains(ep.id), progress: ongoing ? progress : nil,
                              timeLeft: ongoing ? PlaybackRules.timeLeft(left) : "",
                              leftMinutes: ongoing ? PlaybackRules.minutesLeft(left) : 0, download: downloadStates[ep.id],
                              airs: Self.airDate(ep.released, now: services.now()), titleLanguage: ep.titleLanguage, overviewLanguage: ep.overviewLanguage)
        }
    }

    // MARK: ver
    /// El video con el que sigue el botón principal: donde ibas, o el primer episodio.
    public var continueVideoID: String? { Self.continueVideoID(kind: kind, metaID: metaID, entry: entry, seasons: seasons) }

    /// La misma cuenta sin abrir la ficha (lo usa «¿Qué vemos?» para que «Ver» ponga el capítulo en que vas): con lo tuyo en
    /// el teléfono (`entry`) y las temporadas de Cinemeta.
    nonisolated public static func continueVideoID(kind: String, metaID: String, entry: LibraryEntry?, seasons: [Season]) -> String? {
        if let video = entry?.videoID, !video.isEmpty, (entry?.position ?? 0) > 0 || kind == "series" {
            // Ibas al día y terminaste el último que había: «Ver» pone ese (no hay siguiente todavía).
            return video
        }
        if kind == "movie" { return metaID }
        return seasons.first { !$0.isSpecials }?.episodes.first?.id
    }

    /// «Continuar T2 E5» / «Reproducir» / «Reproducir T1 E1».
    public var continueLabel: (isResume: Bool, season: Int?, episode: Int?) {
        guard let video = continueVideoID else { return (false, nil, nil) }
        let resume = entry?.videoID == video && entry?.nextUp == false && (entry?.position ?? 0) > 1
        if kind == "series" {
            let numbers = LibraryRules.episodeNumbers(videoID: video, metaID: metaID)
            if let s = numbers.season, let e = numbers.episode { return (resume, s, e) }
        }
        return (resume, nil, nil)
    }

    /// Minutos para acabar lo que pone el botón principal: lo que falta si vas a medias, si no la duración (de la película o
    /// del episodio típico de la serie). nil si no se sabe. Con esto la ficha dice «terminas a las 23:21».
    public var minutesToFinish: Int? {
        guard continueVideoID != nil else { return nil }
        let duration = entry?.duration ?? 0, offset = entry?.position ?? 0
        if continueLabel.isResume, duration > offset, offset > 0 { return max(1, PlaybackRules.minutesLeft(duration - offset)) }
        let runtime = Int(CinemetaParsing.runtimeSeconds(info.runtime) / 60)
        return runtime > 0 ? runtime : nil
    }

    /// Cuánto llevas visto de lo que pone el botón principal (0…1); nil si no ibas a medias.
    public var resumeFraction: Double? {
        guard continueLabel.isResume else { return nil }
        return entry?.progress
    }

    public func playRequest(videoID: String? = nil, fromStart: Bool = false) -> PlayRequest? {
        guard let video = videoID ?? continueVideoID else { return nil }
        var label = ""
        if kind == "series", let found = episode(video) { label = services.episodeLabel(found.0, found.1.episode) + (found.1.hasTitle ? " · \(found.1.title)" : "") }
        return PlayRequest(kind: kind, metaID: metaID, videoID: video, originalTitle: originalTitle, displayTitle: title, episodeLabel: label,
                           poster: poster, year: info.year, meta: meta, fromStart: fromStart)
    }

    // MARK: Mi lista
    /// Adónde va «Guardar» sin elegir: Mi lista (el teléfono y tu watchlist de Trakt).
    public var saveDestination: SaveDestination { .preferred(traktLinked: traktAvailable, metaID: metaID) }
    /// Las fijas de «Guardar en…» y del menú de «Guardar».
    public var fixedDestinations: [SaveDestination] { SaveDestination.fixed(traktLinked: traktAvailable, metaID: metaID) }
    /// Qué hace un toque en «Guardar».
    public var quickSave: QuickSave {
        QuickSave.decide(inList: inLibrary, inOtherLists: lists.map { $0.contains(where: \.contains) } ?? inSomeList)
    }

    public func isSaved(in destination: SaveDestination) -> Bool { inLibrary }

    public func toggle(_ destination: SaveDestination) async { await toggleLibrary() }

    /// Mi lista: cambia aquí al instante y viaja a tu watchlist de Trakt (sin conexión, en cuanto haya).
    public func toggleLibrary() async {
        let target = !inLibrary
        libraryEdits += 1
        inLibrary = target
        await services.watch.setInLibrary(kind: kind, metaID: metaID, title: originalTitle, poster: poster, add: target, outbox: services.traktOutbox)
        await services.forYou.clearCache(["trakt:watchlist"])   // solo la watchlist: lo demás de Para ti sigue válido
    }

    // MARK: favoritos de Trakt
    /// El corazón: lo cambia al instante y lo manda a Trakt. Sin conexión se queda guardado en el iPhone y llega a Trakt en
    /// cuanto se pueda (como la watchlist); si Trakt no lo acepta (ya tienes 100) regresa a como estaba y la ficha dice por qué.
    /// Inicio se entera al momento (`FavoriteChange`). Devuelve si quedó como pediste (para ofrecer «Deshacer»).
    @discardableResult
    public func toggleFavorite() async -> Bool {
        guard let trakt = services.trakt, trakt.linked, metaID.hasPrefix("tt") else { return false }
        let want = !isFavorite
        isFavorite = want
        favoriteWrites += 1
        defer { favoriteWrites -= 1 }
        do {
            try await trakt.setFavorite(imdb: metaID, series: kind == "series", add: want)
            // Sin borrar la caché de Para ti: los favoritos no se guardan ahí (los recuerda `Trakt`, con `last_activities`).
        } catch where TraktOutbox.retryable(error) {
            services.traktOutbox.enqueue(.init(target: TraktOutbox.favorites, imdb: metaID, series: kind == "series", add: want))
            message = "Guardado en el iPhone: llega a Trakt en cuanto haya conexión."
        } catch {
            isFavorite = !want
            message = Self.favoriteFailure(error)
            return false
        }
        FavoriteChange.post(Suggestion(kind: kind, imdb: metaID, title: title, poster: poster ?? String(format: ForYou.metahubPoster, metaID),
                                       wide: background ?? "", reason: .inList(ForYou.favoritesName)), add: want)
        return true
    }

    /// Lo que dice la ficha si el corazón no se pudo cambiar: el tope de 100 tal cual (ya dice qué hacer); lo demás, con su causa.
    nonisolated static func favoriteFailure(_ error: Error) -> String {
        if case TraktError.invalid(let text)? = error as? TraktError { return text }
        return "No pude cambiar tus favoritos de Trakt: \(error)"
    }

    // MARK: tus listas de Trakt
    /// Tus listas y en cuáles está este título (una consulta por lista: suelen ser pocas).
    public func loadLists() async {
        guard let trakt = services.trakt, trakt.linked, metaID.hasPrefix("tt") else { lists = []; return }
        loadingLists = true
        defer { loadingLists = false }
        // Sin conexión: las listas que ya conocías (y lo pendiente encima), para poder elegir igual.
        let outbox = services.traktOutbox
        guard let all = try? await trakt.ownLists() else {
            // Se recuerdan ya ordenadas (recientes primero): sin conexión salen en el mismo orden que la última vez.
            let id = metaID
            lists = outbox.cachedLists.map { SavedList(id: $0.id, name: $0.name, contains: outbox.pending(target: $0.id, imdb: id) ?? false) }
            return
        }
        let id = metaID
        let found = await withTaskGroup(of: (Int, SavedList).self) { group in
            for (i, l) in all.enumerated() {
                group.addTask { (i, SavedList(id: l.id, name: l.name, contains: ((try? await trakt.listMembers(l.id)) ?? []).contains(id), updatedAt: l.updatedAt)) }
            }
            var out: [(Int, SavedList)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let ordered = SaveSheetPlan.order(found)
        outbox.remember(lists: ordered.map { ($0.id, $0.name) })
        lists = ordered
    }

    /// Cuántas listas esperar en «Guardar en…» antes de que lleguen (las de la última vez): sus esqueletos apartan su lugar.
    public var expectedListCount: Int { lists?.count ?? services.traktOutbox.cachedLists.count }

    public func toggleList(_ listID: String) async {
        guard let trakt = services.trakt, var all = lists, let i = all.firstIndex(where: { $0.id == listID }) else { return }
        let want = !all[i].contains
        all[i].contains = want
        lists = all
        do {
            try await trakt.setListItem(listID: listID, imdb: metaID, series: kind == "series", add: want)
            await services.forYou.clearCache(["trakt:list:\(listID)", "trakt:listkeys"])   // solo esa lista (y «Guardado» de las fichas)
        } catch where TraktOutbox.retryable(error) {
            services.traktOutbox.enqueue(.init(target: listID, imdb: metaID, series: kind == "series", add: want))
            message = "Guardado en el iPhone: llega a Trakt en cuanto haya conexión."
        } catch {
            if var back = lists, let j = back.firstIndex(where: { $0.id == listID }) { back[j].contains = !want; lists = back }
            message = "No pude cambiar tu lista de Trakt: \(error)"
        }
    }

    /// Una lista nueva en Trakt, ya con este título.
    public func createList(named name: String) async {
        guard let trakt = services.trakt, trakt.linked else { return }
        do {
            let made = try await trakt.createList(name: name)
            // Recién hecha: va arriba de tus listas (las fijas, abajo, no se mueven).
            lists = SaveSheetPlan.order((lists ?? []) + [SavedList(id: made.id, name: made.name, contains: false, updatedAt: Date())])
            await toggleList(made.id)
        } catch { message = "No pude crear la lista: \(error)" }
    }

    /// Marca un episodio (o la película) como visto: en el teléfono al instante y en Trakt (y la copia a Stremio). Marcar un
    /// episodio anterior no mueve tu punto de «Seguir viendo».
    public func markWatched(_ videoID: String) async {
        await services.watch.markWatched(kind: kind, metaID: metaID, videoID: videoID, name: originalTitle)
        await refreshState()
    }

    /// «Marcar como no visto»: sale de lo visto aquí y en Trakt.
    public func unmarkWatched(_ videoID: String) async {
        await services.watch.unmarkWatched(kind: kind, metaID: metaID, videoID: videoID)
        await refreshState()
    }

    // MARK: descargar
    public enum DownloadOutcome: Equatable { case queued(Int), noSources, notEnoughSpace(String), already, failed(String) }

    /// Descarga uno o varios episodios con la fuente que mejor sirve para guardar (1080p, moderada).
    @discardableResult
    public func download(_ videoIDs: [String], source: Source? = nil, replace: Bool = false, keepBoth: Bool = false) async -> DownloadOutcome {
        var queued = 0
        for video in videoIDs {
            var label = ""
            if let found = episode(video) { label = services.episodeLabel(found.0, found.1.episode) + (found.1.hasTitle ? " · \(found.1.title)" : "") }
            switch await services.queueDownload(kind: kind, metaID: metaID, videoID: video, title: title, originalTitle: originalTitle, subtitle: label, poster: poster, source: source, replace: replace, keepBoth: keepBoth) {
            case .queued: queued += 1
            case .noSources: if queued == 0 { return .noSources } else { continue }
            case .already: if videoIDs.count == 1 { return .already } else { continue }
            case .notEnoughSpace(let message): return .notEnoughSpace(message)
            case .failed(let message): return .failed(message)
            }
        }
        await refreshState()
        return queued > 0 ? .queued(queued) : .noSources
    }

    /// «Descargar los siguientes N episodios».
    public func downloadNext(_ count: Int) async -> DownloadOutcome {
        let from = continueVideoID
        let ids = seasons.filter { !$0.isSpecials }.flatMap { $0.episodes.map(\.id) }
        guard let from, let i = ids.firstIndex(of: from) else { return .noSources }
        return await download(Array(ids.dropFirst(i).prefix(count)))
    }

    /// Seguir una descarga en pausa o que falló (donde iba, con la misma fuente), en vez de empezarla de cero.
    public func resumeDownload(_ videoID: String) async {
        await services.downloads.resume(DownloadItem.makeID(metaID: metaID, videoID: videoID))
        await refreshState()
    }

    /// Pausar o cancelar (borrar lo bajado) una descarga de este título.
    public func pauseDownload(_ videoID: String) async {
        await services.downloads.pause(DownloadItem.makeID(metaID: metaID, videoID: videoID))
        await refreshState()
    }

    public func cancelDownload(_ videoID: String) async {
        await services.downloads.remove(DownloadItem.makeID(metaID: metaID, videoID: videoID))
        await refreshState()
    }

    /// «T2 E5» de un episodio de esta serie; nil en una película.
    public func episodeLabel(_ videoID: String) -> String? {
        guard kind == "series", let found = episode(videoID) else { return nil }
        return services.episodeLabel(found.0, found.1.episode)
    }

    /// El video que bajaría «Descargar» de un toque: la película, o el episodio que sigue en una serie.
    public var downloadTarget: String? { kind == "movie" ? metaID : continueVideoID }

    /// La copia que ya tienes (o se está bajando) de este video, para preguntar antes de cambiarla por otra fuente.
    public func existingDownload(_ videoID: String) async -> DownloadItem? { await services.downloads.item(DownloadItem.makeID(metaID: metaID, videoID: videoID)) }

}

/// Una de tus listas de Trakt, con si el título que ves está en ella.
public struct SavedList: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var contains: Bool
    /// Cuándo cambió en Trakt (las recientes van arriba en «Guardar en…»); nil sin conexión o si Trakt no lo dijo.
    public var updatedAt: Date? = nil

    public init(id: String, name: String, contains: Bool, updatedAt: Date? = nil) {
        self.id = id; self.name = name; self.contains = contains; self.updatedAt = updatedAt
    }
}
