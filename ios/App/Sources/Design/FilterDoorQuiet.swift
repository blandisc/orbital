import SwiftUI
import OrbitalCore
import OrbitalModels

/// La puerta de Búsqueda avanzada con la identidad del cajón (propuestas BA-A y BA-B, Fernando, 25 nov 2026): sin caja
/// turquesa ni círculo, el encabezado de dos niveles de la app (el porqué turquesa y el título) y los mosaicos oscuros con
/// el ícono grande a color, como adentro. BA-A: los seis en cuadrícula; BA-B: una fila que se desliza.
struct FilterDoorQuiet: View {
    enum Style: String { case grid = "BA-A", strip = "BA-B" }
    /// Cuál se ve: `-door BA-A` o `-door BA-B` al abrir la app; sin nada, la puerta de siempre (hasta que Fernando elija).
    static var chosen: Style? { UserDefaults.standard.string(forKey: "door").flatMap(Style.init(rawValue:)) }

    let style: Style
    let context: FilterContext
    let count: FilterCount?
    let open: (FilterPage?) -> Void
    var clear: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .bottom, spacing: DS.Space.s6) {
                DSSectionHead(title: Text("Búsqueda avanzada"), action: { open(nil) }, chevron: true, meta: meta, eyebrow: Text("Sin escribir nombres"))
                    .accessibilityIdentifier("browse-filters")
                if !context.filter.isEmpty {
                    DSIconButton(symbol: DS.Symbol.remove, label: "Limpiar la búsqueda avanzada", size: .regular, action: clear)
                        .accessibilityIdentifier("browse-filters-clear")
                }
            }
            switch style {
            case .grid:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: DS.Space.s2) {
                    ForEach(pages) { tile($0) }
                }
            case .strip:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(pages) { tile($0).frame(width: DS.Filter.stripTile) }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .rowEdge(.bleeds)   // los mosaicos llegan a la orilla de la pantalla al deslizar
            }
        }
    }

    /// Con filtros puestos, los que llevas van primero (encendidos).
    private var pages: [FilterPage] {
        let on = FilterPage.main.filter { FilterText.value($0, context) != nil }
        return on + FilterPage.main.filter { !on.contains($0) }
    }

    private func tile(_ page: FilterPage) -> some View {
        FilterTile(page: page, context: context) { open(page) }
            .accessibilityIdentifier("browse-filter-\(page.rawValue)")
    }

    private var meta: Text? {
        let n = context.filter.activeCount
        guard n > 0 else { return nil }
        let filters = n == 1 ? Text("1 filtro") : Text("\(n) filtros")
        guard let count else { return filters }
        return Text("\(filters) · \(ResultCountHeader.phrase(count, language: context.language)) la última vez")
    }
}
