import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons

/// La ficha de una película o serie: continuar, guardar (en Mi lista, tu watchlist o tus listas), descargar, temporadas y episodios.
struct TitleView: View {
    @Environment(\.titleName) var titleName
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let route: TitleRoute
    /// Opcional a propósito: al mantener presionado un póster, iOS arma la ficha (y los botones de su barra) en un árbol
    /// que todavía no tiene el entorno de la app, y uno obligatorio tiraba la app (R1, 31 oct 2026; `ToolbarEnvironmentTests`).
    @Environment(AppEnvironment.self) private var appEnv: AppEnvironment?
    var env: AppEnvironment { appEnv ?? .shared }
    /// Sin `@Environment(\.dismiss)` aquí (V9): cambia con cada movimiento de la pila y llegó a pintar la ficha 69 veces seguidas
    /// al abrirla. Quien cierra la ficha lee `dismiss` en su propia pieza (`DismissWhen`).
    @State private var closing = false
    @Environment(\.dynamicTypeSize) var typeSize
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var windowSizeClass
    @Environment(\.titleInPanel) var inPanel
    /// En el panel de la derecha de la Mac (FI-B), siempre la ficha de una columna. No basta con poner `.compact` en el entorno:
    /// la pila de navegación del panel lo vuelve a tomar de la ventana, y la ficha ancha en un panel angosto se medía sin fin
    /// (la app se trabó al abrir una ficha, 22 nov 2026).
    var sizeClass: UserInterfaceSizeClass? { inPanel ? .compact : windowSizeClass }
    /// La pestaña elegida bajo el arte en el iPad y la Mac (nil: la primera que haya).
    @State private var wideTab: WideTab?
    /// Lo que dice Letterboxd de la película (su promedio y sus reseñas populares); las series casi nunca están.
    @State var letterboxdInfo: LetterboxdFilmInfo?
    @State private var observer: ModelObserver<TitleModel>
    @State var tint = ArtTint()
    @State var sourcesFor: SourcesTarget?
    @State var rewatch: EpisodeRow?   // EV1: el visto que tocaste («Ya lo viste»)
    /// Elegiste otra fuente para algo que ya tienes descargado: ¿cambiarla?
    @State var replacing: Replacement?

    struct Replacement { var source: Source; var videoID: String; var existing: DownloadItem }
    /// Real-Debrid: la hoja de un pedido, «¿Qué es esto?» o la línea antes de pedir permiso de avisos (`TitleView+RealDebrid`).
    @State var debridSheet: TitleDebridSheet?
    /// IOS-7 · el pedido que se va a cancelar desde el botón de la ficha (pregunta antes, como la hoja).
    @State var cancelling: DebridRequest?
    var observerModel: TitleModel { observer.model }
    func openVersions(_ videoID: String) { sourcesFor = SourcesTarget(videoID: videoID, purpose: .watch) }
    @State var saving = false
    /// «¿Cuándo la viste?»: qué se está marcando (la película, un episodio, la temporada o la serie).
    @State var marking: WatchedScope?
    /// «Tus vistas» (gestor ola 3): de qué película o capítulo; y la hoja de «Tu nota».
    @State var viewingsFor: ViewingsTarget?
    @State var noting = false
    /// La temporada que calificas desde «Vista» (G7-A, F1).
    @State var ratingSeason: Int?
    /// Lo que mide la pantalla visible (sin la barra de pestañas) y lo que hay bajo el arte hasta las acciones: el arte
    /// se ajusta para que «Ver», Guardar, Descargar y Fuente queden a la vista al abrir, en un SE y en un Pro.
    @State private var measure = TitleMeasure()
    /// En la Mac las tres medidas (pantalla, margen de arriba, lo de bajo el arte) llegan juntas: cada una por su lado volvía
    /// a pintar y acomodar la ficha entera, tres veces seguidas al abrirla (~90 ms; 24 nov 2026). Ver `TitleMeasure`.
    @State private var measureBox = TitleMeasure.Box()
    private var viewport: CGSize { measure.viewport }
    private var belowHero: CGFloat { measure.belowHero }
    /// Lo de abajo de la ficha (episodios, reparto, detalles) se arma cuando la ficha ya llegó, no en el mismo cuadro del
    /// toque: así el toque responde al momento (en la Mac armar todo junto congelaba 250–400 ms al abrir; 24 nov 2026).
    @State private var belowFold = false
    /// Cuánto has deslizado (0 arriba) y el alto de la barra de arriba: el arte se recoge y lo que sube se desvanece.
    var topInset: CGFloat { measure.topInset }

    struct SourcesTarget: Identifiable { var videoID: String; var purpose: Purpose; var fromHere = false; var id: String { "\(videoID)-\(purpose)" } }

    init(route: TitleRoute) {
        self.route = route
        _observer = State(wrappedValue: ModelObserver(TitleModel(AppEnvironment.shared.services, kind: route.kind, metaID: route.metaID, hint: (route.title, route.poster))))
    }

