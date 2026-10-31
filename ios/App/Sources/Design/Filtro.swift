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

/// La puerta del filtro avanzado arriba de Buscar (Fernando, 30 oct 2026, opción B1): la tarjeta de siempre con su nombre
/// (y lo que ya elegiste, en turquesa) y una fila de filtros con íconos de línea en blanco que se desliza. Tocar uno abre el
/// cajón justo en ese filtro; tocar arriba, el cajón completo.
struct FilterDoor: View {
    struct Option: Identifiable {
        let id: String
        let symbol: String
        let title: Text
    }
    let options: [Option]
    let active: Int
    let summary: Text?
    /// nil: el cajón completo; si no, el id de la opción tocada.
    let open: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Button { open(nil) } label: {
                HStack(spacing: DS.Space.s2) {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text("Búsqueda avanzada").recipe(.cardTitle)
                        if active > 0, let summary {
                            // Lo elegido, en el color de la selección del filtro (el turquesa es solo para los porqués).
                            Text("\(active) \(active == 1 ? "filtro" : "filtros") · \(summary)").recipe(.footnote, color: DS.brandMoon).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("browse-filters")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(options) { option in
                        Button { open(option.id) } label: {
                            Label { option.title } icon: { Image(systemName: option.symbol) }
                                .font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.text)
                                .padding(.horizontal, DS.Space.s3).frame(minHeight: DS.Size.touchTarget)
                                .background(DS.fill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("browse-filter-\(option.id)")
                    }
                }
            }
            .scrollClipDisabled()
        }
        .padding(DS.Space.s4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }
}

/// Un filtro puesto, arriba de los resultados: su nombre y una ✕ que lo quita ahí mismo.
struct ActiveFilterChip: View {
    let title: Text
    let remove: () -> Void
    var body: some View {
        Button(action: remove) {
            HStack(spacing: DS.Space.s1) {
                title.recipe(.footnote, color: DS.text).fontWeight(.semibold).lineLimit(1)
                Image(systemName: "xmark").font(DS.TextRecipe.caption.font.weight(.bold)).foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.Space.s3).frame(minHeight: DS.Size.touchTarget)
            .background(DS.Filter.selectedFill, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.brandMoon, lineWidth: DS.Size.hairline * 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Quitar \(title)"))
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
