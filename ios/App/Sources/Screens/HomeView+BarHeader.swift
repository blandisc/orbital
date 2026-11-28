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

    var kindBinding: Binding<String> {
        Binding(get: { home.model.spotlightKind ?? "" }, set: { home.model.spotlightKind = $0.isEmpty ? nil : $0 })
    }

    @ToolbarContentBuilder var barHeader: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { AppMark(small: true).fixedSize() }.sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: DS.Space.s2) {   // con más aire ya no cabe junto a la hora: iOS manda el renglón a «…» (probado)
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

    /// HB1-B (Fernando, 27 nov 2026: «vamos con el filtro en la portada»): el filtro de Inicio va recogido (solo lo que ves) en
    /// la esquina de arriba de la portada, a la misma distancia de la orilla que el texto de la portada. Se abre hacia la
    /// izquierda con los tres. Primero en el Duo (no cabía en el renglón de la hora); desde la misma noche en todo iPhone
    /// (Fernando: «que sea lo más posible la misma aplicación… para reducir mantenimiento»). En el iPad y la Mac sigue arriba.
    static var kindOnHero: Bool { headerInBar || ThisDevice.isPhone }

    @ViewBuilder var heroKind: some View {
        if Self.kindOnHero {
            DSKindFilter(kind: kindBinding, menu: true, open: $heroKindOpen).accessibilityIdentifier("home-kind-filter")
                // A la misma distancia de la orilla que el texto de la portada: en claro es tarjeta (su orilla + su margen); en
                // oscuro el arte llega a la orilla (solo el margen).
                .padding(.top, DS.Space.gutter).padding(.trailing, scheme == .dark ? DS.Space.gutter : DS.Space.gutter * 2)
        }
    }
}
