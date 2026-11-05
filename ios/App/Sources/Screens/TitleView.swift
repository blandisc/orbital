import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons

/// La ficha de una película o serie: continuar, guardar (en Mi lista, tu watchlist o tus listas), descargar, temporadas y episodios.
struct TitleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let route: TitleRoute
    /// Opcional a propósito: al mantener presionado un póster, iOS arma la ficha (y los botones de su barra) en un árbol
    /// que todavía no tiene el entorno de la app, y uno obligatorio tiraba la app (R1, 31 oct 2026; `ToolbarEnvironmentTests`).
    @Environment(AppEnvironment.self) private var appEnv: AppEnvironment?
    var env: AppEnvironment { appEnv ?? .shared }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) var typeSize
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openURL) private var openURL
    /// Lo que dice Letterboxd de la película (su promedio y sus reseñas populares); las series casi nunca están.
    @State var letterboxdInfo: LetterboxdFilmInfo?
    @State private var observer: ModelObserver<TitleModel>
    @State var tint = ArtTint()
    @State private var sourcesFor: SourcesTarget?
    /// La sinopsis completa (tocar «más»).
    @State private var fullSynopsis = false
    /// Elegiste otra fuente para algo que ya tienes descargado: ¿cambiarla?
    @State var replacing: Replacement?

    struct Replacement { var source: Source; var videoID: String; var existing: DownloadItem }
    /// Real-Debrid: la hoja de un pedido, «¿Qué es esto?» o la línea antes de pedir permiso de avisos (`TitleView+RealDebrid`).
    @State var debridSheet: TitleDebridSheet?
    /// IOS-7 · el pedido que se va a cancelar desde el botón de la ficha (pregunta antes, como la hoja).
    @State var cancelling: DebridRequest?
    var observerModel: TitleModel { observer.model }
    func openVersions(_ videoID: String) { sourcesFor = SourcesTarget(videoID: videoID, purpose: .watch) }
    @State private var saving = false
    /// «¿Cuándo la viste?»: qué se está marcando (la película, un episodio, la temporada o la serie).
    @State var marking: WatchedScope?
    /// Lo que mide la pantalla visible (sin la barra de pestañas) y lo que hay bajo el arte hasta las acciones: el arte
    /// se ajusta para que «Ver», Guardar, Descargar y Fuente queden a la vista al abrir, en un SE y en un Pro.
    @State private var viewport: CGSize = .zero
    @State private var belowHero: CGFloat = 0
    /// Cuánto has deslizado (0 arriba) y el alto de la barra de arriba: el arte se recoge y lo que sube se desvanece.
    @State var topInset: CGFloat = 0

    struct SourcesTarget: Identifiable { var videoID: String; var purpose: Purpose; var fromHere = false; var id: String { "\(videoID)-\(purpose)" } }

    init(route: TitleRoute) {
        self.route = route
        _observer = State(wrappedValue: ModelObserver(TitleModel(AppEnvironment.shared.services, kind: route.kind, metaID: route.metaID, hint: (route.title, route.poster))))
    }

    var body: some View {
        let model = observer.model
        Group {
            // iPad y Mac (Fernando, 4 nov 2026, FE1): la ficha de la TV como esqueleto; el iPhone sigue en una columna.
            if sizeClass == .regular { wideLayout(model) } else { oneColumnLayout(model) }
        }
        #if DEBUG
        .modifier(DemoScroll())   // `-demo-scroll N`: abre ya desplazada (capturas del arte a medio recoger)
        #endif
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        // Lo de arriba que sigue al desplazamiento va aparte (`TitleScrollChrome`): antes cada cuadro del desplazamiento
        // volvía a pintar toda la ficha (capítulos, detalles), y regresar con el gesto se trababa.
        // En el iPad y la Mac la barra de pestañas ocupa ese renglón: el nombre no sube a la barra (se encimaba).
        .modifier(TitleScrollChrome(topInset: topInset, heroHeight: heroHeight, logo: sizeClass == .regular ? nil : model.logo,
                                    title: sizeClass == .regular ? "" : model.title,
                                    buttons: (env.services.orbital.isConfigured ? 1 : 0) + (model.canFavorite ? 1 : 0) + (model.metaID.hasPrefix("tt") ? 1 : 0)))
        // El color del arte solo como un brillo arriba (antes toda la ficha se lavaba de ese tono): el arte manda.
        .background(Backdrop(tint: tint.colors))
        // iPad y Mac (FE1): siempre oscura, como la sala de la TV; el arte no se corta contra un fondo claro.
        .environment(\.colorScheme, sizeClass == .regular ? .dark : scheme)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)     // el arte llega hasta arriba y la barra flota encima
        .toolbar { topBar(model) }
        .task { await model.followDownloads() }
        // F3: la primera vez que abres una ficha (si nunca has visto nada aquí), el foco en «Ver».
        .learnCoach(.titlePlay, title: "«Ver» elige la mejor versión en tu idioma.", detail: "Si quieres otra, toca «Versión».",
                    used: env.services.library.all.contains { $0.position > 0 || !$0.seen.isEmpty })
        // De vuelta a la app (quizá viste algo en la TV): lo visto, por dónde vas y lo que sigue, al día.
        .onChange(of: appEnv?.ui.returnedToApp) { Task { await model.refreshState() } }
        .task(id: model.metaID) {   // Letterboxd es de películas: las series no se preguntan
            guard route.kind == "movie" else { return }
            letterboxdInfo = await Letterboxd(http: env.services.http, kv: env.services.kv).info(imdb: model.metaID)
        }
        .task { await model.loadConsoleDetails() }
        .task { await model.loadExtras(); if model.extras != nil { Perf.mark("title.extras") } }     // la ficha rica: elenco con foto, saga, tráiler, frase y detalles (TMDB)
        .onChange(of: env.watchedSomething) { Task { await model.refreshState() } }   // vuelves de ver: avance, visto y «Continuar» al día
        .task {
            await model.load()
            Task { await model.loadBestSource(onCellular: env.connectivity.isCellular); if model.bestSource != nil { Perf.mark("title.sources") } }   // aparte: las fuentes tardan y no detienen el color del fondo
            if let video = route.versionsFor { sourcesFor = SourcesTarget(videoID: video, purpose: .watch) }   // «Probar otra versión» desde «Tus pedidos»
            #if DEBUG
            if Demo.isOn, Demo.open == "play" { start(model, videoID: nil) }
            if Demo.isOn, ["sources", "sources-all", "sources-request", "sources-card"].contains(Demo.open ?? ""), let v = model.continueVideoID { sourcesFor = SourcesTarget(videoID: v, purpose: .watch) }
            if Demo.isOn, Demo.open == "download" || Demo.open == "download-here" { await report(model.download([model.continueVideoID ?? model.metaID]), model); if Demo.open == "download" { dismiss() } }
            if Demo.isOn, Demo.open == "download-tap" { await downloadRecommended(model) }
            if Demo.isOn, Demo.open == "save" { saving = true }   // `-demo-open save`: la hoja «Guardar en…», para capturas
            if Demo.isOn, let sheet = Demo.open.flatMap({ TitleDebridSheet(rawValue: $0.replacingOccurrences(of: "rd-", with: "")) }), Demo.open?.hasPrefix("rd-") == true {
                debridSheet = sheet   // `-demo-open rd-request|rd-explain|rd-notify`: las hojas de Real-Debrid
            }
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
            }, request: env.services.debridRequests.canRequest ? { source in await sendRequest(model, source: source, videoID: target.videoID) } : nil)
            .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $saving) { SaveView(observer: observer).fittedSheet() }
        .sheet(item: $debridSheet) { kind in debridSheetContent(kind, model) }
        .debridFlowIntro(when: model.debridOffer != nil && model.debridRequest == nil)   // RX3-A: «Pedir a la nube» a la vista
        .task { _ = await DebridRequestNotifier.permission() }   // IOS-8: sin permiso no se promete «Te aviso»
        .debridCancelConfirmation(isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
                                  name: cancelling?.title ?? "", finished: false) { if let request = cancelling { Task { await cancelRequest(request) } } }
        // Un pedido cambió de estado (quedó listo, lo cancelaste): la versión y el botón se ponen al día.
        .onChange(of: model.debridRequest?.state) { _, _ in Task { await model.loadBestSource(onCellular: env.connectivity.isCellular) } }
        .modifier(TitleWatchedWhen(model: model, scope: $marking))
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

    /// El arte arriba y todo debajo; en ventana ancha (iPad, Mac), a un ancho de lectura y al centro. Desde Inicio, en el
    /// iPad y la Mac la ficha se abre en el panel de la derecha (`TitlePanel`), a la medida del iPhone.
    private func oneColumnLayout(_ model: TitleModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {   // ds-exception: el arte va a sangre pegado a lo de abajo; el ritmo lo lleva el stack de adentro
                // Al deslizar, el arte se recoge (`BleedArt(collapse:)`): ver `hero`.
                hero(model)
                    .perfTag("title.hero").onAppear { Perf.mark("title.shown") }
                VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                    VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                        facts(model)
                        actions(model)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { belowHero = $0 }
                    readingSections(model)
                }
                .modifier(TitleEntrance())   // el arte llega con el zoom; lo de abajo entra detrás de él
                .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Layout.screenBottom)
                .padding(.top, scheme == .dark ? 0 : DS.Space.s4)   // en claro el arte es una tarjeta: los datos no se le pegan
                // Siempre se puede recoger el arte hasta que el nombre suba a la barra, aunque haya poco abajo (una película sin
                // reparto ni saga): si no, en unas fichas se recogía y en otras no.
                .frame(minHeight: viewport.height, alignment: .top)
            }
            // Ventana ancha de pie (iPad, Mac angosta): la ficha a un ancho de lectura, al centro; en el iPhone ocupa todo.
            .frame(maxWidth: DS.TitleAction.readableWidth)
            .frame(maxWidth: .infinity)
        }
    }

    /// La ficha ancha (iPad, Mac; FE1), como la de la TV: el arte llena la pantalla con un velo a la izquierda y, encima,
    /// el logo, los datos, «Ver», las acciones y la sinopsis; lo demás (episodios, reparto, parecidas, detalles) debajo.
    private func wideLayout(_ model: TitleModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {   // ds-exception: el arte va a sangre pegado a lo de abajo
                ZStack(alignment: .bottomLeading) {
                    // Al bajar, el arte se recoge como en el iPhone.
                    BleedArt(url: model.background ?? model.poster, title: model.title, collapse: DS.backdropDeep,
                             fallback: model.poster, fadesTop: false) { EmptyView() }
                        .overlay { ArtVeil(kind: .leading, strength: .deep) }
                        .overlay { ArtVeil(kind: .bottom, at: DS.TitleAction.wideVeilFrom, until: DS.TitleAction.wideVeilSolid, strength: .deep) }
                    VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                        TitleLogo(url: model.logo, title: model.title, size: .hero)
                            .frame(maxWidth: DS.TitleAction.wideLogoWidth, alignment: .leading)
                        facts(model, leading: true)
                        actions(model)
                        synopsis(model)
                    }
                    .frame(maxWidth: DS.TitleAction.wideColumn, alignment: .leading)
                    .padding(.horizontal, side).padding(.bottom, DS.Layout.betweenSections)
                }
                // El arte sube detrás del reloj y de la barra, como en la TV.
                .frame(height: viewport.height * DS.TitleAction.wideHeroShare + topInset)
                .padding(.top, -topInset)
                VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                    readingSections(model, withSynopsis: false)
                }
                .modifier(TitleEntrance())
                .padding(.horizontal, side).padding(.top, DS.Space.s4).padding(.bottom, DS.Layout.screenBottom)
            }
        }
        // El fondo de la sala, el mismo color al que baja el velo del arte: sin la línea donde terminaba el arte.
        .background(DS.backdropDeep.ignoresSafeArea())
    }

    /// Lo que se lee bajo las acciones: avisos, sinopsis, créditos, episodios, la ficha rica y los detalles.
    @ViewBuilder private func readingSections(_ model: TitleModel, withSynopsis: Bool = true) -> some View {
        if let message = model.message { DSNotice(verbatim: env.message(message), tone: .error) }
        if let error = model.error, !model.isLoading {
            // No cargó (sin red, Cinemeta caído): lo dice y deja reintentar (antes «Cargando» se quedaba para siempre).
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSNotice(verbatim: env.message(error), tone: .warn)
                Button("Reintentar", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    .dsGlassButton().accessibilityIdentifier("title-retry")
            }
        }
        if withSynopsis { synopsis(model) }
        creditLine(model)
        yourRating(model)
        // Tu reseña en Letterboxd (si la conectaste y la reseñaste o calificaste).
        if let review = env.letterboxdReview(model.metaID) { LetterboxdReviewCard(entry: review, watched: LetterboxdWords.watched(review, language: env.services.appSettings.uiLanguage)) }
        if let info = letterboxdInfo, !info.reviews.isEmpty {
            LetterboxdPublicReviews(reviews: info.reviews, link: info.slug.flatMap { URL(string: "\(Letterboxd.site)/film/\($0)/reviews/by/activity/") })
        }
        if model.kind == "series" { episodes(model) }
        // Sin TMDB, los créditos ya van en el renglón de arriba (antes salían dos veces: «Dirección · Con» y otra vez
        // «Reparto · Dirección · Guion»).
        if let extras = model.extras { rich(extras).padding(.horizontal, -side) }
        details(model)
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

    private var heroHeight: CGFloat { contentWidth > 0 ? contentWidth / heroAspect : 0 }
    /// El ancho de la ficha: el de la ventana, hasta el ancho de lectura (`DS.TitleAction.readableWidth`).
    var contentWidth: CGFloat { min(viewport.width, DS.TitleAction.readableWidth) }

    /// Mi lista y En la TV: botones de ícono en la barra de arriba (con su nombre para VoiceOver).
    @ToolbarContentBuilder private func topBar(_ model: TitleModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if env.services.orbital.isConfigured {
                // Mientras va en camino, la ruedita en su lugar (y el aviso abajo): antes el toque no enseñaba nada.
                Button { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: model.continueVideoID, title: model.title) } } label: {
                    if env.isSendingToTV(model.metaID) { ProgressView() } else { Image(systemName: "tv") }   // ds-exception: la ruedita va dentro del botón que la pidió
                }
                    .disabled(model.continueVideoID == nil || env.isSendingToTV(model.metaID))
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: env.isSendingToTV(model.metaID)) { _, sending in sending }
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

    var artAccent: Color { tint.colors?.accent ?? DS.accent }

    /// El botón principal (`ContinueAction`: el botón dice una sola cosa; el avance, la versión y «Desde el principio» van
    /// debajo) y cuatro acciones del mismo tamaño: Guardar, Descargar, Tráiler y Fuente. Cada una cambia en su lugar (Guardada,
    /// el anillo de la descarga): nada brinca.
    private func actions(_ model: TitleModel) -> some View {
        VStack(spacing: DS.Space.s4) {
            continueAction(model)
            debridWhere(model)   // mientras Real-Debrid lo baja: dónde y cómo (3 nov, la 1729)
            // Con letra de accesibilidad, en dos columnas (en un renglón los nombres se encimaban: «Guardada Descargar»).
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2, alignment: .top), count: typeSize.isAccessibilitySize ? 2 : (model.extras?.trailer?.url == nil ? 3 : 4) + (model.kind == "movie" || AppEnvironment.shared.follow.available ? 1 : 0)),
                      spacing: DS.Space.s2) {
                if model.kind == "movie" { watchedAction(model).frame(maxWidth: .infinity) }
                else if AppEnvironment.shared.follow.available { followAction(model).frame(maxWidth: .infinity) }   // series: seguirla o no
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
        .disabled(target == nil || (model.debridOffer != nil && model.recommendedSource?.instant != true))   // IOS-17, R2-A: con «Pedirlo y avisarme», apagado
        .accessibilityIdentifier("title-download")
    }

    /// Un toque: la recomendada (la mejor en calidad, idioma y tamaño), y un aviso que dice cuál y deja elegir otra.
    private func downloadRecommended(_ model: TitleModel, videoID: String? = nil) async {
        guard let target = videoID ?? model.downloadTarget else { return }
        let outcome = await model.download([target])
        guard case .queued = outcome else { return await report(outcome, model, videoID: target) }
        let item = await model.existingDownload(target)
        let size = item?.expectedBytes.map { ByteSize.text($0, locale: env.uiLocale) }
        let detail = [item?.quality, size].compactMap { $0 }.joined(separator: " · ")
        let what = model.episodeLabel(target)
        env.notify(what.map { String(format: Strings.tr("Bajando %@", language: env.services.appSettings.uiLanguage), $0) } ?? "Bajando la recomendada",
                   detail: detail.isEmpty ? nil : detail, actionTitle: "Otra") {
            sourcesFor = SourcesTarget(videoID: target, purpose: .download)
        }
    }

    /// La temporada: lista desplegable si hay varias; si es una sola, su nombre.
    @ViewBuilder private func seasonControl(_ model: TitleModel) -> some View {
        if model.seasons.count > 1 {
            DSSeasonMenu(seasons: model.seasons.map(\.season), selection: Binding(get: { model.selectedSeason }, set: { model.select(season: $0) }))
        } else if let only = model.seasons.first {
            Text(only.isSpecials ? "Especiales" : "Temporada \(only.season)").recipe(.labelLarge, color: DS.text)
        }
    }

    /// La versión de la serie (lo que recuerda: latino, castellano, inglés…); tocarla elige otra «desde aquí».
    @ViewBuilder private func seriesVersion(_ model: TitleModel, wanted: String) -> some View {
        if let next = model.continueVideoID {
            Button { sourcesFor = SourcesTarget(videoID: next, purpose: .watch, fromHere: true) } label: {
                // La bandera y el idioma, sin el ícono de lista (Fernando, 2 nov 2026, N2: la bandera ya dice qué es, como en el
                // renglón bajo «Continuar»).
                HStack(spacing: DS.Space.s2) {
                    // «es» es «cualquier español» (lo que pediste), no una versión que no dice cuál.
                    Text("\(Text.flag(wanted))\(Text(verbatim: wanted == "es" ? Strings.tr("Español", language: env.services.appSettings.uiLanguage) : Streams.versionLanguageName(wanted, in: env.services.appSettings.uiLanguage)))")
                        .recipe(.labelLarge, color: DS.text).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted)
                }
            }
            .dsSecondaryButton()
            .accessibilityLabel(Text("Versión de la serie"))
            .accessibilityIdentifier("series-version")
        }
    }

    @ViewBuilder private func episodes(_ model: TitleModel) -> some View {
        // Un solo renglón de controles: a la izquierda la temporada en lista desplegable (Fernando, 1 nov 2026: las cápsulas
        // «T1, T2…» van solo en el reproductor; la misma pieza que Mi media y la hoja de episodios) y a la derecha la versión de
        // la serie, su cápsula gemela; abajo, el avance de la temporada.
        let wanted = env.services.titlePrefs.languages(for: model.metaID, settings: env.services.appSettings).prefs.wanted
        if !model.seasons.isEmpty || model.continueVideoID != nil {
            // Con letra grande no caben juntas: la versión baja a su renglón.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s2) { seasonControl(model); Spacer(minLength: DS.Space.s2); seriesVersion(model, wanted: wanted) }
                VStack(alignment: .leading, spacing: DS.Space.s2) { seasonControl(model); seriesVersion(model, wanted: wanted) }
            }
        }
        // Cuántos llevas de esta temporada y marcarla completa (como en Infuse y Trakt), con su barra.
        let progress = model.seasonProgress
        if progress.total > 0 {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack {
                    Text("\(progress.watched) de \(progress.total) vistos").recipe(.footnote)
                    Spacer()
                    Menu {
                        Button("Solo la temporada \(model.selectedSeason)", systemImage: "checkmark.circle") { marking = .season(model.selectedSeason) }
                        Button("Toda la serie", systemImage: "checkmark.rectangle.stack") { marking = .series }
                    } label: { Label("Marcar como vista", systemImage: "checkmark.circle").font(DS.TextRecipe.footnote.font) }
                    .accessibilityIdentifier("season-mark-watched")
                }
                ProgressView(value: Double(progress.watched), total: Double(progress.total)).tint(DS.accent)
            }
        }
        let _ = env.ratings.track()   // tus estrellas de cada capítulo: calificar uno vuelve a pintar la lista
        if sizeClass == .regular {
            // iPad y Mac (FE2-B): los episodios en una fila que sale por la orilla, como la TV.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s4) {
                    ForEach(model.rows) { row in episodeRow(model, row, card: true) }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, side, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .padding(.horizontal, -side)
        } else {
        LazyVStack(spacing: 0) {   // perezosa: una serie larga no arma (ni pide imágenes de) todos sus episodios a la vez
            ForEach(model.rows) { row in
                EpisodeRowView(row: row, play: { if row.airs == nil { start(model, videoID: row.id) } }, download: { Task { await downloadRecommended(model, videoID: row.id) } },
                               markWatched: { marking = .episode(row.id) }, chooseSource: { sourcesFor = SourcesTarget(videoID: row.id, purpose: .watch) },
                               resumeDownload: { Task { await model.resumeDownload(row.id) } },
                               downloadFraction: model.downloadFraction(row.id),
                               playOnTV: env.services.orbital.isConfigured ? { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: row.id, title: model.title) } } : nil,
                               rating: env.ratings.stars(row.id), rate: rateEpisode(model, row.id), accent: artAccent)
                Divider().overlay(DS.hairline)
            }
        }
        }
    }

    /// Un episodio como tarjeta (la fila del iPad y la Mac).
    private func episodeRow(_ model: TitleModel, _ row: EpisodeRow, card: Bool) -> some View {
        EpisodeRowView(row: row, play: { if row.airs == nil { start(model, videoID: row.id) } }, download: { Task { await downloadRecommended(model, videoID: row.id) } },
                       markWatched: { marking = .episode(row.id) }, chooseSource: { sourcesFor = SourcesTarget(videoID: row.id, purpose: .watch) },
                       resumeDownload: { Task { await model.resumeDownload(row.id) } },
                       downloadFraction: model.downloadFraction(row.id),
                       playOnTV: env.services.orbital.isConfigured ? { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: row.id, title: model.title) } } : nil,
                       rating: env.ratings.stars(row.id), rate: rateEpisode(model, row.id), accent: artAccent, card: card)
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
                        .font(DS.TextRecipe.label.font).foregroundStyle(artAccent).buttonStyle(.plain)
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
                DSSectionHead(title: "Detalles", eyebrow: Text("Los datos de la ficha"))
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

    private static let day: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()   // ds-exception: lee fechas de TMDB, no escribe texto

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
        VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
            if let trailer = x.trailer {
                section(title: "Tráiler y extras", meta: Text("Para verla antes de verla")) {
                    VideoClipCard(clip: trailer)
                    ForEach(x.extras) { VideoClipCard(clip: $0) }
                }
            }
            let people = x.crew + x.cast
            if !people.isEmpty {
                section(title: "Reparto y equipo", meta: Text("Quién sale y quién la hizo")) {
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
                section(title: "Más como esto", meta: Text("Si te gusta esta")) { ForEach(x.recommendations) { TmdbPoster(title: $0) } }
            }
        }
    }

    private func section<Content: View>(title: LocalizedStringKey, meta: Text, count: Int? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: title, count: count, meta: meta).padding(.horizontal, side)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) { content() }.scrollTargetLayout().environment(\.posterCaptions, false)
            }
            .contentMargins(.horizontal, side, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    /// El margen de los lados: el del iPhone, o el de la TV en el iPad y la Mac (FE2-B). Las filas salen por la orilla.
    private var side: CGFloat { sizeClass == .regular ? DS.TitleAction.wideSide : DS.Space.gutter }

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
