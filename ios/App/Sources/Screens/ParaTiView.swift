import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Para ti»: el mosaico (como en la TV, solo películas y series) y las listas (Trakt y plataformas).
struct ParaTiView: View {
    @StateObject private var model: ModelObserver<ParaTiModel>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init() { _model = StateObject(wrappedValue: ModelObserver(ParaTiModel(AppEnvironment.shared.services))) }

    var body: some View {
        let m = model.model
        VStack(spacing: DS.Space.s2) {
            HStack {
                DSSegmented<ParaTiModel.Mode>(options: [(.mosaic, "Mosaico"), (.lists, "Listas")], selection: Binding(get: { m.mode }, set: { m.mode = $0 }))
                Spacer()
                if m.traktLinked { DSChip(text: "Trakt al día", tone: .good) }
            }
            .padding(.horizontal, DS.Space.gutter)
            // Con letra de accesibilidad el botón baja debajo del texto en vez de apretarse a su lado.
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s2)) : AnyLayout(HStackLayout())) {
                Text(footer(m)).font(DS.font(.xs)).foregroundStyle(DS.textMuted)
                if !typeSize.isAccessibilitySize { Spacer() }
                Button { Task { await m.refresh() } } label: { Text("Actualizar") }
                    .buttonStyle(.plain).font(DS.font(.xs)).foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.Space.gutter)
            if let error = m.error, m.mosaic.isEmpty, m.lists.isEmpty { DSNotice(text: LocalizedStringKey(error)).padding(.horizontal, DS.Space.gutter) }
            switch m.mode {
            case .mosaic: Mosaic(items: m.mosaic, watchlistKeys: m.watchlistKeys, demoFocus: demoFocusImdb, onDismiss: { s in Task { await m.dismiss(s) } })
            case .lists: ListsView(observer: model)
            }
        }
        .padding(.top, DS.Space.s2)
        .background(TintedBackground())
        .navigationTitle("Para ti").navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: TitleRoute.self) { TitleView(route: $0) }
        .task {
            #if DEBUG
            if Demo.isOn, Demo.open == "lists" { m.mode = .lists }
            #endif
            await m.load()
        }
        .refreshable { await m.refresh() }
        .animation(DS.Motion.base(reduceMotion), value: m.mode)
    }

    /// El pie discreto bajo el selector: de dónde salió lo que ves, o (si aplica) la invitación a conectar Trakt.
    private func footer(_ m: ParaTiModel) -> LocalizedStringKey {
        if m.isGeneric, m.mode == .mosaic, !m.mosaic.isEmpty {
            return "Lo más popular en Stremio. Conecta Trakt en Ajustes y el mosaico se arma con lo tuyo."
        }
        return m.source == .console ? "Para ti de tu Orbital" : "Calculado en el iPhone"
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

struct ListsView: View {
    @ObservedObject var observer: ModelObserver<ParaTiModel>
    private var model: ParaTiModel { observer.model }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                if model.lists.isEmpty { popularFallback }
                if model.chips.count > 1 {   // un solo filtro («Todo») no filtra nada
                    DSChipRow(items: model.chips, label: label, selection: Binding(get: { model.chip }, set: { new in Task { await model.select(new) } }))
                }
                if model.lists.contains(where: \.splitsKinds) {
                    DSSegmented(options: [("series", "Series"), ("movie", "Películas")], selection: Binding(get: { model.kind }, set: { new in Task { await model.setKind(new) } }))
                        .padding(.horizontal, DS.Space.gutter)
                }
                if model.chip == .trakt { traktTabs }
                ForEach(model.visibleLists) { list in listSection(list) }
            }
            .padding(.bottom, DS.Space.s14)   // aire bajo la última fila: la barra de pestañas no la tapa
        }
    }

    /// Sin Trakt ni TMDB no hay listas: lo popular de Stremio, en filas, y cómo tener las tuyas.
    @ViewBuilder private var popularFallback: some View {
        DSNotice(text: "Conecta Trakt (tu watchlist y tus listas) o agrega una clave de TMDB (lo popular en Netflix, Disney+ y HBO Max) en Ajustes.")
            .padding(.horizontal, DS.Space.gutter)
        let series = model.mosaic.filter { $0.kind == "series" }, movies = model.mosaic.filter { $0.kind == "movie" }
        if !series.isEmpty { Rail(title: "Series populares") { ForEach(series) { TitleLink(route: $0.route) } } }
        if !movies.isEmpty { Rail(title: "Películas populares") { ForEach(movies) { TitleLink(route: $0.route) } } }
    }

    @ViewBuilder private func label(_ chip: ParaTiModel.Chip) -> some View {
        switch chip {
        case .all: Text("Todo")
        case .trakt: Text("Trakt")
        case .platform(let brand):
            let logo = model.platformLists.first { $0.brand == brand }?.logo
            HStack(spacing: DS.Space.s1) {
                if let logo { DSPlatformLogo(url: logo) }
                Text(Tmdb.platforms.first { $0.brand == brand }?.name ?? brand)
            }
        }
    }

    /// Lo tuyo primero («Tuyo») y lo de todos después («Descubrir»).
    private var traktTabs: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach([ForYouGroup.mine, .discover], id: \.self) { group in
                let lists = model.traktLists.filter { $0.group == group }
                if !lists.isEmpty {
                    (group == .mine ? Text("Tuyo") : Text("Descubrir")).font(DS.font(.sm)).foregroundStyle(DS.textMuted).padding(.horizontal, DS.Space.gutter)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.s2) {
                            ForEach(lists) { list in
                                Button { Task { await model.select(traktList: list.id) } } label: {
                                    listName(list).font(DS.font(.sm, weight: .semibold)).lineLimit(1)
                                        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
                                        .foregroundStyle(model.traktList == list.id ? DS.onPrimary : DS.text)
                                        .background(model.traktList == list.id ? DS.primary : DS.fill, in: Capsule())
                                }
                            }
                        }.padding(.horizontal, DS.Space.gutter)
                    }
                }
            }
        }
    }

    private func listName(_ list: ForYouList) -> Text {
        if !list.title.isEmpty { return Text(list.title) }
        switch list.id {
        case "watchlist": return Text("Watchlist")
        case "mine": return Text("Viendo")
        case "recs": return Text("Recomendadas")
        case "trend": return Text("En tendencia")
        case "popular": return Text("Popular")
        default: return Text(list.id)
        }
    }

    @ViewBuilder private func listSection(_ list: ForYouList) -> some View {
        let items = model.items(for: list)
        if model.chip == .all {
            if !items.isEmpty {
                Rail(title: LocalizedStringKey(list.title.isEmpty ? "Tu watchlist" : list.title), trailing: list.group == .platforms ? "Lo más popular" : nil,
                     logo: list.group == .platforms ? list.logo : nil) {
                    ForEach(items) { s in TitleLink(route: s.route, badge: model.watchlistKeys.contains(s.imdb) ? "En tu lista" : nil, rank: s.rank) }
                }
            }
        } else if items.isEmpty {
            DSNotice(text: "No hay nada aquí todavía.").padding(.horizontal, DS.Space.gutter)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Poster.gridMinimum), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
                ForEach(items) { s in TitleLink(route: s.route, badge: badgeKey(s.reason), rank: s.rank, width: DS.Poster.gridMinimum) }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }
}
