import SwiftUI
import OrbitalModels

/// El encabezado de Inicio (HE1-B, Fernando, 4 nov 2026): el logo, la cápsula del control, la dona y tu foto, y «Todo ·
/// Películas · Series». Si hay historias de «Aprende» sin ver, dos círculos se asoman en la orilla derecha, a la altura de la
/// barra de tipos (nunca encima de la cápsula). Al deslizar a la izquierda todo sigue a tu dedo: lo de siempre se aleja y se
/// apaga, y las historias entran ocupando el encabezado entero; al soltar, se acomoda con un resorte. Deslizar a la derecha o
/// la ✕ lo regresa. Al bajar, los círculos se achican en su mismo lugar y su nombre se va. Con «Reducir movimiento», fundido.
struct HomeHeader: View {
    @Binding var kind: String
    let collapsed: Bool
    let showsRemote: Bool
    let remote: () -> Void
    let simpsons: () -> Void
    let simpsonsZoom: Namespace.ID
    let avatar: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    @State private var drag: CGFloat = 0
    @State private var width: CGFloat = 1
    @State private var standardHeight: CGFloat = 0
    @State private var rowHeight: CGFloat = 0

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
                row(stories)
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
        .overlay(alignment: .bottomTrailing) {
            if !stories.isEmpty, !open {
                LearnPeek(stories: stories) { withAnimation(DS.Motion.smooth(reduceMotion) ?? DS.Motion.fade) { open = true } }
                    .offset(x: min(0, drag))
                    .opacity(1 - min(1, progress * 2))   // ds-exception: sigue al dedo: se apaga en la primera mitad del gesto
                    .padding(.bottom, DS.Space.s1)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .contentShape(Rectangle())
        .simultaneousGesture(swipe(enabled: !stories.isEmpty))
        .animation(DS.Motion.smooth(reduceMotion), value: collapsed)
        .sensoryFeedback(.selection, trigger: open)
        .onChange(of: stories.isEmpty) { _, empty in if empty { open = false } }
        #if DEBUG
        .task { if Demo.isOn, ProcessInfo.processInfo.arguments.contains("-demo-stories-open") { open = true } }   // capturas: ya abiertas
        #endif
    }

    /// Lo de siempre: el logo y la cápsula (el control, la dona y tu foto), y debajo los tipos.
    private var standard: some View {
        VStack(spacing: DS.Space.s2) {
            HStack {
                AppMark()
                Spacer(minLength: DS.Space.s3)
                HStack(spacing: DS.Space.s5) {
                    if showsRemote {
                        Button(action: remote) { Image(systemName: "av.remote").font(DS.TextRecipe.section.font) }
                            .accessibilityLabel(Text("Control de tu Orbital")).accessibilityIdentifier("home-remote")
                    }
                    Button(action: simpsons) { Image("Glyphs/donut").renderingMode(.original) }
                        .matchedTransitionSource(id: "simpsons", in: simpsonsZoom)   // la tele sale de la dona
                        .accessibilityLabel(Text("Un Simpson al azar")).accessibilityIdentifier("home-random-simpsons")
                    ProfileButton(avatar: avatar)
                }
                .buttonStyle(.plain).foregroundStyle(DS.text)
                .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s2)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .padding(.horizontal, DS.Space.gutter)
            HomeKindBar(kind: $kind)
        }
    }

    /// Las historias en lugar de todo el encabezado, con la ✕ para regresar.
    private func row(_ stories: [LearnStory]) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            LearnRings(stories: stories, compact: collapsed) { env.ui.openStory = $0.id }
                .frame(maxWidth: .infinity)
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
