import SwiftUI
import OrbitalCore
import OrbitalModels

/// La ficha de una película o serie: continuar, guardar (en Mi lista, tu watchlist o tus listas), descargar, temporadas y episodios.
struct TitleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let route: TitleRoute
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @StateObject private var observer: ModelObserver<TitleModel>
    @StateObject private var tint = ArtTint()
    @State private var sourcesFor: SourcesTarget?
    /// La sinopsis completa (tocar «más»).
    @State private var fullSynopsis = false
    /// Elegiste otra fuente para algo que ya tienes descargado: ¿cambiarla?
    @State private var replacing: Replacement?

    struct Replacement { var source: Source; var videoID: String; var existing: DownloadItem }
    @State private var saving = false
    /// Lo que mide la pantalla visible (sin la barra de pestañas) y lo que hay bajo el arte hasta las acciones: el arte
    /// se ajusta para que «Ver», Guardar, Descargar y Fuente queden a la vista al abrir, en un SE y en un Pro.
    @State private var viewport: CGSize = .zero
    @State private var belowHero: CGFloat = 0
    /// Ya se bajó del arte: un velo bajo la barra de arriba (los episodios no pasan por debajo de los botones a pelo).
    @State private var scrolledPastHero = false

    struct SourcesTarget: Identifiable { var videoID: String; var purpose: Purpose; var id: String { "\(videoID)-\(purpose)" } }

    init(route: TitleRoute) {
        self.route = route
        _observer = StateObject(wrappedValue: ModelObserver(TitleModel(AppEnvironment.shared.services, kind: route.kind, metaID: route.metaID, hint: (route.title, route.poster))))
    }

    var body: some View {
        let model = observer.model
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(model)
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    VStack(alignment: .leading, spacing: DS.Space.s6) {
                        facts(model)
                        actions(model)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { belowHero = $0 }
                    if let message = model.message { DSNotice(verbatim: env.message(message), tone: .error) }
                    if let error = model.error, !model.isLoading {
                        // No cargó (sin red, Cinemeta caído): lo dice y deja reintentar (antes «Cargando» se quedaba para siempre).
                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            DSNotice(verbatim: env.message(error), tone: .warn)
                            Button("Intentar de nuevo", systemImage: "arrow.clockwise") { Task { await model.load() } }
                                .buttonStyle(.glass).accessibilityIdentifier("title-retry")
                        }
                    }
                    synopsis(model)
                    creditLine(model)
                    if model.kind == "series" { episodes(model) }
                    if let extras = model.extras { rich(extras).padding(.horizontal, -DS.Space.gutter) } else { credits(model) }
                    details(model)
                }
                .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s10)
                .padding(.top, scheme == .dark ? 0 : DS.Space.s4)   // en claro el arte es una tarjeta: los datos no se le pegan
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > DS.TitleAction.veilAfter } action: { _, past in scrolledPastHero = past }
        .overlay(alignment: .top) {
            LinearGradient(colors: [DS.bg, DS.bg.opacity(DS.TitleAction.veilEdge), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: DS.TitleAction.veilHeight).ignoresSafeArea(edges: .top)
                .opacity(scrolledPastHero ? 1 : 0).animation(DS.Motion.base(reduceMotion), value: scrolledPastHero)
                .allowsHitTesting(false)
        }
        // El color del arte solo como un brillo arriba (antes toda la ficha se lavaba de ese tono): el arte manda.
        .background(Backdrop(tint: tint.colors))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)     // el arte llega hasta arriba y la barra flota encima
        .toolbar { topBar(model) }
        .task { await model.followDownloads() }
        .task { await model.loadConsoleDetails() }
        .task { await model.loadExtras() }     // la ficha rica: elenco con foto, saga, tráiler, frase y detalles (TMDB)
        .onChange(of: env.watchedSomething) { Task { await model.refreshState() } }   // vuelves de ver: avance, visto y «Continuar» al día
        .task {
            await model.load()
            Task { await model.loadBestSource(onCellular: env.connectivity.isCellular) }   // aparte: las fuentes tardan y no detienen el color del fondo
            #if DEBUG
            if Demo.isOn, Demo.open == "play" { start(model, videoID: nil) }
            if Demo.isOn, Demo.open == "sources", let v = model.continueVideoID { sourcesFor = SourcesTarget(videoID: v, purpose: .watch) }
            if Demo.isOn, Demo.open == "download" || Demo.open == "download-here" { await report(model.download([model.continueVideoID ?? model.metaID]), model); if Demo.open == "download" { dismiss() } }
            if Demo.isOn, Demo.open == "download-tap" { await downloadRecommended(model) }
            if Demo.isOn, Demo.open == "save" { saving = true }   // `-demo-open save`: la hoja «Guardar en…», para capturas
            if Demo.isOn, Demo.open == "versions", let v = model.downloadTarget {   // `-demo-open versions`: la hoja «Ya la tienes»
                await report(model.download([v]), model)
                await model.loadBestSource()
                if let source = model.bestSource, let existing = await model.existingDownload(v) { replacing = Replacement(source: source, videoID: v, existing: existing) }
            }
            #endif
            await tint.load(model.background ?? model.poster)
        }
        .sheet(item: $sourcesFor) { target in
            SourcesSheet(model: model, videoID: target.videoID, choose: { source, purpose in
                sourcesFor = nil
                handle(source: source, videoID: target.videoID, purpose: purpose, model: model)   // lo que quedó en el selector de la hoja
            }, infuse: { source in
                sourcesFor = nil
                if let request = model.playRequest(videoID: target.videoID) { Task { await env.playExternal(request, source: source) } }
            })
            .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $saving) { SaveView(observer: observer).fittedSheet() }
        .sheet(isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })) {
            if let r = replacing {
                DownloadVersionSheet(current: describe(r.existing), new: describe(r.source),
                    keepBoth: { replacing = nil; Task { await report(model.download([r.videoID], source: r.source, keepBoth: true), model) } },
                    replace: { replacing = nil; Task { await report(model.download([r.videoID], source: r.source, replace: true), model) } },
                    cancel: { replacing = nil })
                .fittedSheet()
            }
        }
    }

    // MARK: partes
    /// Ancho / alto del arte: el de siempre si cabe; si no, más ancho (más bajito) hasta que las acciones queden sobre la
    /// barra de pestañas. Antes de medir, la proporción fija de los teléfonos bajitos.
    private var heroAspect: CGFloat {
        let fallback = UIScreen.main.bounds.height < DS.TitleAction.shortScreen ? DS.TitleAction.heroAspectShort : DS.TitleAction.heroAspect
        guard viewport.width > 0, belowHero > 0 else { return fallback }
        let padding = scheme == .dark ? 0 : DS.Space.s4
        // `viewport` ya es el alto entre la barra de arriba y la de pestañas, y el contenido empieza bajo la de arriba (el arte
        // solo se extiende detrás de ella): lo libre es eso menos lo de abajo del arte. Antes se sumaba el margen de arriba y
        // la segunda fila de acciones quedaba debajo de las pestañas.
        let room = viewport.height - belowHero - padding - DS.Space.s3
        let width = viewport.width - (scheme == .dark ? 0 : DS.Space.gutter * 2)
        guard room > 0 else { return typeSize.isAccessibilitySize ? DS.TitleAction.heroAspectMaxLarge : DS.TitleAction.heroAspectMax }
        let cap = typeSize.isAccessibilitySize ? DS.TitleAction.heroAspectMaxLarge : DS.TitleAction.heroAspectMax
        return min(cap, max(DS.TitleAction.heroAspect, width / room))
    }

    /// El arte a sangre, más alto, con el logo (o el nombre) al centro y la frase de la película debajo, como un cartel de cine.
    private func hero(_ model: TitleModel) -> some View {
        BleedArt(url: model.background ?? model.poster, title: model.title,
                 aspect: heroAspect) {
            VStack(spacing: DS.Space.s2) {
                TitleLogo(url: model.info.logo ?? Artwork.logoURL(metaID: model.metaID), title: model.title, size: .hero, dark: model.logoIsDark, centered: true)
                    .containerRelativeFrame(.horizontal) { width, _ in width * DS.TitleAction.logoWidth }
                if let tagline = model.extras?.tagline {
                    Text(verbatim: tagline).font(DS.TextRecipe.secondary.font.italic()).foregroundStyle(DS.onArtSecondary)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .top)
    }

    /// Bajo el arte, al centro, un solo renglón: año · géneros · duración («2 h 25 min») y la clasificación («B») como insignia
    /// con contorno al final; debajo, las calificaciones. La calidad de la que va a sonar (la recomendada) vive dentro de «Ver».
    private func facts(_ model: TitleModel) -> some View {
        let language = env.services.appSettings.uiLanguage
        let minutes = Int(CinemetaParsing.runtimeSeconds(model.info.runtime) / 60)
        let runtime = Vocabulary.runtimeText(minutes: minutes > 0 ? minutes : nil) ?? model.info.runtime
        let facts = Vocabulary.titleFacts(year: model.info.year, genres: Vocabulary.genres(model.info.genres, language: language), runtime: runtime, rating: "")
        return VStack(spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s2) {
                Text(verbatim: Vocabulary.factLine(facts)).recipe(.footnote).multilineTextAlignment(.center).lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                if let certification = model.extras?.certification {
                    QualityBadges(items: [certification]).fixedSize().accessibilityLabel(Text("Clasificación \(certification)"))
                }
            }
            RatingsRow(imdb: model.info.rating, tmdb: model.extras?.rating, trakt: model.traktRating, centered: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// Mi lista y En la TV: botones de ícono en la barra de arriba (con su nombre para VoiceOver).
    @ToolbarContentBuilder private func topBar(_ model: TitleModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if env.services.orbital.isConfigured {
                Button { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: model.continueVideoID, title: model.title) } } label: { Image(systemName: "tv") }
                    .disabled(model.continueVideoID == nil)
                    .accessibilityLabel(Text("Ver en la TV"))
            }
            // «Guardar» vive en la rejilla de acciones; arriba, compartir (la ficha de IMDb, que abre en cualquier app).
            if model.metaID.hasPrefix("tt"), let url = URL(string: "https://www.imdb.com/title/\(model.metaID)/") {
                ShareLink(item: url, subject: Text(verbatim: model.title)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(Text("Compartir"))
            }
        }
    }

    private var artAccent: Color { tint.colors?.accent ?? DS.accent }

    /// El botón principal sólido (negro en claro, blanco en oscuro) con la calidad de lo que va a sonar en un segundo renglón
    /// y, si ibas a medias, cuánto falta y su barrita; debajo, cuatro acciones del mismo tamaño: Guardar, Descargar, Tráiler y
    /// Fuente. Cada una cambia en su lugar (Guardada, el anillo de la descarga): nada brinca.
    private func actions(_ model: TitleModel) -> some View {
        let label = model.continueLabel
        return VStack(spacing: DS.Space.s4) {
            VStack(spacing: DS.Space.s2) {
                Button { play(model) } label: { primaryButtonLabel(label, model) }
                    .dsSolidPrimaryButton().disabled(model.continueVideoID == nil || model.continueAirs != nil)
                    .accessibilityIdentifier("title-play")
                // «Desde el principio» (como la TV, `core/watch.js`), discreto: solo si ibas a medias.
                if label.isResume {
                    Button("Desde el principio", systemImage: "arrow.counterclockwise") { start(model, videoID: nil, fromStart: true) }
                        .font(DS.TextRecipe.footnote.font).buttonStyle(.borderless).tint(DS.textMuted)
                        .accessibilityIdentifier("title-restart")
                }
            }
            // Con letra de accesibilidad, en dos columnas (en un renglón los nombres se encimaban: «Guardada Descargar»).
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2, alignment: .top), count: typeSize.isAccessibilitySize ? 2 : (model.extras?.trailer?.url == nil ? 3 : 4)),
                      spacing: DS.Space.s2) {
                saveAction(model).frame(maxWidth: .infinity)
                downloadAction(model).frame(maxWidth: .infinity)
                if let url = model.extras?.trailer?.url {
                    Button { openURL(url) } label: { ActionTileLabel(title: Text("Tráiler"), symbol: "play.rectangle", tint: artAccent) }
                        .buttonStyle(.plain).frame(maxWidth: .infinity).accessibilityIdentifier("title-trailer")
                }
                Button { if let v = model.continueVideoID { sourcesFor = SourcesTarget(videoID: v, purpose: .watch) } } label: {
                    ActionTileLabel(title: Text("Fuente"), symbol: "list.bullet.rectangle", tint: artAccent)
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity).disabled(model.continueVideoID == nil).accessibilityIdentifier("title-sources")
            }
            .animation(DS.Motion.base(reduceMotion), value: model.isSaved)
        }
    }

    /// Lo de adentro de «Ver»: ▶ Ver (o «Continuar · quedan 42 min») y, abajo, la calidad de la recomendada (la que va a sonar)
    /// («4K · Dolby Vision · Atmos»; nada si aún no se sabe). Con avance, una barrita al pie. Mientras carga, «Cargando».
    @ViewBuilder private func primaryButtonLabel(_ label: (isResume: Bool, season: Int?, episode: Int?), _ model: TitleModel) -> some View {
        let quality = model.recommendedSource?.qualitySummary ?? []
        VStack(spacing: DS.Space.s1) {
            if model.continueVideoID == nil && !model.isLoading {
                // Ya cargó y no hay qué ver: sin red, o una serie que aún no tiene episodios.
                (model.error != nil ? Text("Sin conexión") : Text("Aún sin episodios")).font(DS.TextRecipe.body.font.weight(.semibold))
            } else if model.continueVideoID == nil {
                HStack(spacing: DS.Space.s2) {
                    ProgressView().tint(DS.onSolidPrimary)
                    Text("Cargando")
                }
                .font(DS.TextRecipe.body.font.weight(.semibold))
            } else if let airs = model.continueAirs {
                // Todavía no sale: la fecha en lugar de «Ver» (antes abría un reproductor que fallaba).
                Label { Text("Sale el \(airs, format: .dateTime.day().month(.wide))") } icon: { Image(systemName: "calendar") }
                    .font(DS.TextRecipe.body.font.weight(.semibold)).lineLimit(1)
            } else {
                Label {
                    if label.isResume, let left = Vocabulary.runtimeText(minutes: model.minutesToFinish) {
                        primaryLabel(label, model) + Text(verbatim: " · ") + Text("quedan \(left)")
                    } else {
                        primaryLabel(label, model)
                    }
                } icon: { Image(systemName: "play.fill") }
                .font(DS.TextRecipe.body.font.weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                if model.sourceCheck == .none || model.sourceCheck == .offline {
                    (model.sourceCheck == .none ? Text("Sin fuentes por ahora") : Text("Sin conexión"))
                        .font(DS.TextRecipe.caption.font.weight(.medium)).opacity(DesignTokens.Opacity.onArtSecondary).lineLimit(1)
                } else if !quality.isEmpty {
                    Text(verbatim: quality.joined(separator: " · ")).font(DS.TextRecipe.caption.font.weight(.medium))
                        .opacity(DesignTokens.Opacity.onArtSecondary).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                        .accessibilityLabel(Text("Se va a ver en: \(quality.joined(separator: ", "))"))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: DS.TitleAction.primaryHeight - DS.Space.s3 * 2)
        .overlay(alignment: .bottom) {
            if let fraction = model.resumeFraction, model.continueVideoID != nil {
                GeometryReader { box in
                    Capsule().fill(DS.onSolidPrimary.opacity(DesignTokens.Opacity.track))
                        .overlay(alignment: .leading) { Capsule().fill(DS.onSolidPrimary).frame(width: box.size.width * fraction) }
                }
                .frame(height: DS.TitleAction.primaryProgress)
                .padding(.horizontal, DS.Space.s4)
                .offset(y: DS.Space.s1)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, DS.Space.s3 - DS.Space.s2)
    }

    /// Guardar: un toque la guarda en Mi lista (con un aviso que deja cambiar); mantener presionado elige dónde.
    private func saveAction(_ model: TitleModel) -> some View {
        Menu {
            Button { Task { await model.toggleLibrary() } } label: {
                Label { Text("Mi lista") + Text(verbatim: " (Stremio)") } icon: { Image(systemName: model.inLibrary ? "checkmark" : "rectangle.stack") }
            }
            if model.traktAvailable {
                Button { Task { await model.toggleWatchlist() } } label: {
                    Label { Text("Tu watchlist") + Text(verbatim: " (Trakt)") } icon: { Image(systemName: model.inWatchlist ? "checkmark" : "bookmark") }
                }
                Button("Tus listas de Trakt…", systemImage: "list.bullet") { saving = true }
            }
        } label: {
            ActionTileLabel(title: model.isSaved ? Text("Guardada") : Text("Guardar"), symbol: model.isSaved ? "checkmark.circle.fill" : "plus.circle", active: model.isSaved, tint: artAccent)
        } primaryAction: {
            Task { await quickSave(model) }
        }
        .menuStyle(.button).buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: model.isSaved) { _, saved in saved }
        .accessibilityIdentifier("title-save")
        .accessibilityHint(Text("Mantén presionado para elegir en qué lista"))
    }

    private func quickSave(_ model: TitleModel) async {
        if !model.isSaved {
            await model.toggleLibrary()
            guard model.inLibrary else { return }   // falló: lo dice el mensaje de la ficha
            env.notify("Guardada en Mi lista", detail: "Stremio", actionTitle: "Cambiar") { saving = true }
        } else if model.inLibrary && !model.inWatchlist && !model.inSomeList && !(model.lists ?? []).contains(where: \.contains) {
            await model.toggleLibrary()
            env.notify("Quitada de Mi lista", tone: .info, actionTitle: "Deshacer") { Task { await model.toggleLibrary() } }
        } else {
            saving = true   // está en varias listas: que elijas de cuál quitarla
        }
    }

    /// Descargar: un toque baja la recomendada y el círculo se vuelve el anillo de su avance; tocar el anillo da sus opciones.
    @ViewBuilder private func downloadAction(_ model: TitleModel) -> some View {
        let target = model.downloadTarget
        let fraction = model.downloadFraction(target)
        Group {
            switch model.downloadState(target) {
            case .downloading?, .queued?:
                Menu {
                    if let fraction { Text("Lleva \(Int(fraction * 100)) %") }
                    Button("Pausar", systemImage: "pause.fill") { if let target { Task { await model.pauseDownload(target) } } }
                    Button("Ver en Descargas", systemImage: "arrow.down.circle") { env.openTab = AppEnvironment.downloadsTab }
                    Button("Cancelar la descarga", systemImage: "xmark", role: .destructive) { if let target { Task { await model.cancelDownload(target) } } }
                } label: {
                    ActionTileLabel(title: fraction.map { Text(verbatim: "\(Int($0 * 100)) %") } ?? Text("En espera"), symbol: "pause.fill", active: true, progress: fraction ?? 0, tint: artAccent)
                }
            case .paused?, .failed?:
                let failed = model.downloadState(target) == .failed
                Menu {
                    Button("Ver en Descargas", systemImage: "arrow.down.circle") { env.openTab = AppEnvironment.downloadsTab }
                    Button("Cancelar la descarga", systemImage: "xmark", role: .destructive) { if let target { Task { await model.cancelDownload(target) } } }
                } label: {
                    ActionTileLabel(title: failed ? Text("Reintentar") : Text("En pausa"), symbol: failed ? "arrow.clockwise" : "play.fill", active: true, progress: fraction, tint: failed ? DS.warning : artAccent)
                } primaryAction: {
                    if let target { Task { await model.resumeDownload(target) } }
                }
            case .done?:
                Menu {
                    Button("Ver sin internet", systemImage: "play.fill") { start(model, videoID: target) }
                    Button("Ver en Descargas", systemImage: "arrow.down.circle") { env.openTab = AppEnvironment.downloadsTab }
                    Button("Borrar la descarga", systemImage: "trash", role: .destructive) { if let target { Task { await model.cancelDownload(target) } } }
                } label: {
                    ActionTileLabel(title: Text("Descargada"), symbol: "arrow.down.circle.fill", active: true, tint: artAccent)
                }
            default:
                Menu {
                    Button("Elegir la fuente…", systemImage: "list.bullet") { if let target { sourcesFor = SourcesTarget(videoID: target, purpose: .download) } }
                    if model.kind == "series" {
                        Button("Los siguientes \(DS.Size.downloadNext)", systemImage: "square.stack.3d.down.right") { Task { await report(model.downloadNext(DS.Size.downloadNext), model) } }
                    }
                } label: {
                    ActionTileLabel(title: Text("Descargar"), symbol: "arrow.down.circle", tint: artAccent)
                } primaryAction: {
                    Task { await downloadRecommended(model) }
                }
            }
        }
        .menuStyle(.button).buttonStyle(.plain)
        .disabled(target == nil)
        .accessibilityIdentifier("title-download")
    }

    /// Un toque: la recomendada (la mejor en calidad, idioma y tamaño), y un aviso que dice cuál y deja elegir otra.
    private func downloadRecommended(_ model: TitleModel, videoID: String? = nil) async {
        guard let target = videoID ?? model.downloadTarget else { return }
        let outcome = await model.download([target])
        guard case .queued = outcome else { return await report(outcome, model) }
        let item = await model.existingDownload(target)
        let size = item?.expectedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let detail = [item?.quality, size].compactMap { $0 }.joined(separator: " · ")
        let what = model.episodeLabel(target)
        env.notify(what.map { String(format: Strings.tr("Bajando %@", language: env.services.appSettings.uiLanguage), $0) } ?? "Bajando la recomendada",
                   detail: detail.isEmpty ? nil : detail, actionTitle: "Otra") {
            sourcesFor = SourcesTarget(videoID: target, purpose: .download)
        }
    }

    private func primaryLabel(_ label: (isResume: Bool, season: Int?, episode: Int?), _ model: TitleModel) -> Text {
        if let s = label.season, let e = label.episode { return label.isResume ? Text("Continuar T\(s) E\(e)") : Text("Ver T\(s) E\(e)") }
        return label.isResume ? Text("Continuar") : Text("Ver")   // los nombres de la TV (`core/watch.js`)
    }

    @ViewBuilder private func episodes(_ model: TitleModel) -> some View {
        if model.seasons.count > 1 {
            let chips = model.seasons.map { SeasonChip(season: $0.season, isSpecials: $0.isSpecials) }
            let selection = Binding(get: { SeasonChip(season: model.selectedSeason, isSpecials: model.selectedSeason == 0) }, set: { model.select(season: $0.season) })
            let label = { (season: SeasonChip) in season.isSpecials ? Text("Especiales") : Text("Temporada \(season.season)") }
            // Hasta 4 temporadas caben como filtros a la vista; con más, un menú (como Apple TV y Netflix).
            if chips.count <= DS.Size.seasonChipsMax {
                DSChipRow(items: chips, label: label, selection: selection).padding(.horizontal, -DS.Space.gutter)
            } else {
                DSOptionMenu(items: chips, label: label, selection: selection)
            }
        }
        // Cuántos llevas de esta temporada y marcarla completa (como en Infuse y Trakt).
        let progress = model.seasonProgress
        if progress.total > 0 {
            HStack {
                Text("\(progress.watched) de \(progress.total) vistos").recipe(.footnote)
                Spacer()
                if progress.watched < progress.total {
                    Button("Marcar temporada como vista", systemImage: "checkmark.circle") { Task { await model.markSeasonWatched() } }
                        .font(DS.TextRecipe.footnote.font).buttonStyle(.borderless)
                }
            }
        }
        LazyVStack(spacing: 0) {   // perezosa: una serie larga no arma (ni pide imágenes de) todos sus episodios a la vez
            ForEach(model.rows) { row in
                EpisodeRowView(row: row, play: { if row.airs == nil { start(model, videoID: row.id) } }, download: { Task { await downloadRecommended(model, videoID: row.id) } },
                               markWatched: { Task { await model.markWatched(row.id) } }, chooseSource: { sourcesFor = SourcesTarget(videoID: row.id, purpose: .watch) },
                               resumeDownload: { Task { await model.resumeDownload(row.id) } },
                               downloadFraction: model.downloadFraction(row.id),
                               playOnTV: env.services.orbital.isConfigured ? { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: row.id, title: model.title) } } : nil)
                Divider().overlay(DS.hairline)
            }
        }
    }

    /// La sinopsis en tres renglones y «más» para leerla completa.
    @ViewBuilder private func synopsis(_ model: TitleModel) -> some View {
        if model.overview.isEmpty, model.isLoading {
            // Esqueleto: el lugar de la sinopsis mientras llega (antes la ficha se veía vacía la primera vez).
            Text(verbatim: String(repeating: "placeholder ", count: 24)).recipe(.secondary).lineLimit(DS.TitleAction.synopsisLines)
                .redacted(reason: .placeholder).accessibilityHidden(true)
        } else if !model.overview.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(model.overview).recipe(.secondary, color: DS.text).lineLimit(fullSynopsis ? nil : DS.TitleAction.synopsisLines)
                if model.overview.count > DS.Size.synopsisFold {
                    Button(fullSynopsis ? "menos" : "más") { withAnimation(DS.Motion.base(reduceMotion)) { fullSynopsis.toggle() } }
                        .font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(artAccent).buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Como los créditos del cine, en una línea: «Dirección Denis Villeneuve · Guion Jon Spaihts» y «Con …».
    @ViewBuilder private func creditLine(_ model: TitleModel) -> some View {
        let crew = model.extras?.crew ?? []
        let directors = crew.filter { $0.role == "Director" || $0.role == "Creator" }.map(\.name)
        let writers = crew.filter { $0.role == "Screenplay" || $0.role == "Writer" }.map(\.name)
        let leads = (model.extras?.cast.prefix(3).map(\.name)) ?? Array(model.credits.cast.prefix(3))
        let lead = directors.isEmpty ? model.credits.directors : directors
        if !lead.isEmpty || !leads.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if !lead.isEmpty {
                    let who = model.kind == "series" ? Text("Creada por") : Text("Dirección")
                    let line = who.foregroundStyle(DS.textFaint) + Text(verbatim: " " + lead.prefix(2).joined(separator: ", ")).foregroundStyle(DS.text)
                    if let writer = writers.first, model.kind == "movie" {
                        line + Text(verbatim: " · ").foregroundStyle(DS.textFaint) + Text("Guion").foregroundStyle(DS.textFaint) + Text(verbatim: " " + writer).foregroundStyle(DS.text)
                    } else { line }
                }
                if !leads.isEmpty {
                    Text("Con").foregroundStyle(DS.textFaint) + Text(verbatim: " " + leads.joined(separator: ", ")).foregroundStyle(DS.text)
                }
            }
            .font(DS.TextRecipe.footnote.font)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Al final, los datos de referencia: estreno, duración, idiomas, lo disponible, clasificación y estudio.
    @ViewBuilder private func details(_ model: TitleModel) -> some View {
        let rows = detailRows(model)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                DSSectionHead(title: "Detalles")
                Grid(alignment: .leading, horizontalSpacing: DS.Space.s4, verticalSpacing: DS.Space.s2) {
                    ForEach(rows, id: \.0) { label, value in
                        GridRow {
                            Text(LocalizedStringKey(label)).recipe(.footnote, color: DS.textFaint)
                            Text(verbatim: value).recipe(.footnote, color: DS.text)
                        }
                    }
                }
            }
        }
    }

    private static let day: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()

    private func detailRows(_ model: TitleModel) -> [(String, String)] {
        let locale = env.uiLocale
        var rows: [(String, String)] = []
        if let raw = model.extras?.releaseDate, let date = Self.day.date(from: raw) {
            rows.append((model.kind == "series" ? "Primer episodio" : "Estreno", date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale))))
        }
        if !model.info.runtime.isEmpty { rows.append(("Duración", model.info.runtime)) }
        let languages = (model.extras?.languages ?? []).compactMap { locale.localizedString(forLanguageCode: $0)?.capitalized(with: locale) }
        if !languages.isEmpty { rows.append(("Idiomas", languages.prefix(4).joined(separator: ", "))) }
        if let best = model.bestSource {
            let items = QualityBadges.items(resolution: best.resolution, hdr: best.hdr, audio: best.audioBadges)
            if !items.isEmpty { rows.append(("Disponible", items.joined(separator: " · "))) }
        }
        if let rating = model.extras?.certification { rows.append(("Clasificación", rating)) }
        if let studios = model.extras?.studios, !studios.isEmpty { rows.append((model.kind == "series" ? "Cadena" : "Estudio", studios.map(\.name).joined(separator: ", "))) }
        return rows
    }

    /// Lo de TMDB, como Infuse: tráiler y extras, reparto con cara (toca para ver su trabajo), la saga y
    /// «Más como esto». Cada sección con el encabezado de toda la app; las tiras van de borde a borde.
    @ViewBuilder private func rich(_ x: TitleExtras) -> some View {
        VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
            if let trailer = x.trailer {
                section(title: "Tráiler y extras") {
                    VideoClipCard(clip: trailer)
                    ForEach(x.extras) { VideoClipCard(clip: $0) }
                }
            }
            let people = x.crew + x.cast
            if !people.isEmpty {
                section(title: "Reparto y equipo") {
                    ForEach(people) { p in
                        NavigationLink(value: PersonRoute(id: p.personID, name: p.name)) { PersonFace(name: p.name, role: crewRole(p.role), photo: p.photo) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if let saga = x.collection {
                section(title: "La saga", meta: Text(verbatim: saga.name)) { ForEach(saga.parts) { TmdbPoster(title: $0) } }
            }
            if !x.recommendations.isEmpty {
                section(title: "Más como esto") { ForEach(x.recommendations) { TmdbPoster(title: $0) } }
            }
        }
    }

    private func section<Content: View>(title: LocalizedStringKey, meta: Text? = nil, count: Int? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: title, count: count, meta: meta).padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) { content() }.scrollTargetLayout().environment(\.posterCaptions, false)
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    /// El trabajo de alguien del equipo, en español (TMDB lo manda en inglés); un personaje se queda tal cual.
    private func crewRole(_ role: String) -> String {
        let language = env.services.appSettings.uiLanguage
        switch role {
        case "Director": return Strings.tr("Dirección", language: language)
        case "Screenplay", "Writer": return Strings.tr("Guion", language: language)
        case "Novel": return Strings.tr("Novela", language: language)
        case "Creator": return Strings.tr("Creación", language: language)
        default: return role
        }
    }

    @ViewBuilder private func credits(_ model: TitleModel) -> some View {
        if !model.credits.cast.isEmpty || !model.credits.directors.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if !model.credits.cast.isEmpty { creditLine("Reparto", model.credits.cast) }
                if !model.credits.directors.isEmpty { creditLine("Dirección", model.credits.directors) }
                if !model.credits.writers.isEmpty { creditLine("Guion", model.credits.writers) }
            }
        }
    }

    private func creditLine(_ title: LocalizedStringKey, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(title).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)
            Text(names.joined(separator: ", ")).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
        }
    }

    // MARK: acciones
    /// «Ver»: si ya se sabe que no hay fuentes (o no hay red), lo dice aquí en vez de abrir un reproductor que va a fallar.
    private func play(_ model: TitleModel) {
        switch model.sourceCheck {
        case .none: env.notify("Real-Debrid aún no lo tiene. Los estrenos suelen aparecer unas horas después.", tone: .info)
        case .offline: env.notify("Sin conexión: no pudimos preguntar por fuentes. Revisa tu internet.")
        default: start(model, videoID: nil)
        }
    }

    private func start(_ model: TitleModel, videoID: String?, source: Source? = nil, fromStart: Bool = false) {
        guard var request = model.playRequest(videoID: videoID) else { return }
        request.sourceIndex = source?.index
        request.fromStart = fromStart
        if env.services.appSettings.preferInfuse { Task { await env.playExternal(request, source: source) } } else { env.play(request) }
    }

    private func handle(source: Source, videoID: String, purpose: Purpose, model: TitleModel) {
        switch purpose {
        case .watch: start(model, videoID: videoID, source: source)
        case .download:
            // Ya hay una copia (o se está bajando): una sola por película o episodio, así que se pregunta si cambiarla.
            Task {
                if let existing = await model.existingDownload(videoID) { replacing = Replacement(source: source, videoID: videoID, existing: existing); return }
                await report(model.download([videoID], source: source), model)   // la fuente que elegiste
            }
        }
    }

    /// «4K · Dolby Vision» y «12.3 GB · Torrentio» (o «Bajando 40 % · Torrentio») para la hoja «Ya la tienes».
    private func describe(_ item: DownloadItem) -> (label: String, detail: Text) {
        let size = item.expectedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        let tail = item.addon.isEmpty ? "" : " · \(item.addon)"
        if item.state != .done, let expected = item.expectedBytes, expected > 0 {
            let percent = "\(Int(Double(item.writtenBytes) / Double(expected) * 100)) %"
            return (item.quality ?? item.addon, Text("Bajando \(percent)") + Text(verbatim: tail))
        }
        return (item.quality ?? item.addon, Text(verbatim: size + tail))
    }

    private func describe(_ source: Source) -> (label: String, detail: Text) {
        let label = ([source.resolution] + source.hdr).filter { !$0.isEmpty }.joined(separator: " · ")
        let size = source.size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(source.size), countStyle: .file) : nil
        return (label.isEmpty ? source.addon : label, Text(verbatim: [size, source.addon.isEmpty ? nil : source.addon].compactMap { $0 }.joined(separator: " · ")))
    }

    private func report(_ outcome: TitleModel.DownloadOutcome, _ model: TitleModel) async {
        switch outcome {
        // Una sola: lo dice el botón o el renglón (su avance), sin aviso encima. Varias: un aviso breve.
        case .queued(let n): if n > 1 { env.notify(format: "Descargando %lld episodios", n, tone: .success, action: .downloads) }
        case .noSources: env.notify("No hay fuentes de Real-Debrid para descargar.")
        case .notEnoughSpace(let text): env.notify(text)
        case .already: env.notify("Ya está descargado.", tone: .info)
        case .failed(let text): env.notify(text)
        }
        await model.refreshState()
    }
}

