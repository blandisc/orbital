import SwiftUI
import OrbitalModels

/// Las pestañas de Biblioteca › Guardado (GD2, Fernando, 13 nov 2026: «Pestañas, como la tele»; reemplaza el tablero G2-A):
/// cada una con su ícono, su cifra y su nombre, como las pestañas con cifra de la TV («Mi lista · 8 · Viendo · 3…»). Al tocar
/// una, lo suyo ya está a la vista: no hay un índice antes de ver un póster. La elegida en blanco con la rayita debajo (la misma
/// de `DSTextTabs`), las demás en gris; la rayita viaja con `DS.Motion.fold` (sin rebote). Los íconos son todos rellenos (los
/// del estado de un título) y no cambian al elegir.
///
/// Si no caben (iPhone SE con letra grande), ceden primero los nombres de las no elegidas, luego todos los nombres; el ícono y la
/// cifra no se van nunca (VoiceOver siempre lee «Mi lista, 11»).
struct DSCountTabs<ID: Hashable>: View {
    struct Option {
        let id: ID
        let title: Text
        let symbol: String
        /// nil mientras llega (sale «–», del mismo ancho: la fila no brinca).
        let count: Int?
        let identifier: String
    }
    let options: [Option]
    @Binding var selection: ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var mark

    private enum Names { case all, chosen, none }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(.all)
            row(.all, spacing: DS.Space.s3)   // antes de soltar nombres, más juntas (como `DSTextTabs`)
            row(.chosen, spacing: DS.Space.s3)
            row(.none, spacing: DS.Space.s3)
        }
        .dsFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
    }

    /// Al ras del margen y a su ancho (en el iPad no se reparten por toda la ventana).
    private func row(_ names: Names, spacing: CGFloat = DS.Space.s5) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in tab(option, names: names) }
        }
        .padding(.horizontal, DS.Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tab(_ option: Option, names: Names) -> some View {
        let on = option.id == selection
        let named = names == .all || (names == .chosen && on)
        return Button { withAnimation(DS.Motion.fold(reduceMotion)) { selection = option.id } } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .center, spacing: DS.Space.s1) {
                    Image(systemName: option.symbol).imageScale(.small).accessibilityHidden(true)
                    Group { if let count = option.count { Text(count, format: .number) } else { Text(verbatim: "–") } }
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(DS.TextRecipe.cardTitle.font)
                if named {
                    // El peso no cambia el ancho: la gruesa escondida guarda el lugar (como `DSTextTabs`).
                    ZStack(alignment: .leading) {
                        option.title.fontWeight(.bold).hidden()   // ds-exception: la elegida se distingue por el peso
                        option.title.fontWeight(on ? .bold : .medium)   // ds-exception: la elegida se distingue por el peso
                    }
                    .font(DS.TextRecipe.footnote.font).lineLimit(1)
                }
                ZStack {
                    if on {
                        Capsule().fill(DS.text)
                            .matchedGeometryEffect(id: "mark", in: mark)
                    }
                }
                .frame(width: DS.Filter.tabMark, height: DS.Filter.tabMarkHeight)
            }
            .foregroundStyle(on ? DS.text : DS.textMuted)
            .padding(.vertical, DS.Space.s1)
            .frame(minHeight: DS.Size.touchTarget)
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue(option.count.map { Text("\($0) títulos") } ?? Text(verbatim: ""))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(option.identifier)
    }
}

/// Una lista en el mosaico de «Listas» (GD2): su portada con sus primeros cuatro pósters (2 × 2; con menos, el primero entero,
/// y sin ninguno, su ícono sobre el relleno: nunca un hueco), el nombre en hasta dos renglones (se parte entre palabras, no a
/// la mitad de una) y qué es o cuántos tiene. Toca y abre la misma pantalla de lista de siempre.
struct SavedListTile: View {
    let name: Text
    let detail: Text
    let posters: [String]
    /// El ícono de la portada vacía (y la marca de Favoritos).
    var symbol = "rectangle.portrait.on.rectangle.portrait.fill"

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            SavedCover(posters: posters, symbol: symbol)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                name.recipe(.cardTitle).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                detail.recipe(.footnote, color: DS.textMuted).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// «Nueva lista» como un mosaico más (GD2): la misma portada con un solo «+» y su nombre. El único «+» de la pestaña. Sin
/// internet se ve apagada y dice por qué (antes, gris sin explicar).
struct SavedNewListTile: View {
    var online = true
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            SavedCover(posters: [], symbol: "plus")
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Nueva lista").recipe(.cardTitle, color: DS.accent).lineLimit(2)
                (online ? Text("Nace «Solo tú»") : Text("Necesita internet")).recipe(.footnote, color: DS.textMuted).lineLimit(2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// La portada de una lista: un cuadro con 2 × 2 pósters, dos lado a lado, uno entero o el ícono.
private struct SavedCover: View {
    let posters: [String]
    let symbol: String

    var body: some View {
        Color.clear
            .aspectRatio(DS.Saved.coverAspect, contentMode: .fit)
            .overlay {
                if posters.count >= DS.Saved.coverPosters {
                    Grid(horizontalSpacing: DS.Size.hairline, verticalSpacing: DS.Size.hairline) {
                        GridRow { cell(0); cell(1) }
                        GridRow { cell(2); cell(3) }
                    }
                } else if posters.count >= 2 {
                    HStack(spacing: DS.Size.hairline) { cell(0); cell(1) }   // dos, lado a lado: llenan el cuadro sin franjas
                } else if let first = posters.first {
                    PosterView(url: first, title: "", aspect: nil, bleed: true)
                } else {
                    Image(systemName: symbol).font(DS.TextRecipe.section.font).foregroundStyle(DS.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .dsCard(.card, translucent: true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(DS.hairline))   // el borde de un póster
            .accessibilityHidden(true)
    }

    private func cell(_ i: Int) -> some View {
        PosterView(url: posters[i], title: "", aspect: nil, bleed: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}
