import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un estado de Guardado en su pestaña (GD2): **Viendo** (lo que tienes a medias y las series que sigues saliendo, con su
/// avance, y al final «¿Las dejaste?»), **Vistas** por mes (lo más reciente arriba) y **Las dejé**, dentro de Vistas. La misma
/// cuadrícula de pósters de toda lista, el mismo renglón de controles (el orden a la izquierda; filtrar y elegir varios a la
/// derecha) y mantener el dedo en un póster trae «Mover a…». Vacío, cómo se llena. Antes eran tres maquetas distintas de
/// «pila abierta» (G2-A); ahora una sola.
struct SavedPileContent: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var observer: ModelObserver<SavedModel>
    let status: TitleStatus
    var header: AnyView? = nil
    @State private var collections = ModelObserver(AppEnvironment.shared.collections)
    /// «Editar»: elegir varios (G3-A).
    @State private var selection = ListSelection()
    /// Todo · Películas · Series: "" es todo, «movie» o «series».
    @State private var kind = ""
    private var model: SavedModel { observer.model }
    private func shown(_ list: [Suggestion]) -> [Suggestion] { kind.isEmpty ? list : list.filter { $0.kind == kind } }

    var body: some View {
        let follow = env.follow
        let _ = follow.track()
        let board = model.board(hidden: follow.hidden, hiddenNames: Dictionary(follow.hiddenSeries.map { ($0.imdb, $0.title) }, uniquingKeysWith: { a, _ in a }))
        let all = status == .watching ? board.items(status) + board.stale : board.items(status)
        let items = shown(board.items(status))
        let every = status == .watching ? items + shown(board.stale) : items
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                if let header { header }
                if !model.boardReady && all.isEmpty {
                    DSLoadingState()
                } else if all.isEmpty {
                    empty
                } else if status == .watched {
                    bar(nil, every: every)
                    ForEach(months(items, board), id: \.0) { month, group in
                        VStack(alignment: .leading, spacing: DS.Space.s3) {
                            DSSectionHead(title: Text(verbatim: month), count: group.count, level: .subsection)
                                .padding(.horizontal, DS.Space.gutter)
                            DSPosterGrid(items: group) { s, width in cell(s, width: width) }
                        }
                    }
                } else {
                    if !items.isEmpty {
                        SortableGrid(listID: "saved-state:\(status.rawValue)", items: items, collections: collections.model,
                                     showsKindFilter: false, loading: !model.boardReady, states: nil, bar: { AnyView(bar($0, every: every)) }) { s, width in cell(s, width: width) }
                    } else {
                        bar(nil, every: every)
                    }
                    if status == .watching, !shown(board.stale).isEmpty { stale(shown(board.stale)) }
                }
            }
            .refreshOrbitHost()
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Layout.screenBottom)
            .selectionDrag(selection)
        }
        .scrollBounceBehavior(.basedOnSize)
        .orbitalRefreshable { [model] in await model.load() }
        .safeAreaBar(edge: .bottom) {
            if selection.editing {
                SavedSelectionBar(model: model, selection: selection, listID: nil, pile: status, items: every)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// El renglón bajo las pestañas: el orden a la izquierda (donde lo hay) y, a la derecha, filtrar y elegir varios.
    private func bar(_ parts: ListBarParts?, every: [Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            controls(parts, every: every)
            // «Editar»: cuántas van y «Todas», debajo del renglón que lo abrió.
            if selection.editing { SelectionHeader(selection: selection, all: every.map(\.imdb)) }
        }
    }

    /// Con letra de accesibilidad, Todo · Películas · Series baja a su renglón (nada se encima).
    private func controls(_ parts: ListBarParts?, every: [Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .center, spacing: DS.Space.s2) {
                if let parts { parts.sort }
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize { kindFilter }
                if let parts {
                    parts.filters.font(DS.TextRecipe.section.font).foregroundStyle(DS.text)
                        .frame(minWidth: DS.Size.touchTarget, minHeight: DS.Size.touchTarget)
                }
                ListSelectButtons(selection: selection, all: every.map(\.imdb))
            }
            if typeSize.isAccessibilitySize { kindFilter }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    private var kindFilter: some View {
        DSKindFilter(kind: Binding(get: { kind }, set: { new in withAnimation(DS.Motion.base(reduceMotion)) { kind = new } }))
    }

    /// Un póster del montón: abre su ficha, mantener el dedo trae «Mover a…» y, mientras eliges, se elige.
    private func cell(_ s: Suggestion, width: CGFloat) -> some View {
        TitleLink(route: s.route, progress: status == .watched ? nil : model.progress(of: s), width: width, detail: s.year.map { Text(verbatim: String($0)) })
            .contextMenu { if !selection.editing { SavedMoveMenu(suggestion: s, from: status, model: model) } }
            .accessibilityHint(Text("Mantén presionado para moverlo"))
            .selectable(selection, id: s.imdb, title: titleName(s.title, id: s.imdb, kind: s.kind))
    }

    /// Un vacío enseña qué hacer (GD2): qué junta esta pestaña y cómo se llena.
    private var empty: some View {
        Group {
            switch status {
            case .watching:
                DSEmptyState(symbol: TitleView.statusSymbol(.watching), title: Text("Nada a medias"),
                             message: Text("Lo que empieces a ver, aquí o en la TV, aparece aquí con cuánto llevas.")) { searchButton }
            case .dropped:
                DSEmptyState(symbol: TitleView.statusSymbol(.dropped), title: Text("No has dejado nada"),
                             message: Text("Lo que dejes a medias, desde su ficha o manteniendo el dedo en su póster, aparece aquí.")) { searchButton }
            default:
                DSEmptyState(symbol: TitleView.statusSymbol(.watched), title: Text("Todavía no terminas nada"),
                             message: Text("Lo que termines, aquí o en la TV, aparece aquí por mes.")) { searchButton }
            }
        }
    }

    private var searchButton: some View {
        Button("Buscar qué ver") { env.openTab = AppEnvironment.searchTab }.accessibilityIdentifier("saved-empty-search")
    }

    /// «¿Las dejaste?»: las series a medias que no ves hace más de seis meses ya no cuentan en Viendo; un toque las deja todas
    /// (o una por una, manteniendo el dedo), y si no, siguen aquí.
    private func stale(_ shows: [Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: Text("¿Las dejaste?"), count: shows.count, eyebrow: Text("Hace más de seis meses que no las ves"))
                .padding(.horizontal, DS.Space.gutter)
            DSPosterGrid(items: shows) { s, width in cell(s, width: width) }
            if !selection.editing {
                Button { Task { await dropAll(shows) } } label: { Label("Sí, las dejé", systemImage: TitleView.statusSymbol(.dropped)) }
                    .dsSecondaryButton()
                    .padding(.horizontal, DS.Space.gutter)
                    .accessibilityIdentifier("saved-stale-drop")
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("saved-stale")
    }

    private func dropAll(_ shows: [Suggestion]) async {
        let follow = env.follow, ids = shows.map(\.imdb)
        if let problem = await follow.hide(ids) { env.notify(problem, tone: .error); return }
        for id in ids { await ReleaseNotifier.forget(id) }
        env.notify(ids.count == 1 ? "La dejaste" : "Las dejaste", detail: ids.count == 1 ? shows.first.map { titleName($0.title, id: $0.imdb, kind: $0.kind) } : nil, tone: .info,
                   actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {
            Task { _ = await follow.unhide(ids) }
        }
    }

    /// «Noviembre», «Octubre»… (con el año si no es este): solo la primera letra en mayúscula.
    static func month(_ date: Date, language: String) -> String {
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        let text = thisYear ? date.formatted(.dateTime.month(.wide).locale(Locale(identifier: language)))
                            : Strings.date(date, .monthYear, language: language)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Cada vista bajo el mes en que la viste por última vez.
    private func months(_ items: [Suggestion], _ board: SavedBoard) -> [(String, [Suggestion])] {
        let language = env.services.appSettings.uiLanguage
        var out: [(String, [Suggestion])] = []
        for s in items {
            let key = board.lastWatched[s.imdb].map { Self.month($0, language: language) } ?? Strings.tr("Sin fecha", language: language)
            if out.last?.0 == key { out[out.count - 1].1.append(s) } else { out.append((key, [s])) }
        }
        return out
    }
}
