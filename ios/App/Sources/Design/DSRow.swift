import SwiftUI

// SD2-A (Fernando, 26 nov 2026): una sola fila para toda la app. Antes cada pantalla armaba la suya (Ajustes, «Guardar en…»,
// versiones, subtítulos, control) con su propio ícono, aire y alto; ahora todas salen de aquí y miden igual.
// `DesignTests.testNoNewRowsCardsOrSheetsOutsideTheCatalog` impide crear otra.

/// Lo de la izquierda de cualquier fila: el ícono en su color (en su columna, para que los nombres queden alineados), el nombre
/// y, debajo, el detalle en gris. Es el `label` de los renglones de lista del sistema (Ajustes, menús, interruptores).
struct DSRowLabel: View {
    let title: Text
    var detail: Text?
    var symbol: String?
    /// `symbol` es un símbolo propio del catálogo de la app (la dona de Los Simpson), no uno del sistema.
    var custom = false
    var tint: Color = DS.textMuted

    var body: some View {
        if let symbol {
            Label { name } icon: {
                (custom ? Image(symbol) : Image(systemName: symbol)).font(DS.TextRecipe.cardTitle.font).foregroundStyle(tint)
                    .frame(width: DS.SettingsLook.rowIcon)
            }
        } else { name }
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 0) {   // como el subtítulo de un renglón del sistema
            title.foregroundStyle(DS.text)
            if let detail { detail.recipe(.footnote, color: DS.textMuted) }
        }
    }
}

/// Una fila que se toca por sí sola (fuera de una lista del sistema): su ícono, el nombre y, a la derecha, lo que dice cómo
/// está (palomita, flecha). Todo el renglón se toca y nunca mide menos que un objetivo táctil.
struct DSRow: View {
    enum Accessory: Equatable { case none, chevron, check(Bool) }

    let title: Text
    var detail: Text?
    var symbol: String?
    var tint: Color = DS.textMuted
    var accessory: Accessory = .none
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                if let symbol { PanelIcon(symbol: symbol, color: tint) }
                VStack(alignment: .leading, spacing: 0) {
                    title.recipe(.labelLarge, color: DS.text).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)   // con letra grande no se corta
                    if let detail { detail.recipe(.footnote, color: DS.textMuted).lineLimit(2) }
                }
                Spacer(minLength: DS.Space.s2)
                trailing
            }
            .padding(DS.Space.s2)
            .frame(minHeight: DS.Size.touchTarget)
            .dsCard(.row, translucent: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .dsFeedback(.selection, trigger: checked)
    }

    private var checked: Bool { if case .check(true) = accessory { true } else { false } }

    @ViewBuilder private var trailing: some View {
        switch accessory {
        case .none: EmptyView()
        case .chevron: Image(systemName: "chevron.right").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textFaint)
        case .check(let on):
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(DS.TextRecipe.title.font.weight(DS.Weight.plain))   // la casilla del sistema va en peso regular, como en Ajustes de iOS
                .foregroundStyle(on ? DS.accent : DS.textFaint)
                .contentTransition(.symbolEffect(.replace))
        }
    }
}
