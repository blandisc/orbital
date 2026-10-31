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
    @State private var more = false
    @State private var detent: PresentationDetent = AdvancedFilterSheet.short
    /// Lo que mide el cajón cerrado (formato, mosaicos, «Más filtros» y «Ver resultados»): la altura corta es esa, sin aire
    /// muerto abajo.
    @State private var fit: CGFloat = 0
    /// Lo que miden «Ver resultados» y el margen de abajo del iPhone (aparte: dentro de la lista entran y salen de la medida).
    @State private var actionsHeight: CGFloat = 0

    var body: some View {
        let model = env.advancedFilter
        let _ = model.track()
        let context = FilterContext(filter: model.filter, platforms: model.platforms, language: env.services.appSettings.uiLanguage)
        NavigationStack {
            ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        formatBar(model)
                        grid(FilterPage.main, context, model)
                        FilterMoreRow(expanded: more, active: FilterPage.more.filter { FilterText.value($0, context) != nil }.count) {
                            withAnimation(DS.Motion.smooth(reduceMotion)) {
                                more.toggle()
                                if !more, let o = open, FilterPage.more.contains(o) { open = nil }
                            }
                        }
                        .accessibilityIdentifier("filter-more")
                        if more {
                            grid(FilterPage.more, context, model)
                                .transition(.opacity.combined(with: .offset(y: -DS.Space.s3)))
                        }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    .padding(.bottom, DS.Space.s2)
                    // El cajón cerrado mide su contenido + la barra de arriba + «Ver resultados» + el margen de abajo del iPhone (cada
                    // uno por su lado: la lista mete y saca esos márgenes de su propia medida y la hoja brincaba).
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        let total = h + DS.Filter.sheetBar + actionsHeight + AppWindows.safeArea.bottom
                        guard open == nil, !more, actionsHeight > 0, abs(total - fit) > 1 else { return }
                        fit = total
                        detent = shortDetent   // cerrado, siempre a su medida (la primera medida, al aparecer, sale de más)
                    }
                }
                // Abrir un filtro no mueve la lista: el panel baja desde su mosaico y lo de abajo se recorre (Fernando, 31 oct 2026).
                .sensoryFeedback(.selection, trigger: open)

            .safeAreaInset(edge: .bottom) {
                actions(model).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsHeight = $0 }
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
            more = FilterPage.more.contains(start)
            open = start
            if start == .length { model.refreshClock() }
        }
        .presentationDetents([shortDetent, .large], selection: $detent)
        .onChange(of: open) { detent = open != nil || more ? .large : shortDetent }
        .onChange(of: more) { detent = open != nil || more ? .large : shortDetent }
        .accessibilityElement(children: .contain)   // cada pieza de adentro conserva su identificador
        .accessibilityIdentifier("advanced-filter")
    }

    /// La altura corta antes de medir: lo justo para el formato, los seis mosaicos y «Ver resultados» (en una pantalla baja,
    /// la grande).
    static var short: PresentationDetent { WindowMetrics.size.height < DS.Filter.shortScreen ? .large : .fraction(DS.Filter.shortFraction) }

    /// Ya medido: lo que trae el cajón cerrado, sin aire muerto (si no cabe, la grande).
    private var shortDetent: PresentationDetent {
        guard fit > 0 else { return Self.short }
        return fit >= WindowMetrics.size.height * DS.Filter.fitMax ? .large : .height(fit)
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
            Label { Text("Ocultar lo que ya viste").recipe(.footnote, color: DS.text).fontWeight(.semibold) } icon: {
                Image(systemName: "eye.slash").foregroundStyle(DS.orbitalBlue)
            }
        }
        .tint(DS.orbitalBlue)
        .padding(.horizontal, DS.Space.s3)
        .frame(minHeight: DS.Size.touchTarget)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
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
                    .id(o)   // otro filtro: otro panel (el de antes se va, el nuevo baja)
                    // Baja desde su mosaico: crece desde arriba y aparece; al cerrarse se recoge hacia arriba.
                    // Al cambiar de filtro, el de antes se apaga rápido y el nuevo baja: sin brincos.
                    .transition(.asymmetric(insertion: .scale(scale: DS.Filter.panelFrom, anchor: .top).combined(with: .opacity),
                                            removal: .opacity.animation(DS.Motion.base(reduceMotion))))
                }
            }
        }
        .animation(DS.Motion.smooth(reduceMotion), value: open)   // lo de abajo se reacomoda con el mismo resorte
    }

    private func toggle(_ page: FilterPage, _ model: AdvancedFilterModel) {
        if page == .length { model.refreshClock() }
        withAnimation(DS.Motion.smooth(reduceMotion)) { open = open == page ? nil : page }
    }

    private func actions(_ model: AdvancedFilterModel) -> some View {
        HStack(spacing: DS.Space.s3) {
            if !model.filter.isEmpty {
                Button("Limpiar") { withAnimation(DS.Motion.base(reduceMotion)) { model.clear() } }
                    .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
                    .accessibilityIdentifier("filter-clear")
            }
            Button(action: onResults) {
                Text(model.filter.isEmpty ? "Ver resultados" : "Ver resultados · \(model.filter.activeCount)").frame(maxWidth: .infinity)
            }
            .dsSolidPrimaryButton().controlSize(.large)   // el principal sólido de la app: se lee siempre
            .accessibilityIdentifier("filter-results")
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.vertical, DS.Space.s2)
    }
}
