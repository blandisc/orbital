import SwiftUI
import OrbitalCore
import OrbitalModels

// Las páginas de «Decide por mí» que se abren desde la hoja: «Más filtros» y «De qué listas» (separadas de DecideView por
// tamaño, 2 nov 2026).

// MARK: - Más filtros
/// «Más filtros»: géneros, época, qué tan conocida, premios, de qué listas y lo ya visto. Cuenta
/// cuántas quedan mientras eliges; «Ver N» regresa y lo aplica.
struct DecideMoreFilters: View {
    let model: DecideModel
    let openLists: () -> Void
    let done: () -> Void
    @State private var observer: ModelObserver<DecideModel>
    @Environment(AppEnvironment.self) private var env

    init(model: DecideModel, openLists: @escaping () -> Void, done: @escaping () -> Void) {
        self.model = model; self.openLists = openLists; self.done = done
        _observer = State(wrappedValue: ModelObserver(model))
    }

    private var language: String { env.services.appSettings.uiLanguage }

    var body: some View {
        let m = observer.model
        let count = m.count()
        let unknown = count == 0 ? m.unknownCount() : 0
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                PanelGroupTitle(title: "Géneros")
                Text("Elige uno o varios · el número es cuántas hay").recipe(.caption, color: DS.textFaint)
                // Mosaicos con el arte de tus sugerencias de cada género (el `id` con lo elegido: ver `FlowChips`).
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 3), spacing: DS.Space.s2) {
                    ForEach(DecideModel.genreChoices, id: \.self) { g in
                        let count = m.count { $0.genres = [g] }
                        DecideTile(title: Text(verbatim: genreName(g, language: env.language)), image: DecideView.tileImage(genre: g), selected: m.genres.contains(g),
                                   dimmed: !m.genres.isEmpty && !m.genres.contains(g), count: count,
                                   height: DS.Decide.genreTile, enabled: DecideModel.offered(count, selected: m.genres.contains(g))) {
                            if m.genres.contains(g) { m.genres.remove(g) } else { m.genres.insert(g) }
                        }
                    }
                }
                .id(m.genres)   // que se redibuje al elegir (ver `FlowChips`)
                .onChange(of: m.genres) { m.resolveUnknown() }
                PanelGroupTitle(title: "Época")
                // En la misma cuadrícula de tres que los géneros: «2020s» y «90s» del mismo tamaño (F12; en cinco columnas los
                // nombres largos se encogían y «90s» salía más grande).
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 3), spacing: DS.Space.s2) {
                    ForEach(DecideModel.decadeChoices, id: \.self) { d in
                        let count = m.count { $0.decades = [d] }
                        DecideTile(title: d == 1980 ? Text("Antes") : Text(verbatim: d >= 2000 ? "\(d)s" : "\(d % 100)s"), image: "decide-era-\(d)",
                                   selected: m.decades.contains(d), dimmed: !m.decades.isEmpty && !m.decades.contains(d),
                                   count: count, height: DS.Decide.eraTile, era: true, enabled: DecideModel.offered(count, selected: m.decades.contains(d))) {
                            if m.decades.contains(d) { m.decades.remove(d) } else { m.decades.insert(d) }
                        }
                    }
                }
                .id(m.decades)
                .onChange(of: m.decades) { m.resolveUnknown() }
                fame(m)
                awards(m)
                if !m.sources.isEmpty { lists(m) }
                Toggle(isOn: Binding(get: { m.includeWatched }, set: { m.includeWatched = $0 })) { Text("Incluir lo que ya vi").recipe(.secondary, color: DS.text) }
                    .tint(DS.accent)
            }
            .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s4)
        }
        .safeAreaInset(edge: .bottom) {
            Button { done() } label: {
                Text(count > 0 ? String(format: Strings.tr("Ver %lld", language: language), count)
                     : unknown > 0 ? Strings.tr("Buscando opciones…", language: language) : Strings.tr("Sin opciones con eso", language: language))
                    .frame(maxWidth: .infinity)
            }
            .dsPrimaryButton().controlSize(.large)
            .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s2)
            .accessibilityIdentifier("decide-more-done")
        }
        .navigationTitle(Text("Más filtros")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Limpiar") { Task { await m.clearMoreFilters() } }.disabled(m.moreFilters == 0) } }
        // Al volver (con «Ver», deslizando o con ‹), los carteles ya son de lo elegido.
        .onDisappear { Task { await m.apply() } }
    }

    /// «Qué tan conocida» (los votos de TMDB, como en el filtro avanzado): se piden al elegir una y se recuerdan; hasta
    /// tenerlos todos, sin número.
    @ViewBuilder private func fame(_ m: DecideModel) -> some View {
        PanelGroupTitle(title: "Fama")
        if env.services.tmdb.configured {
            // El mismo cuadro del filtro avanzado (fama × calificación), con cuántas quedan en cada esquina cuando ya se sabe.
            let counts = m.fameReady ? Dictionary(uniqueKeysWithValues: [AdvancedFilter.Fame.gems, .classics, .niche, .blockbusters].map { f in (f, m.count { $0.fame = f }) }) : nil
            FameQuadrant(selected: m.fame, counts: counts) { f in
                m.fame = f
                m.fetchFameInBackground()
            }
        } else {
            Text("Necesita la clave de TMDB (Ajustes › Avanzado).").recipe(.caption, color: DS.textFaint)
        }
    }

    /// «Premios»: cada uno con su estatuilla (la misma pieza del filtro avanzado) y cuántas de tus sugerencias ganaron; uno que
    /// no deja nada no se toca (F13).
    @ViewBuilder private func awards(_ m: DecideModel) -> some View {
        PanelGroupTitle(title: "Premios")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 3), spacing: DS.Space.s2) {
            ForEach(FilterCatalog.awards, id: \.self) { id in
                let count = m.count { $0.awards = [id] }
                let offered = DecideModel.offered(count, selected: m.awards.contains(id))
                FilterLogoChoice(title: Text("\(AwardNames.title(id)) · \(count)"), selected: m.awards.contains(id)) {
                    m.awards.formSymmetricDifference([id])
                } logo: { Image("Awards/" + id).resizable().scaledToFit() }
                .disabled(!offered).opacity(offered ? 1 : DS.Opacity.dimmed)
                .accessibilityIdentifier("decide-award-\(id)")
            }
        }
        .id(m.awards)
    }

    /// «De dónde»: un renglón con lo elegido (abre «De qué listas») y las usadas hace poco, a un toque.
    @ViewBuilder private func lists(_ m: DecideModel) -> some View {
        let chosen = m.sources.filter { m.sourceIDs.contains($0.id) }
        PanelGroupTitle(title: "De dónde")
        Button(action: openLists) {
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(chosen.isEmpty ? Strings.tr("Todo lo sugerido", language: language)
                         : String(format: Strings.tr(chosen.count == 1 ? "%lld lista" : "%lld listas", language: language), chosen.count))
                        .recipe(.labelLarge, color: DS.text)
                    if !chosen.isEmpty { Text(verbatim: chosen.map(\.name).joined(separator: " · ")).recipe(.caption).lineLimit(1) }
                }
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: String(format: Strings.tr("de %lld", language: language), m.sources.count)).recipe(.caption)
                Image(systemName: "chevron.right").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted)
            }
            .padding(DS.Space.s3)
            .dsCard(.row, translucent: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("decide-lists")
    }

}

