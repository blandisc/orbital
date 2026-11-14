import SwiftUI
import OrbitalModels

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
