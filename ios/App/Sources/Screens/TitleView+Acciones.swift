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
        case .none:
            // Si tu Real-Debrid venció, eso es lo que pasa (no «no hay fuentes»), con la salida a la mano.
            if case .expired(let days)? = env.services.debrid.saved?.state(now: Date()) {
                let renew = env.services.debrid.provider.renewURL
                env.notify(String(format: Strings.tr(days == 1 ? "Tu Real-Debrid venció ayer" : "Tu Real-Debrid venció hace %lld días", language: env.services.appSettings.uiLanguage), days),
                           tone: .warn, actionTitle: "Renovar") { UIApplication.shared.open(renew) }
            } else if !env.services.debrid.hasToken {
                // Sin tu cuenta de Real-Debrid en la app casi no hay versiones que se vean en el iPhone: esa es la salida.
                env.notify("No encontré dónde verlo", detail: "Conecta tu Real-Debrid en Ajustes: sin él casi no hay versiones que se vean aquí",
                           tone: .warn, actionTitle: "Ajustes") { env.ui.openSettings = true }
            } else {
                env.notify("Real-Debrid aún no lo tiene", detail: "Los estrenos suelen llegar unas horas después")
            }
        case .offline:
            // Ningún complemento contestó: sin red es el iPhone; con red, son ellos (antes siempre decía «Sin internet»).
            if env.isOnline {
                env.notify("Tus complementos no contestan", detail: "Hay internet, pero ninguno respondió", tone: .warn, actionTitle: "Reintentar") { start(model, videoID: nil) }   // el reproductor vuelve a preguntar
            } else {
                env.notify("Sin internet", detail: "No pude buscar dónde verlo", tone: .warn, actionTitle: "Reintentar") { start(model, videoID: nil) }
            }
        default: start(model, videoID: nil)
        }
    }

    func start(_ model: TitleModel, videoID: String?, source: Source? = nil, fromStart: Bool = false) {
        guard var request = model.playRequest(videoID: videoID) else { return }
        request.sourceIndex = source?.index
        request.fromStart = fromStart
        if env.services.appSettings.preferInfuse { Task { await env.playExternal(request, source: source) } } else { env.play(request) }
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

    /// «4K · Dolby Vision» y «12.3 GB · Torrentio» (o «Bajando 40 % · Torrentio») para la hoja «Ya la tienes».
    func describe(_ item: DownloadItem) -> (label: String, detail: Text) {
        let size = item.expectedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        let tail = item.addon.isEmpty ? "" : " · \(item.addon)"
        if item.state != .done, let expected = item.expectedBytes, expected > 0 {
            let percent = "\(Int(Double(item.writtenBytes) / Double(expected) * 100)) %"
            return (item.quality ?? item.addon, Text("\(Text("Bajando \(percent)"))\(Text(verbatim: tail))"))
        }
        return (item.quality ?? item.addon, Text(verbatim: size + tail))
    }

    func describe(_ source: Source) -> (label: String, detail: Text) {
        let label = ([source.resolution] + source.hdr).filter { !$0.isEmpty }.joined(separator: " · ")
        let size = source.size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(source.size), countStyle: .file) : nil
        return (label.isEmpty ? source.addon : label, Text(verbatim: [size, source.addon.isEmpty ? nil : source.addon].compactMap { $0 }.joined(separator: " · ")))
    }

    func report(_ outcome: TitleModel.DownloadOutcome, _ model: TitleModel, videoID: String? = nil) async {
        switch outcome {
        // Una sola: lo dice el botón o el renglón (su avance), sin aviso encima. Varias: un aviso breve.
        case .queued(let n): if n > 1 { env.notify(format: "Descargando %lld episodios", n, tone: .success, action: .downloads) }
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
            return ContinueAction(title: Text("Cargando"), loading: true, enabled: false, version: Text("Buscando versión…"), play: go)
        }
        if let airs = model.continueAirs {
            // Todavía no sale: la fecha en lugar de «Ver» (antes abría un reproductor que fallaba).
            return ContinueAction(title: Text("Sale el \(Strings.date(airs, .dayMonth, language: env.services.appSettings.uiLanguage))"), symbol: "calendar", enabled: false, play: go)
        }
        let language = model.recommendedLanguage.map { LanguageFlags.flagged($0 == "es" ? Strings.tr("Español", language: env.services.appSettings.uiLanguage)
                                                                  : Streams.versionLanguageName($0, in: env.services.appSettings.uiLanguage), $0) }
        let quality = model.recommendedSource.map { [language].compactMap { $0 } + $0.qualitySummary } ?? []
        let version: Text = model.sourceCheck == .none ? Text("Sin versiones por ahora") : model.sourceCheck == .offline ? (env.isOnline ? Text("Tus complementos no contestan") : Text("Sin conexión"))
            : quality.isEmpty ? Text("Buscando versión…") : Text(verbatim: quality.joined(separator: " · "))
        let left = label.isResume ? Vocabulary.runtimeText(minutes: model.minutesToFinish).map { Text("quedan \($0)") } : nil
        return ContinueAction(title: primaryLabel(label, model), progress: model.resumeFraction, left: left, version: version,
                              versionLabel: quality.isEmpty ? nil : Text("Se va a ver en: \(LanguageFlags.withoutFlags(quality.joined(separator: ", ")))"),
                              play: go, restart: label.isResume ? { start(model, videoID: nil, fromStart: true) } : nil, tint: artAccent)
    }

    func primaryLabel(_ label: (isResume: Bool, season: Int?, episode: Int?), _ model: TitleModel) -> Text {
        if let s = label.season, let e = label.episode { return label.isResume ? Text("Continuar T\(s) E\(e)") : Text("Ver T\(s) E\(e)") }
        return label.isResume ? Text("Continuar") : Text("Ver")   // los nombres de la TV (`core/watch.js`)
    }

}
