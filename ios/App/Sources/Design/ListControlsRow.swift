import SwiftUI

/// El renglón de controles de una lista (R1, Guardado y Mi lista): el orden a la izquierda con su nombre; luego la pastilla de
/// tipo y los íconos (⊜, ＋, el reloj, elegir varios). Con el nombre de lo elegido en la pastilla (KT1, «Series») el renglón
/// aparta su lugar: si así no cabe a lo ancho, la pastilla baja a su propio renglón, a la derecha como arriba en vez de empujar la página
/// fuera de la pantalla (Fernando, 13 nov 2026, visto en las capturas). Se mide lo que ocupa y lo que hay, no se adivina.
struct ListControlsRow<Sort: View, Kind: View, Trailing: View>: View {
    /// Cuántos íconos aparta siempre a la derecha (las pestañas de Guardado: 3). Con pestañas que traen distintos íconos, la
    /// pastilla no brinca de lugar al cambiar de pestaña (Fernando, 13 nov 2026: «como que se mueve»). 0: lo que traiga.
    var reservedIcons = 0
    @ViewBuilder var sort: Sort
    @ViewBuilder var kind: Kind
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Cada parte en su caja (aunque venga vacía): el acomodo siempre recibe las tres.
        ControlsLayout(stack: typeSize.isAccessibilitySize) {
            VStack(spacing: 0) { sort }
            VStack(spacing: 0) { kind }
            ZStack(alignment: .trailing) {
                // El lugar de los íconos más anchos que puede traer, invisible: mide con la letra que haya.
                if reservedIcons > 0 {
                    HStack(spacing: DS.Space.s2) { ForEach(0..<reservedIcons, id: \.self) { _ in ListBarIcon(symbol: "checklist") } }
                        .hidden().accessibilityHidden(true)
                }
                HStack(spacing: DS.Space.s2) { trailing }
            }
        }
    }
}

/// Decide con el ancho que de verdad le dan (no con lo que mide de sí mismo, que crece con lo que pone): si el ícono del
/// orden, la pastilla y los íconos caben, van en un renglón; si no, la pastilla baja al suyo.
private struct ControlsLayout: Layout {
    var stack: Bool
    private let gap = DS.Space.s2
    private let sortMin = DS.Size.touchTarget

    private func fits(_ width: CGFloat, kind: CGSize, trailing: CGSize) -> Bool {
        !stack && (kind.width == 0 || sortMin + kind.width + trailing.width + gap * 2 <= width)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let kind = subviews[1].sizeThatFits(.unspecified), trailing = subviews[2].sizeThatFits(.unspecified)
        let room = max(sortMin, (width.isFinite ? width : 1000) - trailing.width - gap - (fits(width, kind: kind, trailing: trailing) ? kind.width + gap : 0))
        let sort = subviews[0].sizeThatFits(ProposedViewSize(width: room, height: nil))
        let row = max(sort.height, trailing.height, fits(width, kind: kind, trailing: trailing) ? kind.height : 0)
        let height = fits(width, kind: kind, trailing: trailing) ? row : row + (kind.height > 0 ? gap + kind.height : 0)
        return CGSize(width: width.isFinite ? width : sort.width + kind.width + trailing.width + gap * 2, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let kind = subviews[1].sizeThatFits(.unspecified), trailing = subviews[2].sizeThatFits(.unspecified)
        let inline = fits(bounds.width, kind: kind, trailing: trailing)
        let room = max(sortMin, bounds.width - trailing.width - gap - (inline ? kind.width + gap : 0))
        let sort = subviews[0].sizeThatFits(ProposedViewSize(width: room, height: nil))
        let row = max(sort.height, trailing.height, inline ? kind.height : 0)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + row / 2), anchor: .leading, proposal: ProposedViewSize(width: room, height: nil))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.minY + row / 2), anchor: .trailing, proposal: .unspecified)
        if inline {
            subviews[1].place(at: CGPoint(x: bounds.maxX - trailing.width - gap, y: bounds.minY + row / 2), anchor: .trailing, proposal: .unspecified)
        } else {
            // Del mismo lado que en el renglón: la pastilla no cruza la pantalla.
            subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.minY + row + gap), anchor: .topTrailing, proposal: .unspecified)
        }
    }
}
