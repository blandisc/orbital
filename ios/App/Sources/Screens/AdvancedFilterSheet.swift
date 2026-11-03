import SwiftUI
import OrbitalCore
import OrbitalModels

extension View {
    /// El filtro avanzado como hoja: el cajón de dos alturas donde cada filtro se abre ahí mismo, bajo su mosaico.
    /// «Ver resultados» cierra la hoja y avisa con `onResults` (Buscar enseña los resultados en su propia pantalla).
    func advancedFilter(isPresented: Binding<Bool>, start: FilterPage? = nil, onResults: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            AdvancedFilterSheet(start: start) {
                isPresented.wrappedValue = false
                onResults()
            }
        }
    }
}

/// El cajón del filtro avanzado (entrada A, Fernando, 31 oct 2026): arriba el formato (Todo · Películas · Series, con «En
/// emisión / Terminadas» al elegir Series) y el ojo de «Ocultar lo que ya vi»; seis mosaicos y «Ver más filtros» (origen,
/// premios y estudios). Tocar un mosaico abre su control debajo de su renglón, en el mismo cajón; tocar otro cierra el
/// anterior. Nunca cambia de pantalla. Corto mientras eliges; crece al abrir un filtro o «Ver más».
struct AdvancedFilterSheet: View {
    /// El filtro que se abre de entrada (lo tocado en la puerta de Buscar).
    var start: FilterPage?
    let onResults: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open: FilterPage?

