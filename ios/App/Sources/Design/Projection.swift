import SwiftUI

// Piezas de Proyección (el sistema visual del iPhone; ver docs/ios-interfaz.md y el canvas de diseño).
// Todas se arman con tokens (`DS.*`) y recetas de texto (`DS.TextRecipe`); las pantallas solo las componen.

extension Text {
    /// Aplica una receta de texto con su color por omisión.
    func recipe(_ recipe: DS.TextRecipe, color: Color? = nil) -> some View {
        font(recipe.font).foregroundStyle(color ?? recipe.defaultColor)
    }
}

extension DS.TextRecipe {
    var defaultColor: Color {
        switch self {
        case .section, .cardTitle, .body: DS.text
        case .secondary, .footnote, .eyebrow, .data: DS.textMuted
        }
    }
}

/// Una línea de datos en SF Mono (la marca tipográfica de la app): «T2 · E5 · quedan 20 min · terminas a las 23:21».
/// Si no cabe completa, quita partes del final antes de cortar un número.
struct DataLine: View {
    let parts: [String]
    var color: Color?

    var body: some View {
        let shown = parts.filter { !$0.isEmpty }
        ViewThatFits(in: .horizontal) {
            ForEach(Array((1...max(1, shown.count)).reversed()), id: \.self) { count in
                Text(verbatim: shown.prefix(count).joined(separator: " · ")).recipe(.data, color: color).lineLimit(1)
            }
        }
    }
}

/// El rótulo pequeño sobre un título («Seguir viendo», «N.º 2 en Netflix esta semana»). Con `accent`, en el color de acento.
struct Eyebrow: View {
    let text: Text
    var accent = false
    /// Sobre el arte: más claro que el secundario de siempre.
    var onArt = false

    var body: some View { text.recipe(.eyebrow, color: accent ? DS.accent : onArt ? DS.onArtSecondary : nil).lineLimit(1) }
}

/// Una acción de la rejilla de acciones de la ficha.
struct ProjectionAction: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let symbol: String
    var active = false
    var disabled = false
    let action: () -> Void
}

/// Las acciones secundarias de una ficha (Mi lista, Descargar, Fuentes…): botones nativos con relleno del sistema, del mismo
/// ancho, con ícono arriba y nombre abajo. Con letra de accesibilidad se apilan en renglones.
struct ActionGrid: View {
    let actions: [ProjectionAction]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: DS.Space.s2)) : AnyLayout(HStackLayout(spacing: DS.Space.s2))
        layout {
            ForEach(actions) { item in
                Button(action: item.action) {
                    VStack(spacing: DS.Space.s1) {
                        Image(systemName: item.symbol).font(DS.TextRecipe.cardTitle.font).symbolVariant(item.active ? .fill : .none)
                        Text(item.title).font(DS.TextRecipe.footnote.font).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                    .padding(.vertical, DS.Space.s2)
                }
                .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: DS.Radius.lg))
                .tint(item.active ? DS.accent : DS.text)
                .disabled(item.disabled)
                .sensoryFeedback(.selection, trigger: item.active)
            }
        }
    }
}

/// Una pieza ancha 16:9 de un riel (lo que tenías a medias, episodios nuevos): el arte con su avance y, debajo, el nombre y
/// una línea de datos.
struct StillCard: View {
    let title: String
    let art: String?
    var data: [String] = []
    var progress: Double?
    var width: CGFloat = DS.Poster.stillWidth

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ZStack(alignment: .bottom) {
                PosterView(url: art, title: title, aspect: DS.Poster.stillAspect)
                if let progress { DSProgress(fraction: progress).padding(.horizontal, DS.Space.s2).padding(.bottom, DS.Space.s2) }
            }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).recipe(.cardTitle).lineLimit(1)
                if !data.isEmpty { DataLine(parts: data) }
            }
        }
        .frame(width: width)
        .accessibilityElement(children: .combine)
    }
}

/// Los puntos de un carrusel (el nativo de las páginas de iOS, en pequeño): dónde estás y cuántas hay.
struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: DS.Space.s2) {
                ForEach(0..<count, id: \.self) { i in
                    Circle().fill(i == index ? DS.text : DS.fillStrong).frame(width: DS.Size.pageDot, height: DS.Size.pageDot)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(index + 1) de \(count)"))
        }
    }
}

/// Elegir una opción de muchas (temporadas): el menú nativo, con la opción actual y su chevron, en un botón con relleno del sistema.
struct DSOptionMenu<Item: Hashable & Identifiable>: View {
    let items: [Item]
    let label: (Item) -> Text
    @Binding var selection: Item

    var body: some View {
        Menu {
            Picker(selection: $selection) { ForEach(items) { label($0).tag($0) } } label: { EmptyView() }
        } label: {
            HStack(spacing: DS.Space.s2) {
                label(selection).recipe(.cardTitle)
                Image(systemName: "chevron.up.chevron.down").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted)
            }
            .frame(minHeight: DS.Size.touchTarget)
        }
        .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(DS.text)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Un renglón con su puesto (lo más popular, la cartelera de una plataforma): el número en SF Mono, el póster chico, el nombre
/// y un dato; a la derecha, opcional, cuánto subió o bajó.
struct RankedRow: View {
    let rank: Int
    let title: String
    let poster: String?
    var detail: Text?
    /// Cuántos lugares subió (positivo) o bajó (negativo); nil si no se sabe, 0 si es nuevo en la lista.
    var movement: Int?

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Text(verbatim: "\(rank)").recipe(.data).frame(minWidth: DS.Space.s5, alignment: .leading)
            PosterView(url: poster, title: title).frame(width: DS.Poster.rowWidth)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).recipe(.body).lineLimit(1)
                if let detail { detail.recipe(.footnote).lineLimit(1) }
            }
            Spacer(minLength: DS.Space.s2)
            if let movement { MovementBadge(movement: movement) }
        }
        .frame(minHeight: DS.Size.touchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// ▲ 2 · ▼ 1 · Nuevo: cuánto se movió un título en su lista (el acento solo cuando sube).
struct MovementBadge: View {
    let movement: Int

    var body: some View {
        Group {
            if movement == 0 { Text("Nuevo").recipe(.eyebrow, color: DS.accent) }
            else if movement > 0 { Label { Text(verbatim: "\(movement)") } icon: { Image(systemName: "arrowtriangle.up.fill") }.recipe(.data, color: DS.accent) }
            else { Label { Text(verbatim: "\(-movement)") } icon: { Image(systemName: "arrowtriangle.down.fill") }.recipe(.data) }
        }
        .labelStyle(.titleAndIcon)
    }
}

extension Label where Title == Text, Icon == Image {
    func recipe(_ recipe: DS.TextRecipe, color: Color? = nil) -> some View {
        font(recipe.font).foregroundStyle(color ?? recipe.defaultColor)
    }
}

/// Un mosaico con arte y un nombre encima (géneros de Explora): el arte se tiñe de oscuro abajo para que el nombre se lea.
struct ArtTile: View {
    let title: Text
    let art: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterView(url: art, title: "", aspect: nil, bleed: true, maxPoints: DS.Image.card)
                .overlay(LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .top, endPoint: .bottom))
            title.recipe(.cardTitle).padding(DS.Space.s3).onArt()
        }
        .frame(height: DS.Size.artTileHeight)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
