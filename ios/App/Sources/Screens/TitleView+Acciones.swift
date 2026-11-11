import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons

/// Lo que hace la ficha al tocar: ver, guardar, descargar, en la TV y los avisos que dejan.
extension TitleView {
    // MARK: acciones
    /// «Ver»: si ya se sabe que no hay fuentes (o no hay red), lo dice aquí en vez de abrir un reproductor que va a fallar.
    func play(_ model: TitleModel) {
        switch model.sourceCheck {
        case .none, .offline:
            // Qué decir lo decide el modelo (`playFallback`), con la tabla común con la TV y lo que trae esta versión (D1-B).
            switch model.playFallback(online: env.isOnline) {
            case .cause(let cause): tell(cause, model)
            case .story(let id): env.ui.openStory = id
            case .noInternet:
                env.notify("Sin internet", detail: "No pude buscar dónde verlo", tone: .warn, actionTitle: "Reintentar") { start(model, videoID: nil) }
            }
        default: start(model, videoID: nil)
        }
    }

    /// Una causa en un aviso: su título, su renglón y su única salida.
    func tell(_ cause: UnavailableCause, _ model: TitleModel) {
        let ui = env.services.appSettings.uiLanguage, tr = { (key: String) in Strings.tr(key, language: ui) }
        let detail = cause.detail(tr, languageName: { Streams.versionLanguageName($0, in: ui).lowercased() })
        let title = cause.title(tr)
        guard let action = cause.action else { return env.notify(title, detail: detail, tone: .warn) }
        let label = UnavailableCause.label(action, tr)
        switch action {
        case .renew:
            let renew = env.services.debrid.provider.renewURL
            env.notify(title, detail: detail, tone: .warn, actionTitle: label) { UIApplication.shared.open(renew) }   // en el navegador
        case .settings: env.notify(title, detail: detail, tone: .warn, actionTitle: label) { env.ui.openSettings = true }
        case .retry: env.notify(title, detail: detail, tone: .warn, actionTitle: label) { start(model, videoID: nil) }   // el reproductor vuelve a preguntar
        case .otherVersion: env.notify(title, detail: detail, tone: .warn)
        // «Pedirlo y avisarme» (R2-A): solo si hay qué pedir; si no, la causa sola.
        case .request:
            if env.services.debridRequests.canRequest { env.notify(title, detail: detail, tone: .warn, actionTitle: label) { requestFromDebrid(model) } }
            else { env.notify(title, detail: detail, tone: .warn) }
        }
    }

    func start(_ model: TitleModel, videoID: String?, source: Source? = nil, fromStart: Bool = false) {
        guard var request = model.playRequest(videoID: videoID) else { return }
        request.sourceIndex = source?.index
        request.fromStart = fromStart
        launch(request, source: source)
    }

    /// Tocar un episodio de la lista: igual visto que sin ver, reproduce (uno visto, desde el inicio); la versión va en «⋯».
    func startEpisode(_ model: TitleModel, videoID: String) {
        guard let request = model.episodeRequest(videoID) else { return }
        launch(request, source: nil)
    }

    /// EV1 (Fernando, 9 nov): uno sin ver empieza; uno visto pregunta «Ya lo viste» (ver otra vez, otra versión, no visto).
    func tapEpisode(_ model: TitleModel, _ row: EpisodeRow) {
        if row.watched { rewatch = row } else { startEpisode(model, videoID: row.id) }
    }

    /// La versión de la serie para «Ver otra vez» (la bandera y el idioma; «Español» si no dice cuál).
    func rewatchVersion(_ model: TitleModel) -> String {
        let wanted = env.services.titlePrefs.languages(for: model.metaID, settings: env.services.appSettings).prefs.wanted
        let ui = env.services.appSettings.uiLanguage
        return "\(LanguageFlags.flag(wanted) ?? "") \(wanted == "es" ? Strings.tr("Español", language: ui) : Streams.versionLanguageName(wanted, in: ui))"
    }

    private func launch(_ request: PlayRequest, source: Source?) {
        if env.services.appSettings.preferInfuse { Task { await env.playExternal(request, source: source) } }
        else { env.ui.playerSource = PlayerZoomID(metaID: request.metaID, slot: "title"); env.play(request) }
    }

    func handle(source: Source, videoID: String, purpose: Purpose, model: TitleModel) {
        switch purpose {
        case .watch: start(model, videoID: videoID, source: source)
        case .download:
            // Ya hay una copia (o se está bajando): una sola por película o episodio, así que se pregunta si cambiarla.
            Task {
                if let existing = await model.existingDownload(videoID) { replacing = Replacement(source: source, videoID: videoID, existing: existing); return }
                await report(model.download([videoID], source: source), model, videoID: videoID)   // la fuente que elegiste
            }
        }
    }