    /// Guarda una medida. En la Mac se juntan las que llegan en la misma vuelta y se aplican una vez (el panel entra desde
    /// fuera de la pantalla: esa vuelta no se ve); en el iPhone y el iPad, al momento, como siempre.
    private func measured(_ change: (inout TitleMeasure) -> Void) {
        guard ThisDevice.isMac else { change(&measure); return }
        measureBox.add(to: measure, change) {
            #if MAC_DRIVE
            MacDrive.state("measure")
            #endif
            measure = $0
        }
    }

    /// La ficha con su arte, su barra y su fondo. En partes (`framed`, `loaded`): el cuerpo de una sola pieza no lo alcanzaba
    /// a revisar el Swift de la CI (Xcode 26.3).
    private func framed(_ model: TitleModel) -> some View {
        Group {
            // iPad y Mac (Fernando, 4 nov 2026, FE1): la ficha de la TV como esqueleto; el iPhone sigue en una columna.
            // Cada forma en su propia vista y con su tipo borrado (`TitleLayoutHost`): al girar el iPhone con el reproductor
            // abierto, la ficha de abajo se volvía a armar dentro de la pila del giro y se acababa la pila (EXC_BAD_ACCESS,
            // Fernando, 23 nov 2026; el mismo cierre que el del 11 nov). Su propia vista se arma aparte, con su pila.
            if sizeClass == .regular { TitleLayoutHost { AnyView(wideLayout(model)) } } else { TitleLayoutHost { AnyView(oneColumnLayout(model)) } }
        }
        #if DEBUG
        .modifier(DemoScroll())   // `-demo-scroll N`: abre ya desplazada (capturas del arte a medio recoger)
        #endif
        .onGeometryChange(for: CGSize.self) { $0.size } action: { new in measured { $0.viewport = new } }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { new in measured { $0.topInset = new } }
        // Lo de arriba que sigue al desplazamiento va aparte (`TitleScrollChrome`): antes cada cuadro del desplazamiento
        // volvía a pintar toda la ficha (capítulos, detalles), y regresar con el gesto se trababa.
        // En el iPad y la Mac la barra de pestañas ocupa ese renglón: el nombre no sube a la barra (se encimaba).
        .modifier(TitleScrollChrome(topInset: topInset, heroHeight: heroHeight, logo: sizeClass == .regular ? nil : model.logo(shown: titleName(model.title, id: model.metaID, kind: model.kind)),
                                    title: sizeClass == .regular ? "" : model.title,
                                    buttons: (env.services.orbital.isConfigured ? 1 : 0) + (model.metaID.hasPrefix("tt") ? 1 : 0)))
        // El color del arte solo como un brillo arriba (antes toda la ficha se lavaba de ese tono): el arte manda. En el iPad y
        // la Mac, el fondo de la sala, el mismo que hay bajo el arte: lo que sube bajo la barra se desvanece hacia él, sin la
        // franja del tono que cortaba el arte (AR1, 13 nov 2026).
        .background { if sizeClass == .regular { DS.backdropDeep.ignoresSafeArea() } else { Backdrop(tint: tint.colors) } }
        // iPad y Mac (FE1): siempre oscura, como la sala de la TV; el arte no se corta contra un fondo claro.
        .environment(\.colorScheme, sizeClass == .regular ? .dark : scheme)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)     // el arte llega hasta arriba y la barra flota encima
        .toolbar { topBar(model) }
        // Teclado y barra de menús (iPad, Mac): ⌘↩ ver, ⌘D guardar, ⌥⌘V versión (`AppCommands`).
        .focusedSceneValue(\.titleCommands, TitleCommands(kind: model.kind, metaID: model.metaID,
                                                           play: { let go = continueAction(model); if go.enabled { go.play() } },
                                                           save: { saving = true }, versions: { if let v = model.continueVideoID { openVersions(v) } }))
    }

    /// Lo que la ficha sigue mientras está abierta (aparte de `loaded`: juntas tardaban en revisarse, V9).
    private func following(_ model: TitleModel) -> some View {
        framed(model)
        .task { await model.followDownloads() }
        // F3: la primera vez que abres una ficha (si nunca has visto nada aquí), el foco en «Ver».
        .learnCoach(.titlePlay, title: "«Ver» elige la mejor versión en tu idioma.", detail: "Si quieres otra, toca la bandera, a la derecha de «Ver».",
                    used: env.services.library.all.contains { $0.position > 0 || !$0.seen.isEmpty })
        // De vuelta a la app (quizá viste algo en la TV): lo visto, por dónde vas y lo que sigue, al día.
        .onChange(of: appEnv?.ui.returnedToApp) { Task { await model.refreshState() } }
        .task(id: model.metaID) {   // Letterboxd es de películas: las series no se preguntan
            guard route.kind == "movie" else { return }
            let info = await Letterboxd(http: env.services.http, kv: env.services.kv).info(imdb: model.metaID)
            if info != letterboxdInfo { letterboxdInfo = info }   // sin reseñas no hay nada que volver a pintar
        }
        .task { await model.loadConsoleDetails() }
        // Lo de abajo, cuando la ficha ya llegó (ver `belowFold`). Solo la ficha de una columna lo usa: en la ancha (iPad, Mac)
        // prenderlo volvía a armar la ficha entera a los 0.3 s sin cambiar nada a la vista.
        .task(id: sizeClass == .regular) {
            guard sizeClass != .regular, !belowFold, (try? await Task.sleep(for: .seconds(DesignTokens.Motion.slow))) != nil else { return }
            belowFold = true
        }
        .task { await model.loadExtras(); if model.extras != nil { Perf.mark("title.extras") } }     // la ficha rica: elenco con foto, saga, tráiler, frase y detalles (TMDB)
        .onChange(of: env.watchedSomething) { Task { await model.refreshState() } }   // vuelves de ver: avance, visto y «Continuar» al día
        .modifier(RewatchCard(row: $rewatch, version: rewatchVersion(model), again: { startEpisode(model, videoID: $0) }, versions: openVersions, unwatch: { id in Task { await model.unmarkWatched(id) } }))
    }

    /// Lo que la ficha carga al abrir.
    private func loaded(_ model: TitleModel) -> some View {
        following(model)
        .modifier(DismissWhen(closing: closing))
        .task {
            await model.load()
            Task { await model.loadBestSource(onCellular: env.connectivity.isCellular); if model.bestSource != nil { Perf.mark("title.sources") } }   // aparte: las fuentes tardan y no detienen el color del fondo
            if let video = route.versionsFor { sourcesFor = SourcesTarget(videoID: video, purpose: .watch) }   // «Probar otra versión» desde «Tus pedidos»
            #if DEBUG
            if Demo.isOn, Demo.open == "play" { start(model, videoID: nil) }
            if Demo.isOn, ["sources", "sources-all", "sources-request", "sources-series"].contains(Demo.open ?? ""), let v = model.continueVideoID { sourcesFor = SourcesTarget(videoID: v, purpose: .watch) }
            if Demo.isOn, Demo.open == "download" || Demo.open == "download-here" { await report(model.download([model.continueVideoID ?? model.metaID]), model); if Demo.open == "download" { closing = true } }
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
            #if MAC_DRIVE
            MacDrive.state("tint")
            #endif
        }
    }

    var body: some View {
        let _ = BodyCount.tick("title", why: Self._printChanges)   // V9: cuántas veces se pinta y por qué (`-perf-bodies`, `-perf-why`)
        let model = observer.model
        #if MAC_DRIVE
        let _ = MacDrive.body("title")
        #endif
        loaded(model)
        .appSheet(item: $sourcesFor) { target in
            SourcesSheet(model: model, videoID: target.videoID, fromHere: target.fromHere, choose: { source, purpose in
                sourcesFor = nil
                handle(source: source, videoID: target.videoID, purpose: purpose, model: model)   // lo que quedó en el selector de la hoja
            }, infuse: { source in
                sourcesFor = nil
                if let request = model.playRequest(videoID: target.videoID) { Task { await env.playExternal(request, source: source) } }
            }, request: env.services.debridRequests.canRequest ? { source in await sendRequest(model, source: source, videoID: target.videoID) } : nil)
            .presentationDragIndicator(.visible)   // el alto lo pone la hoja (`VersionSheetSizing`)
        }
        .appSheet(isPresented: $saving) { SaveView(observer: observer).fittedSheet() }
        .appSheet(item: $debridSheet) { kind in debridSheetContent(kind, model) }
        // RX3-A: «Pedir a la nube» a la vista; y si un pedido cambió de estado (quedó listo, lo cancelaste), la versión y el botón
        // se ponen al día. Aparte (`TitleDebridFollow`): leer el pedido aquí rearmaba toda la ficha cuando llegaban las versiones.
        .modifier(TitleDebridFollow(model: model) { Task { await model.loadBestSource(onCellular: env.connectivity.isCellular) } })
        .task { _ = await DebridRequestNotifier.permission() }   // IOS-8: sin permiso no se promete «Te aviso»
        .debridCancelConfirmation(isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
                                  name: cancelling?.title ?? "", finished: false,
                                  service: cancelling?.cloud ?? env.services.debrid.service, locale: env.uiLocale) { if let request = cancelling { Task { await cancelRequest(request) } } }
        .modifier(TitleWatchedWhen(model: model, scope: $marking))
        .modifier(TitleViewingsAndNote(model: model, viewingsFor: $viewingsFor, noting: $noting, ratingSeason: $ratingSeason))
        .appSheet(isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })) {
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
                // Al deslizar, el arte se funde (`BleedArt(collapses:)`): ver `hero`. Con su tipo borrado, como lo de abajo: el
                // anidado de la columna no carga el del arte (el cierre EXC_BAD_ACCESS del 11 nov).
                AnyView(hero(model))
                    .perfTag("title.hero").onAppear { Perf.mark("title.shown") }
                VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                    // Tipos borrados a propósito (11 nov 2026): el cierre EXC_BAD_ACCESS de esta columna salía al copiar el tipo
                    // anidado de datos + acciones + secciones; cada pedazo con su propio tipo lo acota (`TitleFactsLine`).
                    AnyView(VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                        facts(model)
                        TitleLayoutHost { AnyView(actions(model)) }   // aparte: las versiones llegan tarde y solo rearman esto
                    })
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { new in measured { $0.belowHero = new } }
                    AnyView(readingSections(model))
                }
                .modifier(TitleEntrance())   // el arte llega con el zoom; lo de abajo entra detrás de él
                .padding(.horizontal, side).padding(.bottom, DS.Layout.screenBottom)
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
                // La receta (`WideStage`): un escenario centrado de 2.4:1 como mucho; a los lados, el mismo arte difuminado.
                let stage = wideStage
                let name = titleName(model.title, id: model.metaID, kind: model.kind)
                ZStack(alignment: stage.portrait ? .bottom : .bottomLeading) {
                    if stage.hasSides { StageSides(url: model.background ?? model.poster) }
                    // Al bajar, el arte se recoge como en el iPhone.
                    BleedArt(url: model.background ?? model.poster, title: name, collapses: true, fallback: model.poster, fadesTop: false) { EmptyView() }
                        .frame(width: stage.width)
                        .mask(StageEdges(on: stage.hasSides))
                        .frame(maxWidth: .infinity)
                        .overlay { if !stage.portrait { ArtVeil(kind: .leading, strength: .deep) } }
                        .overlay { ArtVeil(kind: .bottom, at: stage.portrait ? DS.TitleAction.wideVeilFrom * 0.8 : DS.TitleAction.wideVeilFrom,
                                           until: DS.TitleAction.wideVeilSolid, strength: .deep) }
                    let column = typeSize.isAccessibilitySize ? DS.TitleAction.readableWidth : DS.TitleAction.wideColumn * stage.grow   // letra grande: más ancho, no cuatro botones apretados
                    if wideBand {
                        // M2: la banda de cine a dos columnas. A la izquierda lo que se hace; a la derecha lo que se lee.
                        // La sinopsis arranca a la altura de «Ver» (`.bandAnchor`), no flota por la base.
                        HStack(alignment: .bandAnchor, spacing: DS.TitleAction.bandGap) {
                            VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                                TitleLogo(url: model.logo(shown: name), title: name, size: .hero, grow: stage.grow)
                                    .frame(maxWidth: DS.TitleAction.wideLogoWidth * stage.grow, alignment: .leading)
                                facts(model, leading: true)
                                TitleLayoutHost { AnyView(actions(model)) }.alignmentGuide(.bandAnchor) { $0[.top] }
                            }
                            .frame(width: column, alignment: .leading)
                            synopsis(model, lines: DS.TitleAction.bandSynopsisLines)
                                .frame(minWidth: DS.TitleAction.bandSynopsisMin, maxWidth: DS.TitleAction.bandReading, alignment: .leading)
                                .alignmentGuide(.bandAnchor) { $0[.top] }
                        }
                        .padding(.horizontal, side).padding(.bottom, DS.Layout.betweenSections)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: stage.portrait ? .center : .leading, spacing: DS.Layout.betweenSubsections) {
                            TitleLogo(url: model.logo(shown: name), title: name, size: .hero, centered: stage.portrait, grow: stage.grow)
                                .frame(maxWidth: DS.TitleAction.wideLogoWidth * stage.grow, alignment: stage.portrait ? .center : .leading)
                            facts(model, leading: !stage.portrait)
                            TitleLayoutHost { AnyView(actions(model)) }
                            synopsis(model, centered: stage.portrait)
                        }
                        .frame(maxWidth: column, alignment: stage.portrait ? .center : .leading)
                        .padding(.horizontal, stage.portrait ? DS.TitleAction.wideSide : side).padding(.bottom, DS.Layout.betweenSections)
                        .frame(maxWidth: .infinity, alignment: stage.portrait ? .center : .leading)
                    }
                }
                // El arte sube detrás del reloj y de la barra, como en la TV.
                .frame(height: viewport.height * wideHeroShare + topInset)
                .padding(.top, -topInset)
                VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                    wideSections(model)
                }
                .modifier(TitleEntrance())
                .padding(.horizontal, side).padding(.top, DS.Space.s4).padding(.bottom, DS.Layout.screenBottom)
            }
        }
        // El fondo de la sala, el mismo color al que baja el velo del arte: sin la línea donde terminaba el arte.
        .background(DS.backdropDeep.ignoresSafeArea())
    }

    /// Bajo el arte, como en la TV: pestañas (Episodios · Reparto y equipo · Más como esto · Detalles) y solo lo de la elegida.
    @ViewBuilder private func wideSections(_ model: TitleModel) -> some View {
        if let message = model.message { DSNotice(verbatim: env.message(message), tone: .error) }
        if let error = model.error, !model.isLoading {
            DSNotice(verbatim: env.message(error), tone: .warn)   // «Reintentar» es el botón principal (OI-3)
        }
        if ThisDevice.isMac { macSections(model) } else { tabbedSections(model) }
    }

    /// RF2 (Fernando, 16 nov 2026: «hazlo de acuerdo a tus sugerencias»): en la Mac no hay pestañas bajo el arte. Todo va en
    /// filas a lo ancho, como la TV: episodios, reparto, tus datos y las reseñas en columnas, parecidas y detalles. Con pestañas,
    /// una película sin reparto dejaba dos tercios de la ventana vacíos.
    @ViewBuilder private func macSections(_ model: TitleModel) -> some View {
        if model.kind == "series" { episodes(model) }
        if let extras = model.extras { rich(extras, similar: false).padding(.horizontal, -side) }
        VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
            creditLine(model)
            yourRating(model)
            yourViewings(model)
            if let review = env.letterboxdReview(model.metaID) { LetterboxdReviewCard(entry: review, watched: LetterboxdWords.watched(review, language: env.services.appSettings.uiLanguage)) }
        }
        .frame(maxWidth: DS.TitleAction.wideReading, alignment: .leading)
        if let info = letterboxdInfo, !info.reviews.isEmpty {
            LetterboxdPublicReviews(reviews: info.reviews, link: info.slug.flatMap { URL(string: "\(Letterboxd.site)/film/\($0)/reviews/by/activity/") },
                                    columns: DS.Mac.reviewColumns)
        }
        if let extras = model.extras { rich(extras, trailers: false, people: false).padding(.horizontal, -side) }
        TitleLayoutHost { AnyView(details(model)) }   // lee la versión, que llega tarde
    }

    /// iPad: pestañas bajo el arte (Episodios · Reparto y equipo · Más como esto · Detalles) y solo lo de la elegida.
    @ViewBuilder private func tabbedSections(_ model: TitleModel) -> some View {
        let tabs = WideTab.available(series: model.kind == "series", extras: model.extras)
        let current = wideTab.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs.first ?? .details
        // Con una sola (una película sin reparto ni parecidas) `DSTextTabs` no se dibuja.
        DSTextTabs(options: tabs.map { DSTextTabs.Option(id: $0, title: $0.title, symbol: $0.symbol) },
                   selection: Binding(get: { current }, set: { wideTab = $0 }))
            .accessibilityIdentifier("title-tabs")
        switch current {
        case .episodes: episodes(model)
        case .cast: if let extras = model.extras { rich(extras, trailers: false, similar: false, headed: false).padding(.horizontal, -side) }
        case .similar: if let extras = model.extras { rich(extras, trailers: false, people: false).padding(.horizontal, -side) }
        case .details:
            // Lo que se lee, a un ancho de lectura: en la Mac las reseñas iban de orilla a orilla en un solo renglón larguísimo.
            VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
                creditLine(model)
                yourRating(model)
                yourViewings(model)
                if let review = env.letterboxdReview(model.metaID) { LetterboxdReviewCard(entry: review, watched: LetterboxdWords.watched(review, language: env.services.appSettings.uiLanguage)) }
                if let info = letterboxdInfo, !info.reviews.isEmpty {
                    LetterboxdPublicReviews(reviews: info.reviews, link: info.slug.flatMap { URL(string: "\(Letterboxd.site)/film/\($0)/reviews/by/activity/") })
                }
            }
            .frame(maxWidth: DS.TitleAction.wideReading, alignment: .leading)
            if let extras = model.extras { rich(extras, people: false, similar: false).padding(.horizontal, -side) }
            TitleLayoutHost { AnyView(details(model)) }
        }
    }

    /// Lo que se lee bajo las acciones: avisos, sinopsis, créditos, episodios, la ficha rica y los detalles.
    @ViewBuilder private func readingSections(_ model: TitleModel, withSynopsis: Bool = true) -> some View {
        if let message = model.message { DSNotice(verbatim: env.message(message), tone: .error) }
        if let error = model.error, !model.isLoading {
            // No cargó (sin red, Cinemeta caído): lo dice, y el botón principal dice «Reintentar» (antes «Cargando» se quedaba para siempre).
            DSNotice(verbatim: env.message(error), tone: .warn)   // «Reintentar» es el botón principal (OI-3)
        }
        if withSynopsis { synopsis(model) }
        creditLine(model)
        yourRating(model)
        yourViewings(model)
        // Tu reseña en Letterboxd (si la conectaste y la reseñaste o calificaste).
        if let review = env.letterboxdReview(model.metaID) { LetterboxdReviewCard(entry: review, watched: LetterboxdWords.watched(review, language: env.services.appSettings.uiLanguage)) }
        if let info = letterboxdInfo, !info.reviews.isEmpty {
            LetterboxdPublicReviews(reviews: info.reviews, link: info.slug.flatMap { URL(string: "\(Letterboxd.site)/film/\($0)/reviews/by/activity/") })
        }
        // Lo de abajo (episodios, reparto, saga, parecidas, detalles) se arma cuando llegó la ficha (`belowFold`), en una pila
        // normal: son tres bloques grandes y una pila perezosa adivinaba su alto. Con Endgame la ficha se «soltaba»: seguía
        // bajando a un hueco vacío y luego brincaba para arriba (Fernando, 26 nov 2026). Los episodios ya son perezosos
        // adentro (`episodes`), que es lo que de verdad pesa.
        if belowFold { VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) { belowTheFold(model) } }
    }

    /// Lo de más abajo de la ficha: se arma después de que la ficha llegó (`belowFold`).
    @ViewBuilder private func belowTheFold(_ model: TitleModel) -> some View {
        if model.kind == "series" { episodes(model) }
        // Sin TMDB, los créditos ya van en el renglón de arriba (antes salían dos veces: «Dirección · Con» y otra vez
        // «Reparto · Dirección · Guion»).
        if let extras = model.extras { rich(extras).padding(.horizontal, -side) }
        TitleLayoutHost { AnyView(details(model)) }   // lee la versión, que llega tarde
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
        let room = viewport.height - belowHero - padding - DS.Space.s2
        let width = contentWidth - (scheme == .dark ? 0 : side * 2)
        guard room > 0 else { return typeSize.isAccessibilitySize ? DS.TitleAction.heroAspectMaxLarge : DS.TitleAction.heroAspectMax }
        let cap = typeSize.isAccessibilitySize ? DS.TitleAction.heroAspectMaxLarge : DS.TitleAction.heroAspectMax
        return min(cap, max(DS.TitleAction.heroAspect, width / room))
    }

    private var heroHeight: CGFloat { contentWidth > 0 ? contentWidth / heroAspect : 0 }
    /// El ancho de la ficha: el de la ventana, hasta el ancho de lectura (`DS.TitleAction.readableWidth`).
    /// La receta de la ficha ancha para esta ventana (`WideStage`).
    var wideStage: WideStage {
        WideStage(window: viewport, heroHeight: viewport.height * wideHeroShare + topInset, stageAspect: DS.TitleAction.stageAspect,
                  portraitBelow: DS.TitleAction.portraitBelow, marginShare: DS.TitleAction.stageMarginShare, minMargin: DS.TitleAction.wideSide,
                  maxMargin: DS.TitleAction.stageMarginMax, growFrom: DS.TitleAction.stageGrowFrom, growMax: DS.TitleAction.stageGrowMax,
                  column: DS.TitleAction.wideColumn)
    }

    /// M2: la banda a dos columnas en ventanas anchas y acostadas (Mac, iPad acostado), salvo con letra de accesibilidad.
    /// Solo si la sinopsis cabe con su ancho mínimo junto a la columna (en ~1100–1300 pt quedaba apretada, en cuatro renglones
    /// cortados): si no, la columna de siempre.
    var wideBand: Bool {
        let room = viewport.width * (1 - 2 * DS.TitleAction.stageMarginShare) - DS.TitleAction.wideColumn - DS.TitleAction.bandGap
        return viewport.width >= DS.TitleAction.bandFrom && room >= DS.TitleAction.bandSynopsisMin
            && viewport.width >= viewport.height * DS.TitleAction.portraitBelow && !typeSize.isAccessibilitySize
    }

    /// Lo alto del arte: más bajo con la banda, para que la primera fila se asome sin desplazar.
    var wideHeroShare: CGFloat { wideBand ? DS.TitleAction.bandHeroShare : DS.TitleAction.wideHeroShare }
    var contentWidth: CGFloat { min(viewport.width, DS.TitleAction.readableWidth) }

    /// En la TV y Compartir: botones de ícono en la barra de arriba (con su nombre para VoiceOver). El corazón ya no va aquí
    /// (I7): favoritos entra por la misma puerta que Mi lista y tus listas, «Guardar en…».
    @ToolbarContentBuilder private func topBar(_ model: TitleModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if env.services.orbital.isConfigured {
                // Mientras va en camino, la ruedita en su lugar (y el aviso abajo): antes el toque no enseñaba nada.
                Button { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: model.continueVideoID, title: model.title,
                                                         source: model.chosenSource(for: nil)) } } label: {
                    if env.isSendingToTV(model.metaID) { ProgressView() } else { Image(systemName: "tv.and.mediabox") }   // ds-exception: la ruedita va dentro del botón que la pidió
                }
                    .disabled(model.continueVideoID == nil || env.isSendingToTV(model.metaID))
                    .dsFeedback(.impact(flexibility: .soft), trigger: env.isSendingToTV(model.metaID)) { _, sending in sending }
                    .accessibilityLabel(Text("Ver en la TV"))
            }
            // «Guardar» vive en la rejilla de acciones; arriba, compartir (la ficha de IMDb, que abre en cualquier app).
            if model.metaID.hasPrefix("tt"), let url = URL(string: "https://www.imdb.com/title/\(model.metaID)/") {
                ShareLink(item: url, subject: Text(verbatim: titleName(model.title, id: model.metaID, kind: model.kind))) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(Text("Compartir"))
            }
        }
    }

    var artAccent: Color { tint.colors?.accent ?? DS.accent }
    /// El color del arte para letra sobre el fondo: en claro, oscurecido como en las acciones (`TitleActions`); el tono claro
    /// sobre papel no pasaba el contraste AA (I13, «más» de la sinopsis). En el iPad y la Mac la ficha siempre es oscura.
    var artInk: Color { scheme == .light && sizeClass != .regular ? artAccent.mix(with: DS.backdropDeep, by: DS.TitleAction.lightTextDeepen) : artAccent }

    /// El botón principal (`ContinueAction`: el botón dice una sola cosa y, partido, la versión que va a sonar; el avance y ↺
    /// «Desde el principio» en una línea debajo, R1) y una sola fila de mosaicos de un renglón (F1, Fernando, 12 nov 2026: «Me
    /// gusta la F1»): Guardar · Descargar · Vista · Tráiler. Cada uno cambia en su lugar (Guardada, el anillo de la descarga,
    /// Vista en verde): nada brinca. «Versión» se abre desde la zona derecha de «Ver» (L3, 11 nov).
    private func actions(_ model: TitleModel) -> some View {
        VStack(spacing: DS.Space.s4) {
            continueAction(model)
            debridWhere(model)   // mientras Real-Debrid lo baja: dónde y cómo (3 nov, la 1729)
            // Los cuatro en un renglón si sus nombres caben enteros; si no (SE con letra grande, letra de accesibilidad), 2×2.
            // Nunca se achica la letra para que quepan.
            if roundTiles {
                // A1: los círculos de orilla a orilla del botón (con `ActionTileRow` quedaban hacia adentro).
                SpreadRow { actionTiles(model) }
            } else if typeSize.isAccessibilitySize { actionGrid(model) } else {
                ViewThatFits(in: .horizontal) {
                    ActionTileRow { actionTiles(model) }
                    actionGrid(model)
                }
            }
        }
        .animation(DS.Motion.base(reduceMotion), value: model.isSaved)
        .environment(\.roundActionTiles, roundTiles)
    }

    /// A1: en la Mac, las acciones son círculos con su nombre.
    private var roundTiles: Bool { ThisDevice.isMac && !typeSize.isAccessibilitySize }

    private func actionGrid(_ model: TitleModel) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2, alignment: .top), count: 2), spacing: DS.Space.s2) { actionTiles(model) }
    }

    /// Los mosaicos de la ficha, en su orden. «Vista» solo si hay qué marcar; «Tráiler» solo si lo hay: la fila se reparte sin hueco.
    @ViewBuilder private func actionTiles(_ model: TitleModel) -> some View {
        statusAction(model).frame(maxWidth: .infinity)   // G1-A: un solo botón dice si la guardaste
        downloadAction(model).frame(maxWidth: .infinity)
        if canMarkWatched(model) { watchedAction(model).frame(maxWidth: .infinity) }
        if let url = model.extras?.trailer?.url {
            Link(destination: url) { ActionTileLabel(title: Text("Tráiler"), symbol: "play.rectangle", tint: artAccent) }   // V9: `Link` lee `openURL` por su cuenta (en la ficha, pintaba todo con cada cambio)
                .buttonStyle(.plain).frame(maxWidth: .infinity).accessibilityIdentifier("title-trailer")
        }
    }

    /// Un toque en el botón de estado sin estado (G1-A): la guarda en Mi lista, como el «Guardar» de antes.
    func quickSave(_ model: TitleModel) async {
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

    /// Un toque: la recomendada (la mejor en calidad, idioma y tamaño), y un aviso que dice cuál y deja elegir otra.
    func downloadRecommended(_ model: TitleModel, videoID: String? = nil) async {
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

    /// La temporada en una sola línea (F1, 12 nov 2026): la cápsula «Temporada N ⌄» a la izquierda y «3 de 22 vistos» a la
    /// derecha, centrados entre sí (antes «3 de 22 vistos» flotaba debajo y dos círculos a un lado). Bajarla y marcarla vista
    /// viven en los mosaicos «Descargar» y «Vista».
    @ViewBuilder private func seasonHeading(_ model: TitleModel, _ progress: (watched: Int, total: Int)) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s2) {
            seasonControl(model)
            Spacer(minLength: DS.Space.s2)
            if progress.total > 0 {
                Text("\(progress.watched) de \(progress.total) vistos").recipe(.footnote, color: DS.textMuted).lineLimit(1)
                    .accessibilityIdentifier("season-progress")
            }
        }
    }

    /// La versión de la serie (lo que recuerda: latino, castellano, inglés…); tocarla elige otra «desde aquí».
    @ViewBuilder private func episodes(_ model: TitleModel) -> some View {
        // Un solo renglón de controles: a la izquierda la temporada en lista desplegable (Fernando, 1 nov 2026: las cápsulas
        // «T1, T2…» van solo en el reproductor; la misma pieza que Mi media y la hoja de episodios) y a la derecha la versión de
        // la serie, su cápsula gemela; abajo, el avance de la temporada.
        // F1 (Fernando, 12 nov): la temporada y cuántos llevas en la misma línea; bajarla y marcarla vista, en los mosaicos de
        // arriba (antes ET1: dos círculos junto al selector). La versión de la serie ya no va aquí (revisión del 11 nov: eran dos controles de versión
        // en la misma ficha): es la zona derecha de «Continuar» (botón partido, L3), que abre la hoja «Versión».
        let progress = model.seasonProgress
        if !model.seasons.isEmpty || model.continueVideoID != nil {
            seasonHeading(model, progress)
            if progress.total > 0 {
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
            .rowEdge(.bleeds)   // lo que crece al picarlo (o al dejarlo apretado) no se corta en la orilla del listón
            .contentMargins(.horizontal, side, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .pagingArrows()   // C4: ‹ › con el puntero
            .padding(.horizontal, -side)
        } else {
        LazyVStack(spacing: 0) {   // perezosa: una serie larga no arma (ni pide imágenes de) todos sus episodios a la vez
            ForEach(model.rows) { row in
                EpisodeRowView(row: row, play: { if row.airs == nil { tapEpisode(model, row) } }, download: { Task { await downloadRecommended(model, videoID: row.id) } },
                               markWatched: { marking = .episode(row.id) }, chooseSource: { sourcesFor = SourcesTarget(videoID: row.id, purpose: .watch) },
                               resumeDownload: { Task { await model.resumeDownload(row.id) } },
                               downloadFraction: model.downloadFraction(row.id),
                               playOnTV: env.services.orbital.isConfigured ? { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: row.id, title: model.title) } } : nil,
                               rating: env.ratings.stars(row.id), rate: rateEpisode(model, row.id), accent: artAccent,
                               viewings: viewings(model, row))
                Divider().overlay(DS.hairline)
            }
        }
        }
    }
    /// Un episodio como tarjeta (la fila del iPad y la Mac).
    private func episodeRow(_ model: TitleModel, _ row: EpisodeRow, card: Bool) -> some View {
        EpisodeRowView(row: row, play: { if row.airs == nil { tapEpisode(model, row) } }, download: { Task { await downloadRecommended(model, videoID: row.id) } },
                       markWatched: { marking = .episode(row.id) }, chooseSource: { sourcesFor = SourcesTarget(videoID: row.id, purpose: .watch) },
                       resumeDownload: { Task { await model.resumeDownload(row.id) } },
                       downloadFraction: model.downloadFraction(row.id),
                       playOnTV: env.services.orbital.isConfigured ? { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: row.id, title: model.title) } } : nil,
                       rating: env.ratings.stars(row.id), rate: rateEpisode(model, row.id), accent: artAccent, card: card,
                       viewings: viewings(model, row))
    }

    // MARK: acciones

}

