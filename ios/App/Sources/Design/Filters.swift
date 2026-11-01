import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// Filtrar por tipo (series o películas) y las filas de fichas.
/// Los íconos de los tipos, los mismos en toda la app (menús, la cápsula de lo elegido, los chips de filtros, el mosaico):
/// Todo, Películas y Series. «tv» no: ese es «Ver en la TV».
enum KindGlyph {
    static let all = "square.grid.2x2", movie = "film", series = "play.rectangle.on.rectangle"
    /// "" o nil es todo, «movie» o «series».
    static func symbol(_ kind: String?) -> String {
        switch kind { case "movie": movie; case "series": series; default: all }
    }
}

/// El filtro de tipo de toda la app: Todo · Películas · Series (o solo Películas · Series), siempre el mismo control y en
/// ese orden: las pestañas de texto con su ícono (`DSTextTabs`). Antes había cinco (cápsulas, un menú, solo íconos, un
/// segmentado y pestañas); Fernando, 30 oct 2026: un solo selector en toda la app. Va debajo del título de su sección, no
/// junto. `kind`: "" es todo, «movie» o «series». `counts`: cuántas hay de cada uno (Buscar).
struct DSKindFilter: View {
    @Binding var kind: String
    var includeAll = true
    var counts: (movies: Int, series: Int)?
    /// La pastilla chica junto al título (el Top 10, Fernando, 31 oct 2026): el segmentado con su ícono en cada opción.
    var compact = false
    /// La rayita de la elegida: blanca (lo elegido) o turquesa en Inicio (Fernando, 31 oct 2026: Inicio se queda como estaba).
    var mark: Color = DS.text
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if compact {
            // La pastilla propia: la nativa de iOS no pone ícono junto al texto.
            HStack(spacing: 0) {
                ForEach(options, id: \.0) { option in
                    let on = kind == option.0
                    Button { kind = option.0 } label: {
                        HStack(spacing: DS.Space.s1) {
                            Image(systemName: KindGlyph.symbol(option.0)).symbolVariant(on ? .fill : .none)
                            // Con letra de accesibilidad solo el ícono (el nombre va para VoiceOver): con el texto la
                            // pastilla medía más que la pantalla y empujaba todo Inicio fuera de la orilla.
                            if !typeSize.isAccessibilitySize { Text(option.1).lineLimit(1) }
                        }
                        .accessibilityLabel(Text(option.1))
                        .font(DS.TextRecipe.badge.font)   // chica: el título de al lado cabe en un renglón
                        .foregroundStyle(on ? DS.text : DS.textMuted)
                        .padding(.horizontal, DS.Space.s2)
                        .frame(maxHeight: .infinity)
                        .background(on ? DS.fillStrong : .clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)   // ds-exception: un segmento del control (no un botón suelto); el fondo marca el elegido
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(DS.Space.s1 / 2)
            .frame(height: DS.Size.touchTarget)
            .background(DS.fill, in: Capsule())
            .fixedSize()
            .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
            .sensoryFeedback(.selection, trigger: kind)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Series o películas"))
        } else {
            // Un grupo con su nombre; cada pestaña conserva el suyo (sin `.contain`, VoiceOver leía las tres como «Series o
            // películas»).
            DSTextTabs(options: options.map { DSTextTabs.Option(id: $0.0, title: Text($0.1), symbol: KindGlyph.symbol($0.0)) }, selection: $kind, mark: mark)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Series o películas"))
        }
    }

    private var options: [(String, LocalizedStringKey)] {
        let movies: LocalizedStringKey = counts.map { "Películas \($0.movies)" } ?? "Películas"
        let series: LocalizedStringKey = counts.map { "Series \($0.series)" } ?? "Series"
        return (includeAll ? [("", "Todo")] : []) + [("movie", movies), ("series", series)]
    }
}

/// Pestañas de texto, la misma pieza en toda la app (Todo · Películas · Series, Semana · Mes · Año · Siempre): la elegida en
/// blanco y negrita con una rayita blanca debajo, las otras en gris; con ícono si lo traen. Sin cápsula (Fernando, 30 oct
/// 2026). Se lee sobre el arte con su sombra.
struct DSTextTabs<ID: Hashable>: View {
    struct Option { let id: ID; let title: Text; var symbol: String? = nil }
    let options: [Option]
    @Binding var selection: ID
    /// La rayita de la elegida (blanca; turquesa solo en Inicio).
    var mark: Color = DS.text

    var body: some View {
        // Si con la letra grande no caben los nombres, solo los íconos (cada uno con su nombre para VoiceOver): nunca se sale
        // de la pantalla (antes «T… Pe…» quedaba cortado por la orilla izquierda).
        ViewThatFits(in: .horizontal) {
            tabs(titles: true)
            tabs(titles: options.allSatisfy { $0.symbol == nil })
        }
        .shadow(DS.Elevation.low)
        .animation(DS.Motion.fade, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tabs(titles: Bool) -> some View {
        HStack(spacing: DS.Space.s5) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = selection == option.id
                Button { selection = option.id } label: {
                    VStack(spacing: DS.Space.s1) {
                        HStack(spacing: DS.Space.s1) {
                            if let symbol = option.symbol { Image(systemName: symbol).symbolVariant(on ? .fill : .none) }
                            if titles { option.title.lineLimit(1) }
                        }
                        .accessibilityLabel(option.title)
                        .font(DS.TextRecipe.cardTitle.font.weight(on ? .bold : .medium))   // ds-exception: la pestaña elegida se distingue por el peso
                        .foregroundStyle(on ? DS.text : DS.textMuted)
                        Capsule().fill(on ? mark : .clear).frame(width: DS.Filter.tabMark, height: DS.Filter.tabMarkHeight)
                    }
                    .padding(.vertical, DS.Space.s1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
