import SwiftUI
import OrbitalModels

/// El encabezado de Inicio (HE1-B, Fernando, 4 nov 2026): el logo, la cápsula del control y tu foto, y «Todo ·
/// Películas · Series» (desde EH1, 9 nov, en un solo renglón con «Todo ▾»).
/// Sin historias (Fernando, 18 nov 2026: «quitarlo de las historias que tenemos arriba… solamente vamos a dejar una sección
/// de how to en ajustes»): «Aprende» vive solo en Ajustes; antes tu foto llevaba un anillo y al deslizar entraban los círculos.
/// I9 (revisión del 10 nov): la dona de «Un Simpson al azar» se fue del encabezado (eran seis cosas): vive junto a Canales.
struct HomeHeader: View {
    @Binding var kind: String
    let collapsed: Bool
    let showsRemote: Bool
    let remote: () -> Void
    let avatar: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kindOpen = false

    var body: some View {
        standard
            .frame(maxWidth: .infinity)
            .animation(DS.Motion.smooth(reduceMotion), value: collapsed)
    }

    /// Lo de siempre en un renglón (EH1, Fernando, 9 nov): el logo, «Todo ▾» y la cápsula (el control y tu foto).
    private var standard: some View {
        // Sin aire de la pila alrededor del espacio flexible (antes 8 + 8 + 8): abierto, el renglón no cabía en un iPhone
        // grande y se ensanchaba de golpe, el logo brincaba a la izquierda y la cápsula se salía de su margen («rebota de
        // inmediato en los botones de arriba a la derecha», Fernando, 13 nov 2026). Cerrado se ve igual que antes.
        HStack(spacing: 0) {
            AppMark(small: true)   // un poco más chico: así caben «Todo ▾» y la cápsula
            if TopRow.tabsInLogoRow {
                // La Mac (RN2) y el iPad con espacio (C1): «Buscar» junto al logo y las pestañas al centro (abajo, en `overlay`); en una ventana angosta las
                // dos van aquí, solo con íconos. «Todo ▾» pasa a la derecha, junto a tu foto.
                MacSearchChip(compact: !MacTabStrip.centered).padding(.leading, DS.Space.s6)
                if !MacTabStrip.centered { MacTabStrip(compact: true).padding(.leading, DS.Space.s2) }
                Spacer(minLength: DS.Space.s2)
                DSKindFilter(kind: $kind, menu: true, open: $kindOpen).accessibilityIdentifier("home-kind-filter")
                    .padding(.trailing, DS.Space.s4)
            } else {
                // En el iPhone el filtro va en la portada (`HomeView.kindOnHero`); aquí, solo en el iPad en ventana angosta.
                if !HomeView.kindOnHero {
                    DSKindFilter(kind: $kind, menu: true, open: $kindOpen).accessibilityIdentifier("home-kind-filter")
                        .padding(.leading, DS.Space.s2)
                }
                Spacer(minLength: DS.Space.s2)
            }
            // SX1: mientras eliges, la cápsula cede su lugar ANTES de que la pastilla lo necesite (`fold`, más rápido que el
            // `grow` de la pastilla) hasta quedar solo tu foto, apagada; tocarla cierra. Al cerrar regresa un instante después
            // de que la pastilla se recogió: nunca se enciman. En un iPhone chico (SE) ni tu foto cabe junto al selector
            // abierto: se va del todo y regresa al elegir.
            if !(kindOpen && WindowMetrics.column.width < DS.KindPill.narrowScreen) {
            capsule
                // Lo apagado siempre con un fundido; el lugar que cede, con `fold` (con «Reducir movimiento», de una vez, igual
                // que la pastilla: si una se acomoda al instante y la otra despacio, se enciman).
                .animation(DS.Motion.fade) { $0.opacity(kindOpen ? DS.Opacity.dimmed : 1) }
                .animation(DS.Motion.fold(reduceMotion)?.delay(kindOpen ? 0 : DS.KindPill.returnDelay), value: kindOpen)
                .allowsHitTesting(!kindOpen)
                .overlay { if kindOpen { Color.clear.contentShape(Rectangle()).onTapGesture { withAnimation(DS.Motion.fold(reduceMotion)) { kindOpen = false } } } }
                .transition(yielding)
            }
        }
        // RN2: en la Mac las pestañas en su cápsula, al centro del renglón (como la tele).
        .overlay { if TopRow.tabsInLogoRow && MacTabStrip.centered { MacTabStrip() } }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.bottom, DS.Space.s1)
        .dsChromeType()   // regla «Las barras fijas no se salen con letra grande»
        // Nunca más ancho que su lugar (si no, toda Inicio se recorre). Antes topaba con el ancho de la ventana, y en el iPad
        // acostado con el control abierto (que encoge Inicio) el encabezado era más ancho que su columna y empujaba todo
        // fuera de la pantalla: «bital», «iendo» (revisión 2 del 11 nov).
        .containerRelativeFrame(.horizontal)   // ds-exception: en la barra de arriba (safeAreaBar) el panel no cuenta: probado con el control abierto
    }

    /// La cápsula entera, en el SE: se va hacia su orilla al abrir el selector (rápido, cediendo el lugar) y regresa cuando la
    /// pastilla ya se recogió. Con «Reducir movimiento» se va de una vez (la pastilla también crece de una vez) y regresa
    /// con un fundido.
    private var yielding: AnyTransition {
        guard let fold = DS.Motion.fold(reduceMotion) else { return .asymmetric(insertion: .opacity.animation(DS.Motion.fade), removal: .identity) }
        let shrink = AnyTransition.scale(scale: DS.KindPill.enterScale, anchor: .trailing).combined(with: .opacity)
        return .asymmetric(insertion: shrink.animation(fold.delay(DS.KindPill.returnDelay)), removal: shrink.animation(fold))
    }

    /// El aire a la izquierda de la cápsula: con el control, el suyo; con tu foto sola, el mismo que a la derecha.
    static func leadingAir(remote: Bool) -> CGFloat { remote ? DS.Space.s4 : DS.Space.s1 }

    /// La cápsula: el control y tu foto (se hace a un lado mientras eliges en el selector, SX1).
    private var capsule: some View {
        HStack(spacing: 0) {
            if showsRemote {
                // Mientras eliges, el control se pliega con la cápsula (su ancho y su aire bajan a cero al mismo paso): antes
                // se quitaba y, apagándose, quedaba un instante encima de tu foto.
                // OI-1: el aire de la cápsula alrededor del ícono también es el botón (sin mover el dibujo), para atinarle con el dedo.
                Button(action: remote) {
                    Image(systemName: "av.remote").font(DS.TextRecipe.section.font)   // como el menú de Explorar en su cápsula: cabe con aire (23 nov 2026)
                        .padding(DS.Space.s4).contentShape(Rectangle()).padding(-DS.Space.s4)   // ds-exception: crece el toque, no el dibujo
                }
                    .accessibilityLabel(Text("Control de tu Orbital")).accessibilityIdentifier("home-remote")
                    .opacity(kindOpen ? 0 : 1)
                    .frame(width: kindOpen ? 0 : nil, alignment: .leading)
                    .clipped()
                    .padding(.trailing, kindOpen ? 0 : DS.Space.s6)   // aire entre el control y tu foto, como el menú y tu foto en Explorar (23 nov 2026)
                    .accessibilityHidden(kindOpen)
            }
            ProfileButton(avatar: avatar)
        }
        .buttonStyle(.plain).foregroundStyle(DS.text)
        // El control con aire a su izquierda; tu foto, a la misma distancia de la orilla que de arriba. Sola (la TV reproduce y el
        // control vive abajo, o mientras eliges), el mismo aire a los dos lados: antes sobraba a la izquierda (Fernando, 25 nov 2026).
        .padding(.leading, Self.leadingAir(remote: showsRemote && !kindOpen)).padding(.trailing, DS.Space.s1)
        .frame(height: DS.Size.touchTarget)   // SZ1: del alto de los demás selectores (44), no más
        .macTopGlass(Capsule())   // el vidrio del renglón de arriba, como las pestañas y «Buscar» (en el iPhone, el de siempre)
    }
}
