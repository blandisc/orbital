import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Para ti»: el mosaico (como en la TV, solo películas y series) y las listas (Trakt y plataformas).
struct ParaTiView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: ModelObserver<ParaTiModel>
    @State private var tint = ArtTint()
    /// El arte de la pieza enfocada del mosaico: el fondo de toda la pantalla toma su tono (nil en el ambiente o en Listas).
    @State private var focusedArt: String?
    /// La sugerencia enfocada del mosaico (su información va bajo él).
    @State private var focused: Suggestion?
    /// Una ficha abierta desde la franja del mosaico («Ver la serie»).
    @State private var openTitle: TitleRoute?
    /// «Decide por mí» abierto.
    @State private var deciding = false
    /// «¿Qué vemos hoy?» · Encuentra tu match perfecto: el mazo a pantalla completa (la tarjeta de Listas).
    @State private var matching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Un iPhone de 375 pt o menos (SE, mini): la barra de arriba no da para todo junto al título.
    static var narrow: Bool { WindowMetrics.size.width < DS.Size.compactWidth }

    init() { _model = State(wrappedValue: ModelObserver(ParaTiModel(AppEnvironment.shared.services))) }

    var body: some View {
        let m = model.model
        VStack(spacing: DS.Space.s2) {
            if let error = m.error, m.mosaic.isEmpty, m.lists.isEmpty { DSNotice(verbatim: env.message(error)).padding(.horizontal, DS.Space.gutter) }
            switch m.mode {
            case .mosaic:
                Mosaic(items: m.mosaic, watchlistKeys: m.watchlistKeys, demoFocus: demoFocusImdb, onDismiss: { s in Task { await m.dismiss(s) } },
                       onFocusChange: { new in
                           // Sin nada elegido (al abrir, o al pasar de largo) no hay pie; elegir una lo muestra.
                           focused = new
                           if let new { focusedArt = new.wide }
                       }, onOpen: { openTitle = $0.route }, loading: m.isLoading, retry: { Task { await m.refresh() } })
                // La pieza elegida, contada sobre el pie del mosaico (flota: el mosaico no cambia de alto al elegir o soltar).
                .overlay(alignment: .bottom) {
                    if DS.Mosaic.uniform, let item = focused {
                        // Como la TV: el motivo tal cual, y una serie sugerida abre su ficha («Ver la serie»), no un episodio al azar.
                        MosaicCaption(reason: Text(badgeKey(item.reason)), title: item.title, logo: item.logo,
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
                .onChange(of: focused == nil) { _, none in if none { env.ui.noticeLift = 0 } }
                .onDisappear { env.ui.noticeLift = 0 }
            case .lists: ListsView(observer: model, onDecide: { deciding = true }, onMatch: { matching = true }).onAppear { env.ui.noticeLift = 0 }
            }
        }
        // El mismo aire bajo el título que Inicio. En listas va adentro de la lista: afuera la despegaba de la orilla y iOS
        // ya no la pasaba detrás de la barra (el mosaico se cortaba en seco bajo el título).
        .padding(.top, m.mode == .lists ? 0 : DS.Space.s3)
        .background(Backdrop(tint: m.mode == .mosaic ? tint.colors : nil))
        .task(id: m.mode == .mosaic ? focusedArt : nil) { await tint.load(m.mode == .mosaic ? focusedArt : nil) }
        .navigationTitle("Para ti")
        // El título grande en el renglón de los botones, como Descargas y Buscar (antes iba debajo de los íconos).
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            // «Decide por mí»: una sola propuesta, por tiempo y ánimo.
            // En Listas y en un iPhone angosto no cabían los cuatro botones junto al título («Para…»): «Decide por mí» pasa al índice.
            if !(m.mode == .lists && Self.narrow) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { deciding = true } label: { Image(systemName: "dice") }.accessibilityLabel(Text("Decide por mí"))
                }
            }
            // Un solo selector en la pantalla (Todo · Series · Películas, en Listas): mosaico ↔ listas es este botón.
            ToolbarItem(placement: .topBarTrailing) {
                Button { m.mode = m.mode == .mosaic ? .lists : .mosaic } label: {
                    Image(systemName: m.mode == .mosaic ? "list.bullet.rectangle" : "square.grid.2x2")
                }
                .accessibilityLabel(m.mode == .mosaic ? Text("Ver las listas") : Text("Ver el mosaico"))
                .accessibilityIdentifier("paraTi-mode")
                .sensoryFeedback(.selection, trigger: m.mode)
            }
            // «Actualizar»: en Listas, deslizando hacia abajo; el mosaico no se desliza, así que ahí es un botón.
            if m.mode == .mosaic {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await m.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(m.isLoading).accessibilityLabel(Text("Actualizar"))
                }
            }
            // Sin separar el perfil: en una sola pastilla los botones caben junto al título aun en un SE («Para…» se cortaba).
            // En Listas, `ListsView` pone el índice de secciones y luego el perfil: así el perfil es siempre el último botón.
            if m.mode == .mosaic { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
        }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .openingTitles(item: $openTitle)   // en el iPad y la Mac, en el panel de la derecha
        .task {
            #if DEBUG
            if Demo.isOn, Demo.open == "lists" || Demo.mode == "lists" { m.mode = .lists }
            if Demo.isOn, Demo.mode == "mosaic" { m.mode = .mosaic }
            if Demo.isOn, Demo.open == "decide" { Task { try? await Task.sleep(for: .seconds(4)); deciding = true } }   // cuando ya cargó lo que se sugiere
            if Demo.isOn, Demo.open == "match" { Task { try? await Task.sleep(for: .seconds(4)); matching = true } }   // el mazo «¿Qué vemos hoy?»
            if let start = Demo.startMode { m.mode = start == "lists" ? .lists : .mosaic }
            #endif
            await m.load()
        }
        .refreshable { await m.refresh() }
        .fullScreenCover(isPresented: $matching) {
            let pool = m.mosaic + m.visibleShelves.flatMap { m.items(for: $0) }
            MatchDeckScreen(pool: pool, onOpenTitle: { openTitle = $0 },
                            onPlay: { route in
                                // Una película suena ya; una serie abre su ficha (un episodio suelto casi nunca es el bueno).
                                if let s = pool.first(where: { $0.imdb == route.metaID }), s.kind == "movie" { Task { await env.play(s) } }
                                else { openTitle = route }
                            })
        }
        .sheet(isPresented: $deciding) {
            DecideView(pool: (m.because?.items ?? []) + m.mosaic + m.visibleShelves.flatMap { m.items(for: $0) }, sources: decideSources(m)) { openTitle = $0 }
        }
        .animation(DS.Motion.base(reduceMotion), value: m.mode)
        .animation(DS.Motion.base(reduceMotion), value: focused?.imdb)
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
            out.append(.init(id: plan.id, name: name, origin: suggested, items: m.items(for: plan)))
        }
        // Todas tus listas (tienes muchas): las que aún no se abren se piden solo si las eliges.
        for list in m.traktLists where !out.contains(where: { $0.id == list.id }) && !list.title.isEmpty {
            let origin = list.source.isEmpty ? (list.group == .mine ? "Trakt" : suggested) : list.source
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
