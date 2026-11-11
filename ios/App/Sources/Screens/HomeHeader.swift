import SwiftUI
import OrbitalModels

/// El encabezado de Inicio (HE1-B, Fernando, 4 nov 2026): el logo, la cápsula del control y tu foto, y «Todo ·
/// Películas · Series» (desde EH1, 9 nov, en un solo renglón con «Todo ▾»). Si hay historias de «Aprende» sin ver, tu foto
/// lleva un anillo turquesa y tocarla las abre. Al deslizar a la izquierda todo sigue a tu dedo: lo de siempre se aleja y se
/// apaga, y las historias entran ocupando el encabezado entero; al soltar, se acomoda con un resorte. Deslizar a la derecha o
/// la ✕ lo regresa. Al bajar, los círculos se achican en su mismo lugar y su nombre se va. Con «Reducir movimiento», fundido.
/// I9 (revisión del 10 nov): la dona de «Un Simpson al azar» se fue del encabezado (eran seis cosas): vive junto a Canales.
struct HomeHeader: View {
    @Binding var kind: String
    let collapsed: Bool
    let showsRemote: Bool
    let remote: () -> Void
    let avatar: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    @State private var drag: CGFloat = 0
    @State private var width: CGFloat = 1
    @State private var standardHeight: CGFloat = 0
    @State private var rowHeight: CGFloat = 0
    @State private var pulse = false
    @State private var kindOpen = false
    @State private var pulsed = false

    /// Cómo avisa que hay historias nuevas (HH2 o HH3, Fernando, 9 nov; se elige al ver las dos de verdad).
    enum Hint { case ringOnAvatar, storyInCapsule }
    static var hint: Hint {
        #if DEBUG
        if Demo.has("-demo-hint-hh3") { return .storyInCapsule }
        #endif
        return .ringOnAvatar
    }

    private func openStories() { withAnimation(DS.Motion.smooth(reduceMotion) ?? DS.Motion.fade) { open = true } }

    var body: some View {
        let _ = env.ui.openStory   // al cerrar una historia, se vuelven a leer
        let stories = LearnModel(env.services).rings()
        let progress = stories.isEmpty ? 0 : (open ? 1 - max(0, drag) / width : max(0, -drag) / width)
        // El alto pasa del de siempre al de las historias al mismo paso que el dedo: la portada no brinca al empezar a deslizar.
        let height = standardHeight == 0 ? nil : standardHeight + (rowHeight - standardHeight) * (stories.isEmpty ? 0 : progress)
        ZStack(alignment: .topLeading) {
            standard
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { standardHeight = $0 }
                .offset(x: -progress * width * DS.HomeStories.away)
                .opacity(1 - progress)   // ds-exception: sigue al dedo (la fracción deslizada), no es un papel
                .allowsHitTesting(!open)
                .accessibilityHidden(open)
            if !stories.isEmpty {
                // Cerradas y sin deslizar: `hidden()` las quita también de VoiceOver (solo `accessibilityHidden` las dejaba
                // fuera de la pantalla para la accesibilidad, a la derecha), y su alto se sigue midiendo.
                let away = !open && progress == 0
                Group { if away { row(stories).hidden() } else { row(stories) } }
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
                    .offset(x: (1 - progress) * width * DS.HomeStories.away)
                    .opacity(progress)   // ds-exception: sigue al dedo (la fracción deslizada), no es un papel
                    .allowsHitTesting(open)
                    .accessibilityHidden(!open)
            }
        }
        .frame(height: height, alignment: .top)
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .contentShape(Rectangle())
        .simultaneousGesture(swipe(enabled: !stories.isEmpty))
        .animation(DS.Motion.smooth(reduceMotion), value: collapsed)
        .dsFeedback(.selection, trigger: open)
        .onChange(of: stories.isEmpty) { _, empty in if empty { open = false } }
        #if DEBUG
        .task { if Demo.isOn, Demo.has("-demo-stories-open") { open = true } }   // capturas: ya abiertas
        #endif
    }