    /// «4K · Dolby Vision» y «12,3 GB · Torrentio» (o «Bajando 40 % · Torrentio») para la hoja «Ya la tienes».
    func describe(_ item: DownloadItem) -> (label: String, detail: Text) {
        let size = item.expectedBytes.map { ByteSize.text($0, locale: env.uiLocale) } ?? ""
        let tail = item.addon.isEmpty ? "" : " · \(item.addon)"
        if item.state != .done, let expected = item.expectedBytes, expected > 0 {
            let percent = "\(Int(Double(item.writtenBytes) / Double(expected) * 100)) %"
            return (item.quality ?? item.addon, Text("\(Text("Bajando \(percent)"))\(Text(verbatim: tail))"))
        }
        return (item.quality ?? item.addon, Text(verbatim: size + tail))
    }

    func describe(_ source: Source) -> (label: String, detail: Text) {
        let label = ([source.resolution] + source.hdr).filter { !$0.isEmpty }.joined(separator: " · ")
        let size = source.size > 0 ? ByteSize.text(Int64(source.size), locale: env.uiLocale) : nil
        return (label.isEmpty ? source.addon : label, Text(verbatim: [size, source.addon.isEmpty ? nil : source.addon].compactMap { $0 }.joined(separator: " · ")))
    }

    func report(_ outcome: TitleModel.DownloadOutcome, _ model: TitleModel, videoID: String? = nil) async {
        switch outcome {
        // N1: el póster vuela a Biblioteca. Una sola: lo dice el botón o el renglón (su avance), sin aviso encima. Varias: un
        // aviso breve.
        case .queued(let n):
            env.ui.downloadFlight = DownloadFlight(poster: model.poster)
            if n > 1 { env.notify(format: "Descargando %lld episodios", n, tone: .success, action: .downloads) }
        // «Ya está descargada · Ver»: la copia del iPhone, sin red.
        default: env.report(outcome, downloaded: videoID.map { (model.metaID, $0) })
        }
        await model.refreshState()
    }

    // MARK: tu calificación
    /// «Tu calificación»: tus estrellas de Trakt en la ficha (con Trakt y un título con IMDb). Tocar la misma la quita.
    @ViewBuilder func yourRating(_ model: TitleModel) -> some View {
        if model.canFavorite {
            let ratings = env.ratings
            let _ = ratings.track()
            HStack(spacing: DS.Space.s3) {
                Text("Tu calificación").recipe(.secondary, color: DS.textMuted)
                Spacer(minLength: 0)
                RatingStars(value: ratings.stars(model.metaID)) { stars in
                    Task { await ratings.rate(imdb: model.metaID, kind: model.kind, stars: stars) }
                }
            }
            .accessibilityElement(children: .contain)   // las estrellas conservan su identificador («rating-stars»)
            .accessibilityIdentifier("title-your-rating")
        }
    }

    /// Calificar un capítulo (con Trakt): su video id es la clave en Trakt.
    func rateEpisode(_ model: TitleModel, _ videoID: String) -> ((Double?) -> Void)? {
        guard model.canFavorite else { return nil }
        let ratings = env.ratings
        return { (stars: Double?) -> Void in Task { await ratings.rate(imdb: videoID, kind: "series", stars: stars) } }
    }

