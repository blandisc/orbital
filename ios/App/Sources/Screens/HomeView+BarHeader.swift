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

    /// HB1 (en prueba, 27 nov 2026): dónde van el filtro de Inicio y Ajustes en el Duo. «a»: tu foto abre un menú con el filtro
    /// y Ajustes; «b»: el filtro en la esquina de la portada. Sin bandera, como hoy (sin filtro en el Duo).
    static var hb: String {
        #if DEBUG
        Demo.isOn ? Demo.value(after: "-demo-hb") ?? "" : ""
        #else
        ""
        #endif
    }

    var kindBinding: Binding<String> {
        Binding(get: { home.model.spotlightKind ?? "" }, set: { home.model.spotlightKind = $0.isEmpty ? nil : $0 })
    }

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
                if Self.hb == "a" { profileMenu } else { ProfileButton(avatar: look.avatar) }
            }
            .buttonStyle(.plain).foregroundStyle(DS.text)
            .fixedSize()
        }
        .sharedBackgroundVisibility(.hidden)
    }

    /// HB1-A: tu foto abre un panelito: arriba, qué ver en Inicio (el filtro de siempre); abajo, Ajustes. Con un `Menu` de iOS
    /// el renglón entero se iba a «…» (probado 27 nov 2026); con un botón y su globo, no.
    private var profileMenu: some View {
        HomeProfilePopover(kind: kindBinding, avatar: look.avatar)
    }

    /// HB1-B: el filtro de siempre (`DSKindFilter`, recogido: solo lo que ves) en la esquina de la portada.
    @ViewBuilder var heroKind: some View {
        if Self.headerInBar && Self.hb == "b" {
            DSKindFilter(kind: kindBinding, menu: true, open: $heroKindOpen).accessibilityIdentifier("home-kind-filter")
                .padding(.top, DS.Space.s4).padding(.trailing, DS.Space.gutter + DS.Space.s4)
        }
    }
}

/// HB1-A (en prueba): tu foto en Inicio del Duo; al tocarla, un globo con el filtro de Inicio y Ajustes.
struct HomeProfilePopover: View {
    @Binding var kind: String
    let avatar: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            AvatarImage(id: avatar)
                .overlay(alignment: .bottomTrailing) {
                    // Con un filtro puesto, su ícono chiquito sobre tu foto: se sabe que Inicio está filtrado.
                    if !kind.isEmpty {
                        Image(systemName: KindGlyph.symbol(kind)).symbolVariant(KindGlyph.variant)
                            .font(DS.TextRecipe.badge.font).foregroundStyle(DS.bg)
                            .padding(DS.Space.s1).background(DS.text, in: Circle())
                            .offset(x: DS.Space.s1, y: DS.Space.s1)
                    }
                }
        }
        .accessibilityLabel(Text("Tu perfil: qué ver en Inicio y Ajustes"))
        .accessibilityIdentifier("home-profile-menu")
        .popover(isPresented: $open) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text("Qué ver en Inicio").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
                DSKindFilter(kind: $kind)
                Divider()
                Button {
                    open = false
                    AppEnvironment.shared.ui.openSettings = true
                } label: {
                    Label("Ajustes", systemImage: "gearshape").font(DS.TextRecipe.body.font)
                        .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(DS.text)
                .accessibilityIdentifier("home-profile-settings")
            }
            .padding(DS.Space.s6)
            .presentationCompactAdaptation(.popover)
        }
    }
}
