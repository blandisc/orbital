import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Para ti»: el mosaico (como en la TV, solo películas y series) y las listas (Trakt y plataformas).
struct ParaTiView: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    @State private var model: ModelObserver<ParaTiModel>
    @State private var tint = ArtTint()
    /// El arte de la pieza enfocada del mosaico: el fondo de toda la pantalla toma su tono (nil en el ambiente o en Listas).
    @State private var focusedArt: String?
    /// La sugerencia enfocada del mosaico (su información va bajo él).
    @State private var focused: Suggestion?
    /// Una ficha abierta desde la franja del mosaico («Ver la serie»).
    @State private var openTitle: TitleRoute?
    /// «Decide por mí» abierto (su puerta en Listas o la de Inicio; adentro, «Tres que caben» y «Una por una»).
    @State private var deciding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() { _model = State(wrappedValue: ModelObserver(ParaTiModel(AppEnvironment.shared.services))) }

    /// El mosaico con su pie (la pieza elegida). Aparte del cuerpo: el compilador de la CI (Xcode 26.3) no alcanzaba a revisarlo.
    private func mosaicPart(_ m: ParaTiModel) -> some View {
        Mosaic(items: m.mosaic, watchlistKeys: m.watchlistKeys, demoFocus: demoFocusImdb, onDismiss: { s in Task { await m.dismiss(s) } },
               onFocusChange: { new in
                   // Sin nada elegido (al abrir, o al pasar de largo) no hay pie; elegir una lo muestra.
                   focused = new
                   if let new { focusedArt = new.wide }
               }, onOpen: { openTitle = $0.route }, loading: m.isLoading, retry: { Task { await m.refresh() } })
        // Deslizar de lado (a cualquier lado: el mosaico solo sube y baja) regresa a Explorar, como la flecha.
        .simultaneousGesture(DragGesture(minimumDistance: DS.Gesture.axisThreshold).onEnded { value in
            let dx = value.translation.width, dy = value.translation.height
            if abs(dx) > DS.Mosaic.swipeBack, abs(dx) > abs(dy) * 2 { m.mode = .lists }
        })
        // La pieza elegida, contada sobre el pie del mosaico (flota: el mosaico no cambia de alto al elegir o soltar).
        .overlay(alignment: .bottom) {
            if DS.Mosaic.uniform, let item = focused {
                // Como la TV: el motivo tal cual, y una serie sugerida abre su ficha («Ver la serie»), no un episodio al azar.
                MosaicCaption(reason: Text(badgeKey(item.reason)), title: titleName(item.title, id: item.imdb, kind: item.kind), logo: item.logo,
                              data: (factStrings(item, language: env.language).first ?? "").components(separatedBy: " · "), accent: tint.colors, isSeries: item.kind == "series",
                              open: { openTitle = item.route },
                              watch: { if item.kind == "series" { openTitle = item.route } else { Task { await env.play(item) } } }) {
                    SuggestionActions(suggestion: item, includeWatch: false) { s in Task { await m.dismiss(s) } }
                }
                .padding(DS.Space.s4)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s14)
                // Los avisos («Ya está en tu Orbital») salen encima del pie, no sobre sus botones.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { env.ui.noticeLift = $0 }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(item.imdb)
            }
        }
        .onChange(of: focused == nil) { _, none in if none, env.ui.noticeLift != 0 { env.ui.noticeLift = 0 } }
        .onDisappear { if env.ui.noticeLift != 0 { env.ui.noticeLift = 0 } }
    }

    /// Las listas (con la puerta de «Decide por mí»).
    private var listsPart: some View {
        ListsView(observer: model, onDecide: { deciding = true })
            .onAppear { if env.ui.noticeLift != 0 { env.ui.noticeLift = 0 } }
    }

    var body: some View {
        let m = model.model
        VStack(spacing: DS.Space.s2) {
            if let error = m.error, m.mosaic.isEmpty, m.lists.isEmpty { DSNotice(verbatim: env.message(error)).padding(.horizontal, DS.Space.gutter) }
            switch m.mode {
            case .mosaic:
                // MO1: el mosaico crece desde la portada (arriba) y al salir regresa a ella, mientras la portada se inclina otra vez.
                mosaicPart(m).transition(MosaicCover.mosaicTransition(reduceMotion))
            case .lists: listsPart
            }
        }
        // El mismo aire bajo el título que Inicio. En listas va adentro de la lista: afuera la despegaba de la orilla y iOS
        // ya no la pasaba detrás de la barra (el mosaico se cortaba en seco bajo el título).
        .padding(.top, m.mode == .lists ? 0 : DS.Space.s3)
        .background(Backdrop(tint: m.mode == .mosaic ? tint.colors : nil))
        .task(id: m.mode == .mosaic ? focusedArt : nil) { await tint.load(m.mode == .mosaic ? focusedArt : nil) }
        // El mismo encabezado que Inicio (Fernando, 31 oct 2026): «Para ti» a la izquierda, donde va el logo, y los pósters debajo.
        // En el iPad y la Mac, el título del sistema como Biblioteca: de pie la barra de pestañas va en ese renglón y iOS lo
        // oculta; con el título a mano quedaba encimado a la hora y a la barra (4 nov 2026).
        .navigationTitle(ThisDevice.platform == "iphone" ? Text(verbatim: "") : Text("Explorar"))
        .toolbarTitleDisplayMode(ThisDevice.platform == "iphone" ? .inline : .inlineLarge)
        // Solo en el mosaico: en las listas no hay pósters que acercar.
        .learnCoach(.explore, title: "Explorar", detail: "Un toque acerca un póster; el segundo abre su ficha.", active: m.mode == .mosaic)
        .toolbar {
            // En el mosaico, regresar a las listas a la izquierda (antes solo el botón de la derecha, que no se entendía);
            // en las listas, el logo.
            if m.mode == .mosaic, ThisDevice.platform == "iphone" {
                ToolbarItem(placement: .topBarLeading) { mosaicBack(m) }
            } else if m.mode == .lists, ThisDevice.platform == "iphone" {
                ToolbarItem(placement: .topBarLeading) { ScreenMark(title: Text("Explorar")) }
                    .sharedBackgroundVisibility(.hidden)
            }
            // «Decide por mí» ya no está en la barra: tiene una sola puerta, en Listas y en Inicio (DE2, 13 nov 2026).
            // Sin botón de mosaico ↔ listas (Fernando, 31 oct 2026): al mosaico se entra con «Pasear por el mosaico» de la
            // portada y se sale con la flecha de la izquierda o deslizando de lado.
            // «Actualizar»: en Listas, deslizando hacia abajo; el mosaico no se desliza, así que ahí es un botón.
            if m.mode == .mosaic {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await m.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(m.isLoading).accessibilityLabel(Text("Actualizar"))
                }
            }
            // Sin separar el perfil: en una sola pastilla los botones caben junto al título aun en un SE («Para…» se cortaba).
            // En Listas, `ListsView` pone el índice de secciones y luego el perfil: así el perfil es siempre el último botón.
            // F1: en el iPad y la Mac el perfil no va en el mosaico (está en Explorar, Inicio y Buscar): con él no cabía la flecha
            // de regresar y la barra la escondía en «⋯».
            if m.mode == .mosaic, ThisDevice.platform == "iphone" { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
            else if m.mode == .mosaic { ToolbarItem(placement: .topBarTrailing) { mosaicBack(m) } }
        }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .openingTitles(item: $openTitle)   // en el iPad y la Mac, en el panel de la derecha
        .onChange(of: env.ui.returnedToApp) { Task { await m.loadIfStale() } }   // de vuelta a la app: al día
        .task {
            #if DEBUG
            if Demo.isOn, Demo.open == "lists" || Demo.mode == "lists" { m.mode = .lists }
            if Demo.isOn, Demo.mode == "mosaic" { m.mode = .mosaic }
            if Demo.isOn, Demo.open == "decide" { Task { try? await Task.sleep(for: .seconds(4)); deciding = true } }   // cuando ya cargó lo que se sugiere
            if Demo.isOn, Demo.open == "match" { Task { try? await Task.sleep(for: .seconds(4)); deciding = true } }   // con -demo-decide-tab deck, el mazo
            if let start = Demo.startMode { m.mode = start == "lists" ? .lists : .mosaic }
            #endif
            // De vuelta a la pestaña: primero termina el salto de la barra y luego, si hace falta, se refresca.
            if !m.lists.isEmpty || !m.mosaic.isEmpty {
                try? await Task.sleep(for: DS.Motion.tabSettle)
                guard !Task.isCancelled else { return }
            }
            await m.loadIfStale()
        }
        // El widget «Mosaico de una lista»: tus listas de Explorar con sus pósters (cuando cambian los estantes que se ven).
        .task(id: m.visibleShelves.map { "\($0.id):\(m.items(for: $0).count)" }) {
            let lists = WidgetListsPublisher.lists(from: m)
            if lists.contains(where: { !$0.posters.isEmpty }) { WidgetListsPublisher.publish(lists) }
        }
        // La puerta de Inicio (DE2): llega aquí y abre la hoja. Primero el cambio de pestaña y lo que se sugiere; luego la
        // hoja (antes salía encima de Inicio y vacía). El cambio de pestaña puede crear esta vista dos veces: las dos piden
        // la hoja y el pedido se apaga cuando la hoja ya se ve, no antes (si no, la que queda viva no la abría).
        .onChange(of: env.ui.openDecide, initial: true) { _, open in
            guard open else { return }
            m.mode = .lists
            Task {
                // La carga la lanza la propia pestaña: aquí solo se espera a que haya listas, unos segundos a lo más.
                for _ in 0..<8 {
                    try? await Task.sleep(for: DS.Motion.tabSettle)
                    if !m.lists.isEmpty || m.hasLoaded { break }
                }
                if env.ui.openDecide { deciding = true }
            }
        }
        .sheet(isPresented: $deciding) {
            DecideView(pool: decidePool(m), sources: decideSources(m),
                       reload: { await m.refresh(); return (decidePool(m), decideSources(m)) }) { openTitle = $0 }
                .onAppear { env.ui.openDecide = false }
        }
        .animation(DS.Motion.base(reduceMotion), value: m.mode)
        .animation(DS.Motion.base(reduceMotion), value: focused?.imdb)
    }

    /// Lo que se sugiere, para «Decide por mí»: «Porque viste», el mosaico y cada estante que se ve.
    private func decidePool(_ m: ParaTiModel) -> [Suggestion] { (m.because?.items ?? []) + m.mosaic + m.visibleShelves.flatMap { m.items(for: $0) } }
    /// F1 (13 nov 2026): la salida del mosaico, siempre a la vista. En el iPhone, la flecha a la izquierda; en el iPad y la Mac
    /// la barra de pestañas va en ese renglón y mandaba lo de la izquierda a «⋯» (no había salida visible, solo deslizar de
    /// lado): ahí es «Cerrar» (✕) al final de la derecha, en el lugar del perfil.
    private func mosaicBack(_ m: ParaTiModel) -> some View {
        Button { m.mode = .lists } label: { Image(systemName: ThisDevice.platform == "iphone" ? "chevron.backward" : DS.Symbol.close) }
            .accessibilityLabel(Text("Regresar a Explorar"))
            .accessibilityIdentifier("paraTi-back")
    }

    /// «¿Qué vemos?» › De dónde: «Porque viste», lo nuevo en tus plataformas y cada estante que se ve (con su nombre).
    private func decideSources(_ m: ParaTiModel) -> [DecideModel.Source] {
        let language = env.services.appSettings.uiLanguage
        var out: [DecideModel.Source] = []
        let suggested = "Sugerencias"
        if let because = m.because { out.append(.init(id: "because", name: String(format: Strings.tr("Porque viste %@", language: language), because.seed.title), origin: suggested, items: because.items)) }
        if !m.newOnPlatforms.isEmpty { out.append(.init(id: "new", name: Strings.tr("Nuevo en tus plataformas", language: language), origin: suggested, items: m.newOnPlatforms)) }
        for plan in m.visibleShelves {
            let name: String = switch plan.id {
            case "watchlist": Strings.tr("Mi lista", language: language)
            case "mine": Strings.tr("Tus series", language: language)
            case "recs": Strings.tr("Recomendadas", language: language)
            case "trend": Strings.tr("En tendencia", language: language)
            case "popular": Strings.tr("Lo más popular", language: language)
            default: plan.title.isEmpty ? plan.id : plan.title
            }
            out.append(.init(id: plan.id, name: name, origin: DecideModel.origin(ofShelf: plan.id), items: m.items(for: plan)))   // F7: «Mi lista» es tuya
        }
        // Todas tus listas (tienes muchas): las que aún no se abren se piden solo si las eliges.
        for list in m.traktLists where !out.contains(where: { $0.id == list.id }) && !list.title.isEmpty {
            let yours = list.group == .mine || DecideModel.origin(ofShelf: list.id) == DecideModel.yoursOrigin
            let origin = yours ? DecideModel.yoursOrigin : list.source.isEmpty ? suggested : list.source
            out.append(.init(id: list.id, name: list.title, origin: origin, items: m.items(for: list), load: m.decideLoader(for: list)))
        }
        return out
    }

    /// Modo demostración (`-demo-mosaic-focus N`): qué sugerencia enfocar al abrir, para las capturas de CEN-36.
    private var demoFocusImdb: String? {
        #if DEBUG
        guard Demo.isOn, let index = Demo.mosaicFocus, model.model.mosaic.indices.contains(index) else { return nil }
        return model.model.mosaic[index].imdb
        #else
        return nil
        #endif
    }
}
