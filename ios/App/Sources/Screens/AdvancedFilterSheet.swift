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

    var body: some View {
        let model = env.advancedFilter
        let _ = model.track()
        let collections = env.collections
        let _ = collections.track()
        let context = FilterContext(filter: model.filter, platforms: model.platforms, studioLogos: collections.studioLogos,
                                    language: env.services.appSettings.uiLanguage)
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        formatBar(model)
                        grid(FilterPage.main, context, model)
                        if more {
                            PanelGroupTitle(title: "Más filtros")
                            grid(FilterPage.more, context, model)
                        }
                        Button {
                            withAnimation(DS.Motion.base(reduceMotion)) {
                                more.toggle()
                                if !more, let o = open, FilterPage.more.contains(o) { open = nil }
                            }
                        } label: {
                            Label(more ? "Ver menos" : "Ver más filtros", systemImage: more ? "chevron.up" : "chevron.down").recipe(.footnote, color: DS.text).fontWeight(.semibold)
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                        .accessibilityIdentifier("filter-more")
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    .padding(.bottom, DS.Space.s4)
                }
                .onChange(of: open) { _, page in
                    guard let page else { return }
                    withAnimation(DS.Motion.base(reduceMotion)) { proxy.scrollTo(page, anchor: .top) }
                }
            }
            .safeAreaInset(edge: .bottom) { actions(model) }
            .navigationTitle(model.filter.isEmpty ? Text("Filtros") : Text("Filtros · \(model.filter.activeCount)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Con un filtro abierto, lo cierra; si no, cierra el cajón.
                    Button("Listo") {
                        if open != nil { withAnimation(DS.Motion.base(reduceMotion)) { open = nil } } else { dismiss() }
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
        .presentationDetents([Self.short, .large], selection: $detent)
        .onChange(of: open) { detent = open != nil || more ? .large : Self.short }
        .onChange(of: more) { detent = open != nil || more ? .large : Self.short }
        .accessibilityElement(children: .contain)   // cada pieza de adentro conserva su identificador
        .accessibilityIdentifier("advanced-filter")
    }

    /// La altura corta: lo justo para el formato, los seis mosaicos y «Ver resultados» (en una pantalla baja, la grande).
    static var short: PresentationDetent { WindowMetrics.size.height < DS.Filter.shortScreen ? .large : .fraction(DS.Filter.shortFraction) }

    /// El formato de un toque y el ojo de «Ocultar lo que ya vi»; con «Series», cuáles series ahí mismo.
    @ViewBuilder private func formatBar(_ model: AdvancedFilterModel) -> some View {
        let kind = Binding<String>(
            get: { model.filter.format == .movie ? "movie" : model.filter.format == .series ? "series" : "" },
            set: { new in
                model.filter.format = new == "movie" ? .movie : new == "series" ? .series : .all
                if model.filter.format != .series { model.filter.seriesStatus = .any }
            })
        let hide = model.filter.hideWatched
        HStack(spacing: DS.Space.s2) {
            DSKindFilter(kind: kind, mark: DS.orbitalBlue)
            Button { model.filter.hideWatched.toggle() } label: {
                Image(systemName: "eye.slash").font(DS.TextRecipe.secondary.font.weight(.semibold))
                    .foregroundStyle(hide ? DS.bg : DS.textMuted)
                    .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                    .background(hide ? DS.orbitalBlue : DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: hide)
            .accessibilityLabel(Text("Ocultar lo que ya vi"))
            .accessibilityAddTraits(hide ? .isSelected : [])
            .accessibilityIdentifier("filter-hide-watched")
        }
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func toggle(_ page: FilterPage, _ model: AdvancedFilterModel) {
        if page == .length { model.refreshClock() }
        withAnimation(DS.Motion.base(reduceMotion)) { open = open == page ? nil : page }
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
