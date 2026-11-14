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
    /// Tres columnas en toda la hoja (el ánimo, cuatro, en dos por dos: las mismas orillas que las demás); con letra de
    /// accesibilidad, dos, para que los nombres quepan enteros.
    private var wide: Int { typeSize.isAccessibilitySize ? 2 : 3 }
    private var pairs: Int { 2 }

    /// Lo que dice una baldosa: cuántas quedarían si eliges esa, con lo demás puesto (`DecideModel.tally`); nil mientras no
    /// se sabe (nunca «0»). Se calcula aquí, en cada pasada de la hoja, no dentro de cada baldosa: así siempre es el de ahora.
    private func tally(_ m: DecideModel, strictTime: Bool? = nil, _ change: (inout DecideModel.Filters) -> Void) -> DecideModel.Tally {
        m.tally(deck: deck, strictTime: strictTime, change)
    }

    var body: some View {
        let _ = BodyCount.tick("decide-filters", why: Self._printChanges)   // cuántas veces se pinta (`-perf-bodies`)
        let m = observer.model
        let total = m.tally(deck: deck)
        let count = total.known
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                Text(verbatim: count == 0 && total.pending > 0 ? Strings.tr("Buscando opciones…", language: language) : words.optionsLine(m, count))
                    .recipe(.labelLarge, color: DS.text).monospacedDigit().contentTransition(.numericText())
                    .animation(DS.Motion.fade, value: count)
                    .accessibilityIdentifier("decide-filters-count")
                tonight(m)
                quality(m)
                kindOf(m)
                origin(m)
            }
            .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s2).padding(.bottom, DS.Space.s4)
        }
        // «Ver N» flota abajo con el mismo margen de los lados; lo que pasa por debajo se funde (no queda un renglón a medias
        // tapado por el botón; regla «Un botón fijo abajo deja ver lo que pasa debajo»).
        .safeAreaBar(edge: .bottom) {
            Button { done() } label: {
                Text(count > 0 ? String(format: Strings.tr("Ver %lld", language: language), count)
                     : total.pending > 0 ? Strings.tr("Buscando opciones…", language: language) : Strings.tr("Sin opciones con eso", language: language))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
            }
            .dsPrimaryButton().controlSize(.large)
            .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s2)
            .accessibilityIdentifier("decide-more-done")
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle(Text("Filtros")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Discreto y solo cuando hay algo que quitar (antes un botón de vidrio grande, apagado casi siempre).
            if hasFilters(m) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { m.clearFilters() } label: { Text("Quitar filtros").recipe(.labelLarge, color: DS.text) }
                        .accessibilityIdentifier("decide-filters-clear")
                }
                .sharedBackgroundVisibility(.hidden)
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
        let times = Dictionary(uniqueKeysWithValues: DecideModel.Time.allCases.map { t in (t, tally(m, strictTime: true) { $0.time = t }) })
        let moods = Dictionary(uniqueKeysWithValues: DecideModel.Mood.allCases.map { mood in (mood, tally(m) { $0.mood = mood }) })
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            DSSectionHead(title: "Esta noche", level: .section)
            if deck { Text("Solo en «Tres que caben»").recipe(.caption, color: DS.textFaint) }
            Group {
            DSSectionHead(title: "Duración")
            DecideChoiceGrid(items: DecideModel.Time.allCases, columns: wide) { t in
                let on = m.shownTime == t
                let n = times[t]
                DecideChoice(symbol: DS.Symbol.filterTime, title: Text(verbatim: words.timeName(t)), count: n?.shown, tint: DS.DecideLive.time,
                             selected: on, enabled: on || n?.open == true) { m.setTime(on ? nil : t) }
                    .accessibilityIdentifier("decide-time-\(t.rawValue)")
            }
            DSSectionHead(title: "Ánimo").padding(.top, DS.Space.s3)
            DecideChoiceGrid(items: DecideModel.Mood.allCases, columns: pairs) { mood in
                let on = m.mood == mood
                let n = moods[mood]
                DecideChoice(symbol: words.moodSymbol(mood), title: Text(LocalizedStringKey(words.moodLabel(mood))), count: n?.shown, tint: DS.DecideLive.mood,
                             selected: on, enabled: on || n?.open == true) { m.mood = on ? nil : mood }
                    .accessibilityIdentifier("decide-mood-\(mood.rawValue)")
            }
            }
            .disabled(deck)
            .opacity(deck ? DS.Opacity.dimmed : 1)
        }
    }

    // MARK: Qué tan buena
    @ViewBuilder private func quality(_ m: DecideModel) -> some View {
        let steps = DecideModel.ratingSteps.filter { $0 > 0 }, boxd = DecideModel.letterboxdSteps.filter { $0 > 0 }
        let ratings = Dictionary(uniqueKeysWithValues: steps.map { r in (r, tally(m) { $0.minRating = r }) })
        let letterboxd = Dictionary(uniqueKeysWithValues: boxd.map { r in (r, tally(m) { $0.minLetterboxd = r }) })
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            DSSectionHead(title: "Qué tan buena", level: .section)
            DSSectionHead(title: "Calificación")
            DecideChoiceGrid(items: steps, columns: wide) { r in
                let on = m.minRating == r
                let n = ratings[r]
                DecideChoice(symbol: DS.Symbol.filterRating, title: Text(verbatim: String(format: "%.0f+", r)), count: n?.shown, tint: DS.DecideLive.rating,
                             selected: on, enabled: on || n?.open == true) { m.minRating = on ? 0 : r }
                    .accessibilityIdentifier("decide-rating-\(Int(r))")
            }
            Text("Según (basta una)").recipe(.caption, color: DS.textFaint)
            DecideChoiceGrid(items: DecideModel.RatingSource.allCases, columns: wide) { source in
                let on = m.ratingSources.contains(source)
                let usable = source != .tmdb || env.services.tmdb.configured
                FilterLogoChoice(title: Text(verbatim: ratingSourceName(source)), selected: on) {
                    if !on { m.ratingSources.insert(source) } else if m.ratingSources.count > 1 { m.ratingSources.remove(source) }
                } logo: { Image("rating-\(source.rawValue)").resizable().scaledToFit().frame(maxWidth: DS.Filter.ratingLogo) }
                .disabled(!usable).opacity(usable ? 1 : DS.Opacity.dimmed)
                .accessibilityIdentifier("decide-source-\(source.rawValue)")
            }
            DSSectionHead(title: "Letterboxd · solo películas").padding(.top, DS.Space.s3)
            DecideChoiceGrid(items: boxd, columns: wide) { r in
                let on = m.minLetterboxd == r
                let n = letterboxd[r]
                DecideChoice(symbol: DS.Symbol.filterRating, title: Text(verbatim: "\(DecideWords.stars(r))+"), count: n?.shown, tint: DS.DecideLive.rating,
                             selected: on, enabled: on || n?.open == true) {
                    m.minLetterboxd = on ? 0 : r
                    m.fetchLetterboxdInBackground()
                }
                .accessibilityIdentifier("decide-letterboxd-\(Int(r * 10))")
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
        let genres = Dictionary(uniqueKeysWithValues: DecideModel.genreChoices.map { g in (g, tally(m) { $0.genres = [g] }) })
        let eras = Dictionary(uniqueKeysWithValues: DecideModel.decadeChoices.map { d in (d, tally(m) { $0.decades = [d] }) })
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            DSSectionHead(title: "Qué tipo", level: .section)
            DSSectionHead(title: "Géneros")
            Text("Elige uno o varios · el número es cuántas hay").recipe(.caption, color: DS.textFaint)
            // Mosaicos con el arte de tus sugerencias de cada género.
            DecideChoiceGrid(items: DecideModel.genreChoices, columns: wide) { g in
                let on = m.genres.contains(g)
                let n = genres[g]
                DecideTile(title: Text(verbatim: genreName(g, language: env.language)), image: DecideView.tileImage(genre: g), selected: on,
                           dimmed: !m.genres.isEmpty && !on, count: n?.shown,
                           height: DS.Decide.genreTile, enabled: on || n?.open == true) {
                    if on { m.genres.remove(g) } else { m.genres.insert(g) }
                }
                .accessibilityIdentifier("decide-genre-\(g)")
            }
            .onChange(of: m.genres) { m.resolveUnknown() }
            DSSectionHead(title: "Época").padding(.top, DS.Space.s3)
            // En la misma cuadrícula de tres que los géneros: «2020s» y «90s» del mismo tamaño (F12).
            DecideChoiceGrid(items: DecideModel.decadeChoices, columns: wide) { d in
                let on = m.decades.contains(d)
                let n = eras[d]
                DecideTile(title: d == 1980 ? Text("Antes") : Text(verbatim: d >= 2000 ? "\(d)s" : "\(d % 100)s"), image: "decide-era-\(d)",
                           selected: on, dimmed: !m.decades.isEmpty && !on,
                           count: n?.shown, height: DS.Decide.eraTile, era: true, enabled: on || n?.open == true) {
                    if on { m.decades.remove(d) } else { m.decades.insert(d) }
                }
                .accessibilityIdentifier("decide-era-\(d)")
            }
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
            let counts = m.fameReady ? Dictionary(uniqueKeysWithValues: [AdvancedFilter.Fame.gems, .classics, .niche, .blockbusters].map { f in (f, m.tally(deck: deck) { $0.fame = f }.known) }) : nil
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
        let counts = Dictionary(uniqueKeysWithValues: FilterCatalog.awards.map { id in (id, tally(m) { $0.awards = [id] }) })
        DSSectionHead(title: "Premios")
        DecideChoiceGrid(items: FilterCatalog.awards, columns: wide) { id in
            let on = m.awards.contains(id)
            let n = counts[id]
            let offered = on || n?.open == true
            FilterLogoChoice(title: n?.shown.map { Text("\(AwardNames.title(id)) · \($0)") } ?? AwardNames.title(id), selected: on) {
                m.awards.formSymmetricDifference([id])
            } logo: { Image("Awards/" + id).resizable().scaledToFit() }
            .disabled(!offered).opacity(offered ? 1 : DS.Opacity.dimmed)
            .accessibilityIdentifier("decide-award-\(id)")
        }
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
                // De dónde, en el selector de toda la app (SL1; antes pestañas de texto y, antes, cápsulas de solo texto).
                DSSelector(options: [.init(id: "", title: Text(verbatim: String(format: Strings.tr("Todas · %lld", language: language), all.count)))]
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
        .scrollEdgeEffectStyle(.hard, for: .top)   // el buscador flota: lo de debajo se tapa, no se ve a través
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(verbatim: String(format: Strings.tr("Buscar entre tus %lld listas", language: language), all.count)))
        .safeAreaBar(edge: .bottom) {
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
        .scrollEdgeEffectStyle(.soft, for: .bottom)
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
