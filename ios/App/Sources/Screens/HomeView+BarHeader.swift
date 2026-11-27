import SwiftUI

/// LD2-B (Fernando, 27 nov 2026): en la pantalla de afuera del Duo, el encabezado de Inicio va en el renglón de la hora (como
/// Buscar, Biblioteca y la ficha): iOS acomoda el logo, el control y tu foto alrededor de la hora y Inicio gana ~55 puntos de
/// alto. Solo ahí: en el iPhone normal no cambia nada («del 17 Pro no debería cambiar nada»).
extension HomeView {
    /// La pantalla baja y ancha del Duo cerrado (466 × 678): ningún iPhone normal de pie llega a esa proporción.
    static var headerInBar: Bool { WindowMetrics.shortPhone }

    /// Todo del lado izquierdo, en un solo elemento: el logo completo, el control y tu foto. Del lado derecho iOS pone la hora
    /// y la señal pegadas a la cámara (el círculo de la esquina de arriba a la derecha), así que no se les estorba. Si el
    /// control y la foto fueran del lado derecho, iOS los esconde en un botón «…» porque no caben junto a la hora.
    /// Sin nada en la TV, el control de tu Orbital vive en el encabezado (con algo reproduciéndose, en el accesorio de abajo).
    var showsRemote: Bool { openRemote != nil && (tvNow.model.now == nil || !Self.hasTabAccessory) }

    @ToolbarContentBuilder var barHeader: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { AppMark(small: true).fixedSize() }.sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: DS.Space.s2) {
                if showsRemote {
                    Button { openRemote?() } label: {
                        Image(systemName: "av.remote").font(DS.TextRecipe.section.font)
                            .padding(DS.Space.s4).contentShape(Rectangle()).padding(-DS.Space.s4)   // ds-exception: crece el toque, no el dibujo (como en HomeHeader)
                    }
                        .accessibilityLabel(Text("Control de tu Orbital")).accessibilityIdentifier("home-remote")
                }
                ProfileButton(avatar: look.avatar)
            }
            .buttonStyle(.plain).foregroundStyle(DS.text)
            .fixedSize()
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