// MARK: - De qué listas
/// Elegir de qué listas sale la propuesta, aunque sean muchas: buscar, por origen (Trakt, Orbital, Sugerencias), las
/// elegidas arriba, las usadas hace poco y todas de la A a la Z. Varias a la vez; «Listo» las aplica.
struct DecideListPicker: View {
    let model: DecideModel
    let done: () -> Void
    @State private var selection: Set<String>
    @State private var query = ""
    @State private var origin: String?
    @Environment(AppEnvironment.self) private var env

    init(model: DecideModel, done: @escaping () -> Void) {
        self.model = model; self.done = done
        _selection = State(initialValue: model.sourceIDs)
    }

    private var language: String { env.services.appSettings.uiLanguage }

    var body: some View {
        let all = model.sources
        let origins = Dictionary(grouping: all, by: \.origin).filter { !$0.key.isEmpty }.map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
        let matching = all.filter { s in
            (origin == nil || s.origin == origin) && (query.isEmpty || s.name.localizedCaseInsensitiveContains(query))
        }
        let chosen = matching.filter { selection.contains($0.id) }
        let recent = model.recentSourceIDs.compactMap { id in matching.first { $0.id == id && !selection.contains(id) } }
        let rest = matching.filter { s in !selection.contains(s.id) && !recent.contains(where: { $0.id == s.id }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        List {
            if origins.count > 1 {
                // De dónde, en las pestañas de texto de toda la app (antes cápsulas de solo texto).
                DSTextTabs(options: [.init(id: "", title: Text(verbatim: String(format: Strings.tr("Todas · %lld", language: language), all.count)))]
                           + origins.map { name, count in .init(id: name, title: Text(verbatim: "\(Strings.tr(name, language: language)) · \(count)")) },
                           selection: Binding(get: { origin ?? "" }, set: { origin = $0.isEmpty ? nil : $0 }))
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: DS.Space.gutter, bottom: 0, trailing: DS.Space.gutter))
            }
            section("Elegidas", chosen)
            section("Usadas hace poco", recent)
            section("Todas, de la A a la Z", rest)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(verbatim: String(format: Strings.tr("Buscar entre tus %lld listas", language: language), all.count)))
        .safeAreaInset(edge: .bottom) {
            Button {
                let ids = selection
                done()
                Task { await model.setSources(ids) }
            } label: {
                Text(selection.isEmpty ? Strings.tr("Listo · todo lo sugerido", language: language)
                     : String(format: Strings.tr(selection.count == 1 ? "Listo · %lld lista" : "Listo · %lld listas", language: language), selection.count))
                    .frame(maxWidth: .infinity)
            }
            .dsPrimaryButton().controlSize(.large)
            .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s2)
            .accessibilityIdentifier("decide-lists-done")
        }
        .navigationTitle(Text("De qué listas")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Todas") { selection = [] }.disabled(selection.isEmpty) } }
    }

    @ViewBuilder private func section(_ title: LocalizedStringKey, _ sources: [DecideModel.Source]) -> some View {
        if !sources.isEmpty {
            Section {
                ForEach(sources) { source in
                    DecideListRow(name: source.name, detail: detail(source), posters: model.items(of: source).prefix(2).map(\.poster),
                                  selected: selection.contains(source.id)) {
                        if selection.contains(source.id) { selection.remove(source.id) } else { selection.insert(source.id) }
                    }
                    .listRowBackground(Color.clear)
                }
            } header: { DSGroupLabel(title: Text(title)) }
        }
    }

    /// «Trakt · 23 títulos» (sin el número si aún no se abre).
    private func detail(_ s: DecideModel.Source) -> String {
        var parts: [String] = []
        if !s.origin.isEmpty { parts.append(Strings.tr(s.origin, language: language)) }
        if let n = model.itemCount(s) { parts.append(String(format: Strings.tr(n == 1 ? "%lld título" : "%lld títulos", language: language), n)) }
        return parts.joined(separator: " · ")
    }
}