    /// «▶ Ver» o «▶ Continuar T2 E6»; si ibas a medias, la barrita con cuánto falta y «Desde el principio» (como la TV,
    /// `core/watch.js`); y la versión que va a sonar («🇲🇽 Latino · 1080p · Dolby Vision»; «Latino» o «Castellano» solo si se
    /// sabe, si no «Español» a secas). Mientras carga, «Cargando» y la versión «Buscando…»: su lugar apartado, nada brinca.
    func continueAction(_ model: TitleModel) -> ContinueAction {
        let label = model.continueLabel
        let go = { play(model) }
        if model.continueVideoID == nil && !model.isLoading {
            // Ya cargó y no hay qué ver: sin red, o una serie que aún no tiene episodios.
            // Con internet no es «Sin conexión»: es que no se pudo cargar (Cinemeta caído, un id raro).
            let failed = model.error == nil ? nil : env.isOnline ? Text("No se pudo cargar") : Text("Sin conexión")
            return ContinueAction(title: failed ?? Text("Aún sin episodios"), symbol: nil, enabled: false, play: go)
        }
        if model.continueVideoID == nil {
            return ContinueAction(title: Text("Cargando"), loading: true, enabled: false, versionPending: true, play: go)
        }
        // Real-Debrid: «Pedirlo y avisarme» en lugar de «Ver» (R2-A) o cuánto lleva lo pedido (R3, R13).
        if let debrid = debridContinueAction(model) { return debrid }
        if let appear = appearContinueAction(model) { return appear }   // R15: «Avisarme cuando aparezca»
        if let airs = model.continueAirs {
            // Todavía no sale: la fecha en lugar de «Ver» (antes abría un reproductor que fallaba).
            return ContinueAction(title: Text("Sale el \(Strings.date(airs, .dayMonth, language: env.services.appSettings.uiLanguage))"), symbol: "calendar", enabled: false, play: go)
        }
        let languageName = model.recommendedLanguage.map { $0 == "es" ? Strings.tr("Español", language: env.services.appSettings.uiLanguage)
                                                                  : Streams.versionLanguageName($0, in: env.services.appSettings.uiLanguage) }
        // «🇲🇽 Latino · 1080p»: la bandera con su idioma escrito (revisión del 11 nov: la bandera sola a 16 pt, sobre todo la de
        // mitad España y mitad México, parecía un ícono roto). Es el único control de versión de la ficha.
        let language = languageName.map { LanguageFlags.flagged($0, model.recommendedLanguage) }
        let quality = model.recommendedSource.map { [language].compactMap { $0 } + $0.qualitySummary } ?? []
        let spoken = model.recommendedSource.map { [languageName].compactMap { $0 } + $0.qualitySummary } ?? []
        let cause = model.unavailableCause.map { Text(verbatim: $0.title { Strings.tr($0, language: env.services.appSettings.uiLanguage) }) }
        let version: Text = model.sourceCheck == .none ? (cause ?? Text("Sin versiones por ahora")) : model.sourceCheck == .offline ? (env.isOnline ? Text("Tus complementos no contestan") : Text("Sin conexión"))
            : Text.withFlagImages(quality.joined(separator: " · "))
        let pending = model.sourceCheck != .none && model.sourceCheck != .offline && quality.isEmpty
        let left = label.isResume ? Vocabulary.runtimeText(minutes: model.minutesToFinish).map { Text("quedan \($0)") } : nil
        return ContinueAction(title: primaryLabel(label, model), progress: model.resumeFraction, left: left, version: pending ? nil : version,
                              versionPending: pending,
                              versionLabel: spoken.isEmpty ? nil : Text("Se va a ver en: \(spoken.joined(separator: ", "))"),
                              play: go, restart: label.isResume ? { start(model, videoID: nil, fromStart: true) } : nil, aside: wantedAside(model),
                              why: model.poorFit.map(poorFitReason),
                              versions: model.sourceCheck == .none || model.sourceCheck == .offline ? nil
                                  : model.continueVideoID.map { video in { openVersions(video) } },
                              tint: artAccent)
    }

    /// N5-A · «La de inglés pesa 64 GB y aquí no se ve bien» (o «…viene en AV1…»).
    func poorFitReason(_ fit: PoorFit) -> Text {
        let ui = env.services.appSettings.uiLanguage
        let name = VersionText.inline(fit.language.map { Streams.versionLanguageName($0, in: ui) } ?? SourcesModel.quality(fit.source), ui)
        switch fit.problem {
        case .heavy(let gb): return Text("La de \(name) pesa \(String(gb)) GB y aquí no se ve bien")
        case .format(let format): return Text("La de \(name) viene en \(format) y aquí no se ve bien")
        }
    }

    func primaryLabel(_ label: (isResume: Bool, season: Int?, episode: Int?), _ model: TitleModel) -> Text {
        if let s = label.season, let e = label.episode { return label.isResume ? Text("Continuar T\(s) E\(e)") : Text("Ver T\(s) E\(e)") }
        return label.isResume ? Text("Continuar") : Text("Ver")   // los nombres de la TV (`core/watch.js`)
    }

}

/// EV1: la hoja chica de un episodio que ya viste (la del sistema, abajo): ver otra vez con la versión de la serie, elegir otra
/// versión o idioma, o marcarlo como no visto. https://claude.ai/artifact/25F8bQVYpNq1ZBzj221YVm
struct RewatchDialog: ViewModifier {
    @Binding var row: EpisodeRow?
    let version: String
    let again: (String) -> Void
    let versions: (String) -> Void
    let unwatch: (String) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(Text("Ya viste «\(row?.title ?? "")»"), isPresented: Binding(get: { row != nil }, set: { if !$0 { row = nil } }),
                                   titleVisibility: .visible, presenting: row) { r in
            Button { again(r.id) } label: { Label { Text("Ver otra vez · \(Text(verbatim: LanguageFlags.plain(version)))") } icon: { Image(systemName: "play.fill") } }
            Button { versions(r.id) } label: { Label("Otra versión o idioma", systemImage: "arrow.left.arrow.right") }
            Button { unwatch(r.id) } label: { Label("Marcar como no visto", systemImage: "circle") }
            Button("Cancelar", role: .cancel) {}
        }
    }
}
