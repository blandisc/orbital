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
/// ese orden (antes había cinco: cápsulas, un menú, pestañas grandes, un segmentado y un botón en la barra).
/// `kind`: "" es todo, «movie» o «series». `counts`: cuántas hay de cada uno (Buscar).
struct DSKindFilter: View {
    @Binding var kind: String
    var includeAll = true
    var counts: (movies: Int, series: Int)?
    /// Chico, a la derecha del título de su sección: el switch en cápsula (dos opciones, como el Top 10).
    var compact = false
    /// Una lista que se despliega (tres opciones no caben junto al título): la cápsula con lo elegido y ⌄, como «Ver todo».
    var menu = false
    /// En la barra de arriba (Inicio): solo los tres íconos, sin texto; cada uno dice su nombre a VoiceOver.
    var icons = false

    var body: some View {
        Group {
            if icons {
                Picker(selection: $kind) {
                    ForEach(options, id: \.0) { Image(systemName: KindGlyph.symbol($0.0)).accessibilityLabel(Text($0.1)).tag($0.0) }
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                .fixedSize()
                .sensoryFeedback(.selection, trigger: kind)
            } else if menu {
                Menu {
                    Picker(selection: $kind) { ForEach(options, id: \.0) { Label($0.1, systemImage: KindGlyph.symbol($0.0)).tag($0.0) } } label: { EmptyView() }
                } label: {
                    DSCapsuleLabel(title: Text(options.first { $0.0 == kind }?.1 ?? "Todo"), symbol: KindGlyph.symbol(kind), trailing: "chevron.down")
                }
                .fixedSize()
                .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
                .sensoryFeedback(.selection, trigger: kind)
            } else if compact {
                // El switch chico del Top 10 (cápsula con lo elegido resaltado), a la derecha del título de su sección.
                DSSegmented(options: options, selection: $kind).fixedSize()
                    .frame(minHeight: DS.Size.touchTarget)   // el mismo renglón que las cápsulas («Ver todo», «Todo ⌄»)
                    .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
            } else {
                DSSegmented(options: options, selection: $kind)
            }
        }
        .accessibilityLabel(Text("Series o películas"))
        .accessibilityIdentifier("kind-filter")
    }

    private var options: [(String, LocalizedStringKey)] {
        let movies: LocalizedStringKey = counts.map { "Películas \($0.movies)" } ?? "Películas"
        let series: LocalizedStringKey = counts.map { "Series \($0.series)" } ?? "Series"
        return (includeAll ? [("", "Todo")] : []) + [("movie", movies), ("series", series)]
    }
}

/// Filtros deslizables (Todo · Trakt · Netflix…): botones nativos en cápsula; el elegido va resaltado.
struct DSChipRow<Item: Hashable & Identifiable, Label: View>: View {
    let items: [Item]
    let label: (Item) -> Label
    @Binding var selection: Item
    /// El valor actual como dato de la vista (ver `DSSegmented`).
    private let current: Item
    /// Hasta dónde está deslizada la tira: el elegido queda a la vista (la temporada 7 de 9 no se esconde a la derecha).
    @State private var scrolled: Item.ID?

    init(items: [Item], @ViewBuilder label: @escaping (Item) -> Label, selection: Binding<Item>) {
        self.items = items; self.label = label; _selection = selection; current = selection.wrappedValue
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(items) { item in
                    Group {
                        if current == item { Button { selection = item } label: { label(item).lineLimit(1) }.buttonStyle(.borderedProminent).foregroundStyle(DS.onPrimary) }
                        else { Button { selection = item } label: { label(item).lineLimit(1) }.buttonStyle(.bordered) }
                    }
                    .buttonBorderShape(.capsule).controlSize(.small)
                    .accessibilityAddTraits(current == item ? .isSelected : [])
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, DS.Space.gutter)
        }
        .scrollPosition(id: $scrolled, anchor: .center)
        .onChange(of: current.id, initial: true) { _, id in scrolled = id }
        .sensoryFeedback(.selection, trigger: current)
    }
}