/// Una temporada en la tira de filtros.
struct SeasonChip: Hashable, Identifiable {
    var season: Int
    var isSpecials: Bool
    var id: Int { season }
}

struct EpisodeRowView: View {
    let row: EpisodeRow
    let play: () -> Void
    let download: () -> Void
    let markWatched: () -> Void
    let chooseSource: () -> Void
    var resumeDownload: () -> Void = {}
    var downloadFraction: Double?
    var playOnTV: (() -> Void)?

    var body: some View {
        // El botón de descargar va junto, no dentro, del que reproduce: anidados, tocar la flecha ponía el episodio.
        // Miniatura, texto y estado en una misma línea central: el estado siempre cae en la misma columna.
        HStack(alignment: .center, spacing: DS.Space.s3) {
            Button(action: play) {
                HStack(alignment: .center, spacing: DS.Space.s3) {
                    ZStack(alignment: .bottom) {
                        PosterView(url: row.thumbnail, title: "\(row.number)", aspect: DS.Poster.stillAspect)
                        if let progress = row.progress { DSProgress(fraction: progress) }
                    }
                    .frame(width: DS.Poster.episodeThumbWidth, height: DS.Poster.episodeThumbWidth / DS.Poster.stillAspect).clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        (row.hasTitle ? Text("\(row.number) · \(row.title)") : Text("Episodio \(row.number)")).font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text).lineLimit(2)
                        if hasStatus { status.font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted) }
                        if !row.overview.isEmpty { Text(row.overview).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint).lineLimit(2) }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            stateIcon.frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget, alignment: .trailing)
        }
        .padding(.vertical, DS.Space.s3)
        .opacity(row.airs == nil ? 1 : DesignTokens.Opacity.faint)
        .contextMenu {
            if row.airs == nil {
            Button("Marcar como visto", systemImage: "checkmark.circle", action: markWatched)
            Button("Descargar", systemImage: "arrow.down.circle", action: download)
            Button("Elegir la fuente…", systemImage: "list.bullet", action: chooseSource)
            if let playOnTV { Button("Ver en la TV", systemImage: "tv", action: playOnTV) }
            }
        }
    }

    private var hasStatus: Bool { row.airs != nil || row.watched || row.leftMinutes > 0 || row.download == .done }

    @ViewBuilder private var status: some View {
        if let airs = row.airs { Text("Sale el \(airs, format: .dateTime.day().month(.abbreviated))") }
        else if row.watched { Text("Visto") }
        else if row.leftMinutes > 0 { Text(timeLeftText(minutes: row.leftMinutes)) }
        else if row.download == .done { Text("Descargado") }
    }

    @ViewBuilder private var stateIcon: some View {
        if row.airs != nil { Image(systemName: "calendar").foregroundStyle(DS.textFaint).accessibilityLabel(Text("Todavía no sale")) }
        else if row.watched { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.good).accessibilityLabel(Text("Visto")) }
        else if row.download == .done { Image(systemName: "arrow.down.circle.fill").foregroundStyle(DS.good).accessibilityLabel(Text("Descargado")) }
        else if row.download == .downloading || row.download == .queued {
            // El mismo anillo que el círculo de Descargar de la ficha.
            DownloadRing(fraction: downloadFraction ?? 0, lineWidth: DS.TitleAction.ringSmallLine)
                .frame(width: DS.TitleAction.ringSmall, height: DS.TitleAction.ringSmall)
        }
        else if row.download == .paused || row.download == .failed {
            // En pausa o falló: seguir donde iba (no empezar de cero con otra fuente).
            Button(action: resumeDownload) {
                Image(systemName: row.download == .failed ? "arrow.clockwise" : "play.circle").foregroundStyle(row.download == .failed ? DS.warning : DS.textMuted)
                    .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
            }
            .buttonStyle(.plain).accessibilityLabel(row.download == .failed ? Text("Reintentar") : Text("Reanudar"))
        }
        else { Button(action: download) { Image(systemName: "arrow.down.circle").foregroundStyle(DS.textMuted).frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget) }.buttonStyle(.plain).accessibilityLabel(Text("Descargar")) }
    }
}
