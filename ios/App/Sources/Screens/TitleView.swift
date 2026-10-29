import SwiftUI
import OrbitalCore
import OrbitalModels

/// La ficha de una película o serie: continuar, guardar (en Mi lista, tu watchlist o tus listas), descargar, temporadas y episodios.
struct TitleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let route: TitleRoute
    @Environment(AppEnvironment.self) var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) var typeSize
    @Environment(\.colorScheme) var scheme
    @Environment(\.openURL) private var openURL
    @State private var observer: ModelObserver<TitleModel>
    @State var tint = ArtTint()
    @State private var sourcesFor: SourcesTarget?
    /// La sinopsis completa (tocar «más»).
    @State private var fullSynopsis = false
    /// Elegiste otra fuente para algo que ya tienes descargado: ¿cambiarla?
    @State var replacing: Replacement?

    struct Replacement { var source: Source; var videoID: String; var existing: DownloadItem }
    @State private var saving = false
    /// Lo que mide la pantalla visible (sin la barra de pestañas) y lo que hay bajo el arte hasta las acciones: el arte
    /// se ajusta para que «Ver», Guardar, Descargar y Fuente queden a la vista al abrir, en un SE y en un Pro.
    @State private var viewport: CGSize = .zero
    @State private var belowHero: CGFloat = 0
    /// Cuánto has deslizado (0 arriba) y el alto de la barra de arriba: el arte se recoge y lo que sube se desvanece.
    @State private var scrolled: CGFloat = 0
    @State private var topInset: CGFloat = 0

    struct SourcesTarget: Identifiable { var videoID: String; var purpose: Purpose; var fromHere = false; var id: String { "\(videoID)-\(purpose)" } }

    init(route: TitleRoute) {
        self.route = route
        _observer = State(wrappedValue: ModelObserver(TitleModel(AppEnvironment.shared.services, kind: route.kind, metaID: route.metaID, hint: (route.title, route.poster))))
    }

    var body: some View {
        let model = observer.model
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Al deslizar, el arte se recoge (`BleedArt(collapse:)`): ver `hero`.
                hero(model)
                    .perfTag("title.hero").onAppear { Perf.mark("title.shown") }
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
                    // Sin TMDB, los créditos ya van en el renglón de arriba (antes salían dos veces: «Dirección · Con» y otra vez
                    // «Reparto · Dirección · Guion»).
                    if let extras = model.extras { rich(extras).padding(.horizontal, -DS.Space.gutter) }
                    details(model)
                }
                .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s10)
                .padding(.top, scheme == .dark ? 0 : DS.Space.s4)   // en claro el arte es una tarjeta: los datos no se le pegan
                // Siempre se puede recoger el arte hasta que el nombre suba a la barra, aunque haya poco abajo (una película sin
                // reparto ni saga): si no, en unas fichas se recogía y en otras no.
                .frame(minHeight: viewport.height, alignment: .top)
            }
            // Ventana ancha (iPad, Mac): la ficha a un ancho de lectura, al centro; en el iPhone ocupa todo como siempre.
            .frame(maxWidth: DS.TitleAction.readableWidth)
            .frame(maxWidth: .infinity)
        }
        #if DEBUG
        .modifier(DemoScroll())   // `-demo-scroll N`: abre ya desplazada (capturas del arte a medio recoger)
        #endif
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in scrolled = y }
        // Lo que sube por debajo de la barra de arriba se desvanece (deja ver el fondo del color del arte) en vez de chocar con
        // el reloj y los botones. Arriba del todo no hay desvanecido: el arte llega hasta la orilla.
        .mask {
            VStack(spacing: 0) {
                // Toda la barra de arriba desvanecida (nada se trasluce detrás del nombre ni de los botones) y, debajo, la
                // transición suave hacia el contenido.
                let total = max(topInset + DS.TitleAction.topFade, 1), kept = 1 - fade
                LinearGradient(stops: [.init(color: .black.opacity(kept), location: 0),
                                       .init(color: .black.opacity(kept), location: topInset / total),
                                       .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: total)
                Color.black   // ds-exception: es una máscara, solo cuenta qué tan opaca es (no se ve el color)
            }
            .ignoresSafeArea()
        }
        // Recogido el arte, el nombre al centro de la barra, entre ‹ y los botones (como Apple TV): sigues sabiendo qué es. Se
        // dibuja aquí y no como elemento de la barra (en la barra transparente de la ficha el sistema no lo enseñaba).
        .overlay(alignment: .top) {
            let shown = Double(min(1, max(0, (scrolled - heroHeight * DS.TitleAction.titleFrom) / max(heroHeight * DS.TitleAction.titleSpan, 1))))
            Text(verbatim: model.title).recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(1)
                .padding(.horizontal, DS.TitleAction.barTitleInset)
                .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                .offset(y: -DS.Size.touchTarget - DS.Space.s2)
                .opacity(shown)
                .allowsHitTesting(false)
                .accessibilityHidden(shown < 1)
        }
        // El color del arte solo como un brillo arriba (antes toda la ficha se lavaba de ese tono): el arte manda.
        .background(Backdrop(tint: tint.colors))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)     // el arte llega hasta arriba y la barra flota encima
        .toolbar { topBar(model) }
        .task { await model.followDownloads() }
        .task { await model.loadConsoleDetails() }
        .task { await model.loadExtras(); if model.extras != nil { Perf.mark("title.extras") } }     // la ficha rica: elenco con foto, saga, tráiler, frase y detalles (TMDB)
        .onChange(of: env.watchedSomething) { Task { await model.refreshState() } }   // vuelves de ver: avance, visto y «Continuar» al día
        .task {
            await model.load()
            Task { await model.loadBestSource(onCellular: env.connectivity.isCellular); if model.bestSource != nil { Perf.mark("title.sources") } }   // aparte: las fuentes tardan y no detienen el color del fondo
            #if DEBUG
            if Demo.isOn, Demo.open == "play" { start(model, videoID: nil) }
            if Demo.isOn, Demo.open == "sources" || Demo.open == "sources-all", let v = model.continueVideoID { sourcesFor = SourcesTarget(videoID: v, purpose: .watch) }
            if Demo.isOn, Demo.open == "download" || Demo.open == "download-here" { await report(model.download([model.continueVideoID ?? model.metaID]), model); if Demo.open == "download" { dismiss() } }
            if Demo.isOn, Demo.open == "download-tap" { await downloadRecommended(model) }
            if Demo.isOn, Demo.open == "save" { saving = true }   // `-demo-open save`: la hoja «Guardar en…», para capturas
            if Demo.isOn, Demo.open == "versions", let v = model.downloadTarget {   // `-demo-open versions`: la hoja «Ya la tienes»
                await report(model.download([v]), model, videoID: v)
                await model.loadBestSource()
                if let source = model.bestSource, let existing = await model.existingDownload(v) { replacing = Replacement(source: source, videoID: v, existing: existing) }
            }
            #endif
            await tint.load(model.background ?? model.poster)
        }
        .sheet(item: $sourcesFor) { target in
            SourcesSheet(model: model, videoID: target.videoID, fromHere: target.fromHere, choose: { source, purpose in
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
    var heroAspect: CGFloat {
        let fallback = WindowMetrics.size.height < DS.TitleAction.shortScreen ? DS.TitleAction.heroAspectShort : DS.TitleAction.heroAspect
        guard contentWidth > 0, belowHero > 0 else { return fallback }
        let padding = scheme == .dark ? 0 : DS.Space.s4
        // `viewport` ya es el alto entre la barra de arriba y la de pestañas, y el contenido empieza bajo la de arriba (el arte
        // solo se extiende detrás de ella): lo libre es eso menos lo de abajo del arte. Antes se sumaba el margen de arriba y
        // la segunda fila de acciones quedaba debajo de las pestañas.
        let room = viewport.height - belowHero - padding - DS.Space.s3
        let width = contentWidth - (scheme == .dark ? 0 : DS.Space.gutter * 2)
        guard room > 0 else { return typeSize.isAccessibilitySize ? DS.TitleAction.heroAspectMaxLarge : DS.TitleAction.heroAspectMax }
        let cap = typeSize.isAccessibilitySize ? DS.TitleAction.heroAspectMaxLarge : DS.TitleAction.heroAspectMax
        return min(cap, max(DS.TitleAction.heroAspect, width / room))
    }

    /// Qué tan desvanecido va lo de arriba (0 con el arte a la vista, 1 ya recogido).
    private var fade: Double { Double(min(1, max(0, scrolled / max(heroHeight * DS.TitleAction.fadeAt, 1)))) }
    private var heroHeight: CGFloat { contentWidth > 0 ? contentWidth / heroAspect : 0 }
    /// El ancho de la ficha: el de la ventana, hasta el ancho de lectura (`DS.TitleAction.readableWidth`).
    private var contentWidth: CGFloat { min(viewport.width, DS.TitleAction.readableWidth) }

    /// Mi lista y En la TV: botones de ícono en la barra de arriba (con su nombre para VoiceOver).
    @ToolbarContentBuilder private func topBar(_ model: TitleModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if env.services.orbital.isConfigured {
                Button { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: model.continueVideoID, title: model.title) } } label: { Image(systemName: "tv") }
                    .disabled(model.continueVideoID == nil)
                    .accessibilityLabel(Text("Ver en la TV"))
            }
            // El corazón (tus favoritos de Trakt, aparte de «Guardar»): solo con Trakt conectado.
            if model.canFavorite {
                FavoriteButton(isFavorite: model.isFavorite) { Task { await toggleFavorite(model) } }
            }
            // «Guardar» vive en la rejilla de acciones; arriba, compartir (la ficha de IMDb, que abre en cualquier app).
            if model.metaID.hasPrefix("tt"), let url = URL(string: "https://www.imdb.com/title/\(model.metaID)/") {
                ShareLink(item: url, subject: Text(verbatim: model.title)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(Text("Compartir"))
            }
        }
    }

    /// El corazón cambia al instante; si Trakt lo acepta, un aviso con «Deshacer» (si no, regresa solo y la ficha dice por qué).
    private func toggleFavorite(_ model: TitleModel) async {
        guard await model.toggleFavorite() else { return }
        env.notify(model.isFavorite ? "Agregada a tus favoritos" : "Quitada de tus favoritos", detail: "Trakt", tone: .info,
                   actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") { Task { await model.toggleFavorite() } }
    }

    private var artAccent: Color { tint.colors?.accent ?? DS.accent }

    /// El botón principal (`ContinueAction`: el botón dice una sola cosa; el avance, la versión y «Desde el principio» van
    /// debajo) y cuatro acciones del mismo tamaño: Guardar, Descargar, Tráiler y Fuente. Cada una cambia en su lugar (Guardada,
    /// el anillo de la descarga): nada brinca.
    private func actions(_ model: TitleModel) -> some View {
        VStack(spacing: DS.Space.s4) {
            continueAction(model)
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
                    ActionTileLabel(title: Text("Versión"), symbol: "list.bullet.rectangle", tint: artAccent)
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity).disabled(model.continueVideoID == nil).accessibilityIdentifier("title-sources")
            }
            .animation(DS.Motion.base(reduceMotion), value: model.isSaved)
        }
    }

    /// «▶ Ver» o «▶ Continuar T2 E6»; si ibas a medias, la barrita con cuánto falta y «Desde el principio» (como la TV,
    /// `core/watch.js`); y la versión que va a sonar («🇲🇽 Latino · 1080p · Dolby Vision»; «Latino» o «Castellano» solo si se
    /// sabe, si no «Español» a secas). Mientras carga, «Cargando» y la versión «Buscando…»: su lugar apartado, nada brinca.
    private func continueAction(_ model: TitleModel) -> ContinueAction {
        let label = model.continueLabel
        let go = { play(model) }
        if model.continueVideoID == nil && !model.isLoading {
            // Ya cargó y no hay qué ver: sin red, o una serie que aún no tiene episodios.
            return ContinueAction(title: model.error != nil ? Text("Sin conexión") : Text("Aún sin episodios"), symbol: nil, enabled: false, play: go)
        }
        if model.continueVideoID == nil {
            return ContinueAction(title: Text("Cargando"), loading: true, enabled: false, version: Text("Buscando versión…"), play: go)
        }
        if let airs = model.continueAirs {
            // Todavía no sale: la fecha en lugar de «Ver» (antes abría un reproductor que fallaba).
            return ContinueAction(title: Text("Sale el \(airs, format: .dateTime.day().month(.wide))"), symbol: "calendar", enabled: false, play: go)
        }
        let language = model.recommendedLanguage.map { LanguageFlags.flagged($0 == "es" ? Strings.tr("Español", language: env.services.appSettings.uiLanguage)
                                                                  : Streams.versionLanguageName($0, in: env.services.appSettings.uiLanguage), $0) }
        let quality = model.recommendedSource.map { [language].compactMap { $0 } + $0.qualitySummary } ?? []
        let version: Text = model.sourceCheck == .none ? Text("Sin versiones por ahora") : model.sourceCheck == .offline ? Text("Sin conexión")
            : quality.isEmpty ? Text("Buscando versión…") : Text(verbatim: quality.joined(separator: " · "))
        let left = label.isResume ? Vocabulary.runtimeText(minutes: model.minutesToFinish).map { Text("quedan \($0)") } : nil
        return ContinueAction(title: primaryLabel(label, model), progress: model.resumeFraction, left: left, version: version,
                              versionLabel: quality.isEmpty ? nil : Text("Se va a ver en: \(LanguageFlags.withoutFlags(quality.joined(separator: ", ")))"),
                              play: go, restart: label.isResume ? { start(model, videoID: nil, fromStart: true) } : nil)
    }

    /// Guardar: un toque la guarda en la lista por omisión (tu watchlist con Trakt, si no Mi lista; `SaveDestination`), con un
    /// aviso que deja cambiar; mantener presionado elige dónde (la de por omisión primero).
    private func saveAction(_ model: TitleModel) -> some View {
        Menu {
            ForEach(model.fixedDestinations, id: \.self) { destination in
                Button { Task { await model.toggle(destination) } } label: {
                    Label { SaveDestinationName.text(destination) } icon: {
                        Image(systemName: model.isSaved(in: destination) ? "checkmark" : SaveDestinationName.symbol(destination))
                    }
                }
            }
            if model.traktAvailable { Button("Tus listas de Trakt…", systemImage: "list.bullet") { saving = true } }
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
        switch model.quickSave {
        case .add(let destination):
            await model.toggle(destination)
            guard model.isSaved(in: destination) else { return }   // falló: lo dice el mensaje de la ficha
            env.notify(saved: destination) { saving = true }
        case .remove(let destination):
            await model.toggle(destination)
            env.notify(removed: destination) { Task { await model.toggle(destination) } }
        case .choose:
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
                    Button("Elegir versión…", systemImage: "list.bullet.rectangle") { if let target { sourcesFor = SourcesTarget(videoID: target, purpose: .download) } }
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
        guard case .queued = outcome else { return await report(outcome, model, videoID: target) }
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
        // Un solo bloque de controles, simétrico: la temporada a la izquierda y la versión de la serie a la derecha, las dos
        // cápsulas iguales (antes temporada, versión y avance eran tres renglones con alineaciones y tamaños distintos); abajo,
        // el avance de la temporada de orilla a orilla.
        let wanted = env.services.titlePrefs.languages(for: model.metaID, settings: env.services.appSettings).prefs.wanted
        HStack(spacing: DS.Space.s2) {
            if model.seasons.count > 1 {
                let chips = model.seasons.map { SeasonChip(season: $0.season, isSpecials: $0.isSpecials) }
                let selection = Binding(get: { SeasonChip(season: model.selectedSeason, isSpecials: model.selectedSeason == 0) }, set: { model.select(season: $0.season) })
                DSOptionMenu(items: chips, label: { $0.isSpecials ? Text("Especiales") : Text("Temporada \($0.season)") }, selection: selection, compact: true)
            } else if let only = model.seasons.first {
                Text(only.isSpecials ? "Especiales" : "Temporada \(only.season)").recipe(.secondary, color: DS.text).fontWeight(.semibold)
            }
            Spacer(minLength: DS.Space.s2)
            // La versión de la serie (lo que recuerda: latino, castellano, inglés…); tocarla elige otra «desde aquí».
            if let next = model.continueVideoID {
                Button { sourcesFor = SourcesTarget(videoID: next, purpose: .watch, fromHere: true) } label: {
                    HStack(spacing: DS.Space.s2) {
                        Image(systemName: "list.bullet.rectangle").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted)
                        // «es» es «cualquier español» (lo que pediste), no una versión que no dice cuál.
                        Text("\(Text.flag(wanted))\(Text(verbatim: wanted == "es" ? Strings.tr("Español", language: env.services.appSettings.uiLanguage) : Streams.versionLanguageName(wanted, in: env.services.appSettings.uiLanguage)))")
                            .recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted)
                    }
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(DS.text)
                .accessibilityLabel(Text("Versión de la serie"))
                .accessibilityIdentifier("series-version")
            }
        }
        // Cuántos llevas de esta temporada y marcarla completa (como en Infuse y Trakt), con su barra.
        let progress = model.seasonProgress
        if progress.total > 0 {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack {
                    Text("\(progress.watched) de \(progress.total) vistos").recipe(.footnote)
                    Spacer()
                    if progress.watched < progress.total {
                        Button("Marcar como vista", systemImage: "checkmark.circle") { Task { await model.markSeasonWatched() } }
                            .font(DS.TextRecipe.footnote.font).buttonStyle(.borderless)
                    }
                }
                ProgressView(value: Double(progress.watched), total: Double(progress.total)).tint(DS.brandMoon)
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
                    let line = Text("\(who.foregroundStyle(DS.textFaint))\(Text(verbatim: " " + lead.prefix(2).joined(separator: ", ")).foregroundStyle(DS.text))")
                    if let writer = writers.first, model.kind == "movie" {
                        Text("\(line)\(Text(verbatim: " · ").foregroundStyle(DS.textFaint))\(Text("Guion").foregroundStyle(DS.textFaint))\(Text(verbatim: " " + writer).foregroundStyle(DS.text))")
                    } else { line }
                }
                if !leads.isEmpty {
                    Text("\(Text("Con").foregroundStyle(DS.textFaint))\(Text(verbatim: " " + leads.joined(separator: ", ")).foregroundStyle(DS.text))")
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
        let languages = (model.extras?.languages ?? []).compactMap { code in (locale.localizedString(forLanguageCode: code)?.capitalized(with: locale)).map { LanguageFlags.flagged($0, code) } }
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

}
