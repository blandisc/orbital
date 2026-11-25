import SwiftUI
import OrbitalCore
import OrbitalModels

/// La puerta de Búsqueda avanzada, refinada como lo haría Apple (propuestas R1 y R2, Fernando, 25 nov 2026: «refina lo que
/// tenemos hoy»): la misma tarjeta, pero callada. Sin tinte ni orilla turquesa ni círculo turquesa; el título con su flecha y
/// una línea corta. R1: los seis atajos dentro de la tarjeta, solo su ícono a color y su nombre (sin cajitas negras).
/// R2: los seis en un renglón de círculos, como los atajos de Centro de control.
struct FilterDoorQuiet: View {
    enum Style: String { case card = "R1", circles = "R2" }
    /// Cuál se ve: `-door R1` o `-door R2` al abrir la app; sin nada, la puerta de siempre (hasta que Fernando elija).
    static var chosen: Style? { UserDefaults.standard.string(forKey: "door").flatMap(Style.init(rawValue:)) }

    let style: Style
    let context: FilterContext
    let count: FilterCount?
    let open: (FilterPage?) -> Void
    var clear: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(alignment: .center, spacing: DS.Space.s4) {
                Button { open(nil) } label: {
                    VStack(alignment: .leading, spacing: DS.Space.s1 / 2) {
                        HStack(spacing: DS.Space.s1) {
                            Text("Búsqueda avanzada").recipe(.cardTitle)
                            Image(systemName: "chevron.forward").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted)
                        }
                        subtitle.recipe(.footnote, color: DS.textMuted).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("browse-filters")
                if !context.filter.isEmpty {
                    DSIconButton(symbol: DS.Symbol.remove, label: "Limpiar la búsqueda avanzada", size: .regular, action: clear)
                        .accessibilityIdentifier("browse-filters-clear")
                }
            }
            switch style {
            case .card:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: DS.Space.s4) {
                    ForEach(FilterPage.main) { page in
                        shortcut(page) {
                            VStack(spacing: DS.Space.s1) {
                                Image(systemName: page.symbol).font(DS.TextRecipe.title.font).foregroundStyle(page.hue).frame(height: DS.Filter.artHeight)
                                label(page)
                            }
                        }
                    }
                }
            case .circles:
                HStack(alignment: .top, spacing: 0) {
                    ForEach(FilterPage.main) { page in
                        shortcut(page) {
                            VStack(spacing: DS.Space.s1) {
                                Image(systemName: page.symbol).font(DS.TextRecipe.labelLarge.font).foregroundStyle(page.hue)
                                    .frame(width: DS.Filter.quietCircle, height: DS.Filter.quietCircle)
                                    .background(DS.surfaceRaised, in: Circle())
                                    .overlay { if on(page) { Circle().strokeBorder(page.hue, lineWidth: DS.Stroke.selected) } }
                                label(page)
                            }
                        }
                    }
                }
            }
        }
        .padding(DS.Space.s4)
        .dsCard(.card)
    }

    private func on(_ page: FilterPage) -> Bool { FilterText.value(page, context) != nil }

    private func label(_ page: FilterPage) -> some View {
        page.short.recipe(.caption, color: on(page) ? DS.text : DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
    }

    private func shortcut<Label: View>(_ page: FilterPage, @ViewBuilder _ label: () -> Label) -> some View {
        Button { open(page) } label: { label().frame(maxWidth: .infinity).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(FilterText.value(page, context) ?? Text("Cualquiera"))
            .accessibilityIdentifier("browse-filter-\(page.rawValue)")
    }

    private var subtitle: Text {
        let n = context.filter.activeCount
        guard n > 0 else { return Text("Por género, época, calificación y más") }
        let filters = n == 1 ? Text("1 filtro") : Text("\(n) filtros")
        guard let count else { return filters }
        return Text("\(filters) · \(ResultCountHeader.phrase(count, language: context.language))")
    }
}

extension FilterPage {
    /// El nombre corto, para los atajos de la puerta (cabe en un renglón de seis).
    var short: Text { self == .rating ? Text("Calificación") : self == .place ? Text("Dónde") : title }
}
