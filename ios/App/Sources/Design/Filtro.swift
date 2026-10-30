import SwiftUI
import OrbitalCore

// Piezas del filtro avanzado (docs/producto/muvy-busqueda-premios/prototipo-filtro.html): el mosaico de cada filtro en el
// cajón, el cuadro «Qué tan conocida» y la opción grande con ícono (formato, tiempo). Sin cápsulas de texto: íconos.

/// Un filtro en el cajón: ícono, nombre y lo que tiene elegido. Con algo elegido se enciende en turquesa (la selección).
struct FilterTile: View {
    let symbol: String
    let title: Text
    /// Lo elegido («Terror, Comedia», «Los 90»); nil: cualquiera.
    let value: Text?
    let action: () -> Void

    var body: some View {
        let on = value != nil
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Image(systemName: symbol).font(DS.TextRecipe.title.font).foregroundStyle(on ? DS.brandMoon : DS.textMuted)
                Spacer(minLength: 0)
                title.recipe(.footnote, color: DS.text).fontWeight(.semibold).lineLimit(1)
                (value ?? Text("Cualquiera")).recipe(.caption, color: on ? DS.text : DS.textMuted).lineLimit(1)
            }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: DS.Filter.tileHeight, alignment: .leading)
            .background(on ? DS.Filter.selectedFill : DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).strokeBorder(on ? DS.brandMoon : .clear, lineWidth: DS.Size.hairline * 2))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Una opción grande con ícono (Todo · Películas · Series, Corta · Normal · Larga): un mosaico que se enciende al elegirla.
struct FilterChoice: View {
    let symbol: String
    let title: Text
    var detail: Text?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s2) {
                Image(systemName: symbol).font(DS.TextRecipe.title.font).foregroundStyle(selected ? DS.brandMoon : DS.text)
                title.recipe(.footnote, color: DS.text).fontWeight(.semibold).lineLimit(1)
                if let detail { detail.recipe(.caption, color: DS.textMuted).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, minHeight: DS.Filter.choiceHeight)
            .background(selected ? DS.Filter.selectedFill : DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).strokeBorder(selected ? DS.brandMoon : .clear, lineWidth: DS.Size.hairline * 2))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// «Qué tan conocida»: el cuadro fama × calificación. Arriba lo bien calificado, a la derecha lo famoso; cada esquina es
/// una forma de buscar (Joyas ocultas, Las de siempre, Para pocos, Taquilleras). Tocar la elegida la quita.
struct FameQuadrant: View {
    let selected: AdvancedFilter.Fame
    let pick: (AdvancedFilter.Fame) -> Void

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                cell(.gems, "sparkles", Text("Joyas ocultas"), Text("Muy buenas, poco vistas"))
                cell(.classics, "crown", Text("Las de siempre"), Text("Muy buenas y famosas"))
            }
            HStack(spacing: DS.Space.s2) {
                cell(.niche, "eye.slash", Text("Para pocos"), Text("Rarezas y culto"))
                cell(.blockbusters, "ticket", Text("Taquilleras"), Text("Las que llenaron salas"))
            }
            HStack {
                Text("Menos conocida").recipe(.caption, color: DS.textMuted)
                Spacer()
                Image(systemName: "arrow.right").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).accessibilityHidden(true)
                Text("Más famosa").recipe(.caption, color: DS.textMuted)
            }
        }
    }

    private func cell(_ fame: AdvancedFilter.Fame, _ symbol: String, _ title: Text, _ detail: Text) -> some View {
        FilterChoice(symbol: symbol, title: title, detail: detail, selected: selected == fame) { pick(selected == fame ? .any : fame) }
    }
}