    /// Lo de siempre en un renglón (EH1, Fernando, 9 nov): el logo, «Todo ▾» y la cápsula (el control y tu foto). Con
    /// historias sin ver, tu foto lleva un anillo turquesa y tocarla las abre (tu perfil sigue junto a la ✕ de las historias).
    private var standard: some View {
        let stories = LearnModel(env.services).rings()
        return HStack(spacing: DS.Space.s2) {
            AppMark(small: true)   // un poco más chico: así caben «Todo ▾» y la cápsula
            DSKindFilter(kind: $kind, menu: true, open: $kindOpen).accessibilityIdentifier("home-kind-filter")
            Spacer(minLength: DS.Space.s2)
            // SX1: mientras eliges, la cápsula se recoge a la derecha hasta quedar solo tu foto, apagada; tocarla cierra.
            // En un iPhone chico (SE) ni tu foto cabe junto al selector abierto: se va del todo y regresa al elegir.
            if !(kindOpen && WindowMetrics.size.width < DS.KindPill.narrowScreen) {
            capsule(stories)
                .opacity(kindOpen ? DS.Opacity.dimmed : 1)
                // al cerrar, regresa un instante después de que la pastilla se encoge: nunca se enciman
                .animation((DS.Motion.morph(reduceMotion) ?? DS.Motion.fade).delay(kindOpen ? 0 : DS.Motion.entranceStep * 2), value: kindOpen)
                .allowsHitTesting(!kindOpen)
                .overlay { if kindOpen { Color.clear.contentShape(Rectangle()).onTapGesture { withAnimation(DS.Motion.morph(reduceMotion) ?? DS.Motion.fade) { kindOpen = false } } } }
                .transition(.scale(scale: DS.KindPill.enterScale, anchor: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.bottom, DS.Space.s1)
        .frame(maxWidth: WindowMetrics.size.width)   // nunca más ancho que la pantalla (si no, toda Inicio se recorre)
    }

    /// La cápsula: el control y tu foto (se hace a un lado mientras eliges en el selector, SX1).
    private func capsule(_ stories: [LearnStory]) -> some View {
            HStack(spacing: Self.hint == .storyInCapsule ? DS.Space.s2 : DS.Space.s4) {
                if showsRemote && !kindOpen {
                    Button(action: remote) { Image(systemName: "av.remote").font(DS.TextRecipe.section.font) }
                        .accessibilityLabel(Text("Control de tu Orbital")).accessibilityIdentifier("home-remote")
                }
                if let first = stories.first, Self.hint == .storyInCapsule {
                    // HH3: un círculo de historia en la cápsula; tu foto sigue siendo tu perfil.
                    Button { openStories() } label: {
                        LearnRingMark(story: first, unseen: true, ring: DS.HomeStories.capsuleRing, tile: DS.HomeStories.capsuleTile)
                    }
                    .accessibilityLabel(Text("Historias nuevas de Aprende")).accessibilityIdentifier("home-stories-ring")
                    ProfileButton(avatar: avatar)
                } else if !stories.isEmpty {
                    // HH2: tu foto con el mismo anillo de las historias (grueso, con aire), que late una vez al llegar.
                    Button { openStories() } label: {
                        AvatarImage(id: avatar)
                            .padding(DS.Stroke.focus)
                            .overlay(Circle().stroke(DS.fresh, lineWidth: DS.Story.ringStroke))
                            .scaleEffect(pulse ? DS.HomeStories.pulse : 1)
                    }
                    .accessibilityLabel(Text("Historias nuevas de Aprende")).accessibilityIdentifier("home-stories-ring")
                    .task {
                        guard !reduceMotion, !pulsed else { return }
                        pulsed = true
                        try? await Task.sleep(for: DS.HomeStories.pulseDelay)
                        withAnimation(DS.Motion.smooth(reduceMotion) ?? DS.Motion.fade) { pulse = true }
                        try? await Task.sleep(for: DS.HomeStories.pulseHold)
                        withAnimation(DS.Motion.smooth(reduceMotion) ?? DS.Motion.fade) { pulse = false }
                    }
                } else {
                    ProfileButton(avatar: avatar)
                }
            }
            .buttonStyle(.plain).foregroundStyle(DS.text)
            .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
            .glassEffect(.regular.interactive(), in: Capsule())
    }

    /// Las historias en lugar de todo el encabezado, con la ✕ para regresar.
    private func row(_ stories: [LearnStory]) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            LearnRings(stories: stories, compact: collapsed) { env.ui.openStory = $0.id }
                .frame(maxWidth: .infinity)
            ProfileButton(avatar: avatar).buttonStyle(.plain)   // EH1: tu perfil, aquí mientras tu foto abre las historias
            DSIconButton(symbol: "xmark", label: "Volver", size: .small) {
                withAnimation(DS.Motion.smooth(reduceMotion) ?? DS.Motion.fade) { open = false }
            }
            .accessibilityIdentifier("home-stories-close")
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.vertical, DS.Space.s2)
    }

    /// Deslizar a la izquierda abre, a la derecha cierra; mientras, todo sigue al dedo.
    private func swipe(enabled: Bool) -> some Gesture {
        DragGesture(minimumDistance: DS.Space.s3)
            .onChanged { g in
                guard enabled, abs(g.translation.width) > abs(g.translation.height) else { return }
                drag = open ? max(0, g.translation.width) : min(0, g.translation.width)
            }
            .onEnded { g in
                guard enabled else { return }
                let far = width * DS.HomeStories.commit
                withAnimation(DS.Motion.smooth(reduceMotion) ?? DS.Motion.fade) {
                    if !open, -g.translation.width > far || -g.predictedEndTranslation.width > width / 2 { open = true }
                    else if open, g.translation.width > far || g.predictedEndTranslation.width > width / 2 { open = false }
                    drag = 0
                }
            }
    }
}
