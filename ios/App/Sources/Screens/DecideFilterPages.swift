import SwiftUI
import OrbitalCore
import OrbitalModels

// Las páginas de «Decide por mí» que se abren desde la hoja: «Filtros» y «De qué listas» (separadas de DecideView por
// tamaño, 2 nov 2026).

// MARK: - Filtros
/// «Filtros» (Fernando, 13 nov 2026: un solo botón y una sola hoja, en lugar de cuatro íconos con sus menús): todo lo que
/// filtra, por secciones con los encabezados de dos niveles. «Esta noche» (duración y ánimo; en «Una por una», apagada: el
/// mazo es para guardar), «Qué tan buena» (calificación, según quién, Letterboxd, fama y premios), «Qué tipo» (géneros y
/// época) y «De dónde» (listas y lo ya visto). Las opciones son baldosas con ícono y nombre (`DecideChoice`, cada sección
/// con su tinte) o con su arte (`DecideTile`); arriba, cuántas quedan mientras eliges. «Ver N» regresa; al regresar (con
/// «Ver», deslizando o con ‹) se baraja solo si cambió algo. «Quitar filtros» quita todo menos el tipo.
struct DecideFilters: View {
    let model: DecideModel
    /// «Una por una»: «Esta noche» apagada.
    let deck: Bool
    let openLists: () -> Void
    let done: () -> Void
    @State private var observer: ModelObserver<DecideModel>
    /// Los filtros al abrir: al salir se baraja solo si cambiaron.
    @State private var opened: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize

    init(model: DecideModel, deck: Bool, openLists: @escaping () -> Void, done: @escaping () -> Void) {
        self.model = model; self.deck = deck; self.openLists = openLists; self.done = done
        _observer = State(wrappedValue: ModelObserver(model))
    }