/// Cierra la pantalla cuando `closing` se vuelve verdadero. Aparte para que solo esta pieza lea `dismiss`, que cambia con cada
/// movimiento de la navegación (V9).
private struct DismissWhen: ViewModifier {
    let closing: Bool
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content.onChange(of: closing) { _, close in if close { dismiss() } }
    }
}

/// Lo de Real-Debrid que la ficha sigue: «Así funciona» la primera vez que aparece «Pedir a la nube», y volver a buscar la
/// versión cuando un pedido cambia de estado. Aparte para que solo esta pieza lea el pedido (que depende de las versiones).
private struct TitleDebridFollow: ViewModifier {
    let model: TitleModel
    let reload: () -> Void
    func body(content: Content) -> some View {
        content
            .debridFlowIntro(when: model.debridOffer != nil && model.debridRequest == nil)
            .onChange(of: model.debridRequest?.state) { _, _ in reload() }
    }
}

/// Lo de adentro de la ficha en su propia vista: SwiftUI lo arma en su turno y no dentro del cuerpo de `TitleView`, que es
/// grande y se copia en cada cierre (ver `framed`).
private struct TitleLayoutHost: View {
    let make: () -> AnyView
    var body: some View {
        #if MAC_DRIVE
        let _ = MacDrive.body("host")
        #endif
        make()
    }
}
