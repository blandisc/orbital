import SwiftUI
import OrbitalCore
import OrbitalModels

/// Una columna de filas: perezosa (solo arma lo que se ve) o, para comparar en las pruebas, toda de una vez.
struct ShelfStack<Content: View>: View {
    let lazy: Bool
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    var body: some View {
        if lazy { LazyVStack(alignment: .leading, spacing: spacing, content: content) }
        else { VStack(alignment: .leading, spacing: spacing, content: content) }
    }
}

/// Qué sección cruza la parte de arriba de Explorar (la escribe `SectionSpy`, la lee solo `SectionMenu`).
@Observable @MainActor final class SectionTracker {
    var active: CollectionSection = .forYou
}

/// Ir a una sección: cada una con su ícono; la que ves, con la palomita (`DS.Symbol.current`) al lado.
struct SectionMenu: View {
    let tracker: SectionTracker
    let sections: [CollectionSection]
    let pick: (CollectionSection) -> Void

    var body: some View {
        Menu {
            ForEach(sections, id: \.self) { section in
                Button { pick(section) } label: {
                    Label { tracker.active == section ? Text("\(section.title)  \(Image(systemName: DS.Symbol.current))") : section.title } icon: { Image(systemName: section.symbol) }
                }
            }
        } label: {
            // OI-1: responde en 44 × 44 (en la Mac solo respondía el dibujo, 22 × 13; un menú no crece con el aire de fuera).
            Image(systemName: "list.bullet.indent")
                .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Ir a una sección"))
        .accessibilityIdentifier("paraTi-sections")
    }
}