    private var language: String { env.services.appSettings.uiLanguage }
    private var words: DecideWords { DecideWords(language: language) }
    /// Tres por renglón (cuatro el ánimo); con letra de accesibilidad, dos, para que los nombres quepan enteros.
    private func columns(_ n: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: typeSize.isAccessibilitySize ? 2 : n)
    }

    var body: some View {
        let m = observer.model
        let count = deck ? m.deckPool().count : m.count()
        let unknown = count == 0 ? m.unknownCount() : 0
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                Text(verbatim: words.optionsLine(m, count)).recipe(.footnote).monospacedDigit().contentTransition(.numericText())
                    .animation(DS.Motion.fade, value: count)
                    .accessibilityIdentifier("decide-filters-count")
                tonight(m)
                quality(m)
                kindOf(m)
                origin(m)
            }
            .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s2).padding(.bottom, DS.Space.s4)
        }
        .safeAreaInset(edge: .bottom) {
            Button { done() } label: {
                Text(count > 0 ? String(format: Strings.tr("Ver %lld", language: language), count)
                     : unknown > 0 ? Strings.tr("Buscando opciones…", language: language) : Strings.tr("Sin opciones con eso", language: language))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
            }
            .dsPrimaryButton().controlSize(.large)
            .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s2)
            .accessibilityIdentifier("decide-more-done")
        }
        .navigationTitle(Text("Filtros")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Quitar filtros") { m.clearFilters() }
                    .disabled(!hasFilters(m))
                    .accessibilityIdentifier("decide-filters-clear")
            }
        }
        .onAppear { if opened == nil { opened = m.filtersSignature } }
        // Al volver, los carteles ya son de lo elegido; si no cambió nada, se quedan los mismos tres.
        .onDisappear { if m.filtersSignature != opened { Task { await m.apply() } } }
    }

    private func hasFilters(_ m: DecideModel) -> Bool {
        m.moreFilters > 0 || m.minRating > 0 || m.minLetterboxd > 0 || m.timeChosen || m.mood != nil
    }

    // MARK: Esta noche
    /// En «Una por una» se ve pero apagada (el mazo es para guardar, no para esta noche): lo puesto sigue a la vista y cuenta
    /// en el botón «Filtros», que es el mismo en las dos pestañas.
    @ViewBuilder private func tonight(_ m: DecideModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            DSSectionHead(title: "Esta noche", level: .section)
            if deck { Text("Solo en «Tres que caben»").recipe(.caption, color: DS.textFaint) }
            Group {
            DSSectionHead(title: "Duración")
            LazyVGrid(columns: columns(3), spacing: DS.Space.s2) {
                ForEach(DecideModel.Time.allCases, id: \.self) { t in
                    let on = m.shownTime == t
                    let count = m.count(strictTime: true) { $0.time = t }
                    DecideChoice(symbol: DS.Symbol.filterTime, title: Text(verbatim: words.timeName(t)), count: count, tint: DS.DecideLive.time,
                                 selected: on, enabled: DecideModel.offered(count, selected: on)) { m.setTime(on ? nil : t) }
                        .accessibilityIdentifier("decide-time-\(t.rawValue)")
                }
            }
            DSSectionHead(title: "Ánimo").padding(.top, DS.Space.s3)
            LazyVGrid(columns: columns(4), spacing: DS.Space.s2) {
                ForEach(DecideModel.Mood.allCases, id: \.self) { mood in
                    let on = m.mood == mood
                    let count = m.count { $0.mood = mood }
                    DecideChoice(symbol: words.moodSymbol(mood), title: Text(LocalizedStringKey(words.moodLabel(mood))), count: count, tint: DS.DecideLive.mood,
                                 selected: on, enabled: DecideModel.offered(count, selected: on), reservesTwoLines: true) { m.mood = on ? nil : mood }
                        .accessibilityIdentifier("decide-mood-\(mood.rawValue)")
                }
            }
            }
            .disabled(deck)
            .opacity(deck ? DS.Opacity.dimmed : 1)
        }
    }

    // MARK: Qué tan buena
    @ViewBuilder private func quality(_ m: DecideModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            DSSectionHead(title: "Qué tan buena", level: .section)
            DSSectionHead(title: "Calificación")
            LazyVGrid(columns: columns(3), spacing: DS.Space.s2) {
                ForEach(DecideModel.ratingSteps.filter { $0 > 0 }, id: \.self) { r in
                    let on = m.minRating == r
                    let count = m.count { $0.minRating = r }
                    DecideChoice(symbol: DS.Symbol.filterRating, title: Text(verbatim: String(format: "%.0f+", r)), count: count, tint: DS.DecideLive.rating,
                                 selected: on, enabled: DecideModel.offered(count, selected: on)) { m.minRating = on ? 0 : r }
                        .accessibilityIdentifier("decide-rating-\(Int(r))")
                }
            }
            Text("Según (basta una)").recipe(.caption, color: DS.textFaint)
            LazyVGrid(columns: columns(3), spacing: DS.Space.s2) {
                ForEach(DecideModel.RatingSource.allCases, id: \.self) { source in
                    let on = m.ratingSources.contains(source)
                    let usable = source != .tmdb || env.services.tmdb.configured
                    FilterLogoChoice(title: Text(verbatim: ratingSourceName(source)), selected: on) {
                        if !on { m.ratingSources.insert(source) } else if m.ratingSources.count > 1 { m.ratingSources.remove(source) }
                    } logo: { Image("rating-\(source.rawValue)").resizable().scaledToFit() }
                    .disabled(!usable).opacity(usable ? 1 : DS.Opacity.dimmed)
                }
            }
            DSSectionHead(title: "Letterboxd · solo películas").padding(.top, DS.Space.s3)
            LazyVGrid(columns: columns(3), spacing: DS.Space.s2) {
                ForEach(DecideModel.letterboxdSteps.filter { $0 > 0 }, id: \.self) { r in
                    let on = m.minLetterboxd == r
                    let count = m.letterboxdReady ? m.count { $0.minLetterboxd = r } : nil
                    DecideChoice(symbol: DS.Symbol.filterRating, title: Text(verbatim: "\(DecideWords.stars(r))+"), count: count, tint: DS.DecideLive.rating,
                                 selected: on, enabled: count.map { DecideModel.offered($0, selected: on) } ?? true) {
                        m.minLetterboxd = on ? 0 : r
                        m.fetchLetterboxdInBackground()
                    }
                }
            }
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) { fame(m) }.padding(.top, DS.Space.s3)
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) { awards(m) }.padding(.top, DS.Space.s3)
        }
    }

    private func ratingSourceName(_ s: DecideModel.RatingSource) -> String {
        switch s { case .imdb: "IMDb"; case .trakt: "Trakt"; case .tmdb: env.services.tmdb.configured ? "TMDB" : Strings.tr("TMDB (falta su clave)", language: language) }
    }

    // MARK: Qué tipo
    @ViewBuilder private func kindOf(_ m: DecideModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            DSSectionHead(title: "Qué tipo", level: .section)
            DSSectionHead(title: "Géneros")
            Text("Elige uno o varios · el número es cuántas hay").recipe(.caption, color: DS.textFaint)
            // Mosaicos con el arte de tus sugerencias de cada género (el `id` con lo elegido: ver `FlowChips`).
            LazyVGrid(columns: columns(3), spacing: DS.Space.s2) {
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
            DSSectionHead(title: "Época").padding(.top, DS.Space.s3)
            // En la misma cuadrícula de tres que los géneros: «2020s» y «90s» del mismo tamaño (F12).
            LazyVGrid(columns: columns(3), spacing: DS.Space.s2) {
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
        }
    }

    // MARK: De dónde
    @ViewBuilder private func origin(_ m: DecideModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            DSSectionHead(title: "De dónde", level: .section)
            if !m.sources.isEmpty { lists(m) }
            Toggle(isOn: Binding(get: { m.includeWatched }, set: { m.includeWatched = $0 })) { Text("Incluir lo que ya vi").recipe(.secondary, color: DS.text) }
                .tint(DS.accent)
        }
    }

    /// «Qué tan conocida» (los votos de TMDB, como en el filtro avanzado): se piden al elegir una y se recuerdan; hasta
    /// tenerlos todos, sin número.
    @ViewBuilder private func fame(_ m: DecideModel) -> some View {
        DSSectionHead(title: "Fama")
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
        DSSectionHead(title: "Premios")
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