    var body: some View {
        let model = env.advancedFilter
        let _ = model.track()
        let context = FilterContext(filter: model.filter, platforms: model.platforms, language: env.services.appSettings.uiLanguage)
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                    VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                        formatBar(model)
                        // Los nueve filtros siempre a la vista, con el cajón en su altura máxima (Fernando, 31 oct 2026): sin
                        // «Más filtros / Menos filtros» ni la altura corta.
                        grid(FilterPage.main + FilterPage.more, context, model)
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    .padding(.bottom, DS.Space.s2)
                }
                // Abrir un filtro no mueve la lista: el panel baja desde su mosaico y lo de abajo se recorre (Fernando, 31 oct 2026).
                // Solo si el panel queda debajo de la orilla, la lista sube lo justo para que se vea entero.
                .sensoryFeedback(.selection, trigger: open)
                .onChange(of: open) { _, page in
                    guard let page else { return }
                    Task {
                        try? await Task.sleep(for: DS.Filter.revealAfter)
                        guard open == page else { return }
                        withAnimation(DS.Motion.smooth(reduceMotion)) { proxy.scrollTo(Self.panelID(page), anchor: nil) }
                    }
                }
            }

            .safeAreaInset(edge: .bottom) {
                actions(model)
            }
            .navigationTitle(model.filter.isEmpty ? Text("Filtros") : Text("Filtros · \(model.filter.activeCount)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Con un filtro abierto, lo cierra; si no, cierra el cajón.
                    Button("Listo") {
                        if open != nil { withAnimation(DS.Motion.smooth(reduceMotion)) { open = nil } } else { dismiss() }
                    }
                    .accessibilityIdentifier("filter-done")
                }
            }
        }
        .task { await model.loadPlatforms() }
        .onAppear {
            guard let start, open == nil else { return }
            open = start
            if start == .length { model.refreshClock() }
        }
        .presentationDetents([.large])
        .accessibilityElement(children: .contain)   // cada pieza de adentro conserva su identificador
        .accessibilityIdentifier("advanced-filter")
    }

    /// El formato de un toque y el ojo de «Ocultar lo que ya vi»; con «Series», cuáles series ahí mismo.
    @ViewBuilder private func formatBar(_ model: AdvancedFilterModel) -> some View {
        let kind = Binding<String>(
            get: { model.filter.format == .movie ? "movie" : model.filter.format == .series ? "series" : "" },
            set: { new in
                model.filter.format = new == "movie" ? .movie : new == "series" ? .series : .all
                if model.filter.format != .series { model.filter.seriesStatus = .any }
            })
        DSKindFilter(kind: kind, mark: DS.orbitalBlue)
        // «Ocultar lo que ya viste», dicho con palabras (el ojo tachado solo no se entendía; Fernando, 31 oct 2026).
        Toggle(isOn: Binding(get: { model.filter.hideWatched }, set: { model.filter.hideWatched = $0 })) {
            Label { Text("Ocultar lo que ya viste").recipe(.label, color: DS.text) } icon: {
                Image(systemName: "eye.slash").foregroundStyle(DS.orbitalBlue)
            }
        }
        .tint(DS.orbitalBlue)
        .padding(.horizontal, DS.Space.s3)
        .frame(minHeight: DS.Size.touchTarget)
        .dsCard()
        .accessibilityIdentifier("filter-hide-watched")
        if model.filter.format == .series {
            let statuses: [(AdvancedFilter.SeriesStatus, LocalizedStringKey)] = [(.any, "Todas"), (.airing, "En emisión"), (.ended, "Terminadas")]
            DSSegmented(options: statuses,
                        selection: Binding(get: { model.filter.seriesStatus }, set: { model.filter.seriesStatus = $0 }))
                .accessibilityIdentifier("filter-series-status")
        }
    }

    /// Los mosaicos de dos en dos; el abierto lleva su panel debajo de su renglón, con la flechita hacia él.
    private func grid(_ pages: [FilterPage], _ context: FilterContext, _ model: AdvancedFilterModel) -> some View {
        VStack(spacing: DS.Space.s3) {
            ForEach(Array(stride(from: 0, to: pages.count, by: 2)), id: \.self) { i in
                let row = Array(pages[i..<min(i + 2, pages.count)])
                HStack(spacing: DS.Space.s2) {
                    ForEach(row) { page in
                        FilterTile(page: page, context: context, open: open == page) { toggle(page, model) }
                            .id(page)
                            .accessibilityIdentifier("filter-\(page.rawValue)")
                    }
                }
                if let o = open, let index = row.firstIndex(of: o) {
                    FilterPanel(notch: row.count == 1 ? 0.5 : index == 0 ? 0.25 : 0.75) {
                        FilterEditor(page: o, model: model, context: context)
                    }
                    .id(Self.panelID(o))   // otro filtro: otro panel (el de antes se va, el nuevo baja)
                    // Baja desde su mosaico: aparece y se asienta un poco hacia abajo; al cerrarse se apaga.
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -DS.Space.s3)),
                                            removal: .opacity.animation(DS.Motion.base(reduceMotion))))
                }
            }
        }
        .animation(DS.Motion.smooth(reduceMotion), value: open)   // lo de abajo se reacomoda con el mismo resorte
        .animation(DS.Motion.smooth(reduceMotion), value: FilterTile.compact(context))   // el primer filtro: los mosaicos crecen juntos
    }

    /// Otro filtro con uno abierto: primero se cierra el de antes y, ya quieto, baja el nuevo. Antes pasaba todo a la vez
    /// (uno se recogía, el otro crecía y lo de en medio se corría) y se veía desordenado, sobre todo abriendo uno de abajo.
    private func toggle(_ page: FilterPage, _ model: AdvancedFilterModel) {
        if page == .length { model.refreshClock() }
        guard let current = open, current != page, !reduceMotion else {
            withAnimation(DS.Motion.smooth(reduceMotion)) { open = open == page ? nil : page }
            return
        }
        withAnimation(DS.Motion.base(reduceMotion)) { open = nil }
        Task {
            try? await Task.sleep(for: DS.Filter.switchPause)
            guard open == nil else { return }
            withAnimation(DS.Motion.smooth(reduceMotion)) { open = page }
        }
    }

    private static func panelID(_ page: FilterPage) -> String { "panel-" + page.rawValue }

    /// «Ver 1 240 resultados» (Fernando, 2 nov 2026), «Ver hasta 860 resultados» si después se quitan las que no llegan a tus
    /// estrellas de Letterboxd o las series que no caben en tu tiempo, «Nada con estos filtros» con cero, y «Ver resultados»
    /// mientras no se sabe (sin clave de TMDB o sin respuesta).
    private func resultsLabel(_ preview: AdvancedFilterModel.Preview?) -> Text {
        guard let preview else { return Text("Ver resultados") }
        let n = preview.count.total
        if n == 0 { return Text("Nada con estos filtros") }
        let number = Strings.count(n, language: env.services.appSettings.uiLanguage)
        switch (preview.upTo, n == 1) {
        case (false, true): return Text("Ver 1 resultado")
        case (false, false): return Text("Ver \(number) resultados")
        case (true, true): return Text("Ver hasta 1 resultado")
        case (true, false): return Text("Ver hasta \(number) resultados")
        }
    }

    private func actions(_ model: AdvancedFilterModel) -> some View {
        HStack(spacing: DS.Space.s3) {
            if !model.filter.isEmpty {
                Button("Limpiar") { withAnimation(DS.Motion.base(reduceMotion)) { model.clear() } }
                    .dsGlassButton().buttonBorderShape(.capsule).controlSize(.large)
                    .accessibilityIdentifier("filter-clear")
            }
            Button(action: onResults) {
                resultsLabel(model.preview).frame(maxWidth: .infinity)
                    .contentTransition(.numericText()).animation(DS.Motion.base(reduceMotion), value: model.preview)
            }
            .dsSolidPrimaryButton().controlSize(.large)   // el principal sólido de la app: se lee siempre
            .disabled(model.preview?.count.total == 0)
            .accessibilityIdentifier("filter-results")
            .task { model.schedulePreview() }
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.vertical, DS.Space.s2)
    }
}
