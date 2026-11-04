import SwiftUI
import UIKit
import OrbitalModels

/// Una historia de «Aprende Orbital» (G3) a pantalla completa, como las de Instagram y el Wrapped: avanza sola (5 s por
/// tarjeta, 7 si el texto es largo), tocar a la izquierda regresa y a la derecha sigue, mantener pausa y bajar cierra. Con
/// VoiceOver o «Reducir movimiento» no avanza sola (acciones «Siguiente» y «Anterior»); en la Mac, flechas y Escape. La
/// última tarjeta lleva su botón a la función («Probar la búsqueda avanzada»). Recibe sus datos: no lee el estado de la app.
struct StoryPlayer: View {
    let story: LearnStory
    /// La que se ve en el mazo (las de los lados esperan quietas).
    var active = true
    /// Llegó a la última tarjeta (ya cuenta como vista).
    var onFinish: () -> Void = {}
    var onAction: (LearnStory.Destination) -> Void = { _ in }
    /// Pasar de la última tarjeta lleva a la historia siguiente, y regresar de la primera a la anterior (como Instagram).
    var onNextStory: (() -> Void)?
    var onPreviousStory: (() -> Void)?
    let close: () -> Void
    @State private var index = 0
    @State private var progress: Double = 0
    @State private var paused = false
    @State private var width: CGFloat = 0
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var card: LearnStory.Card { story.cards[min(index, story.cards.count - 1)] }
    private var last: Bool { index >= story.cards.count - 1 }
    private var tint: Color { DS.ListTint.named(story.tint) }
    private var autoAdvance: Bool { !reduceMotion && !UIAccessibility.isVoiceOverRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            bars
            HStack(spacing: DS.Space.s3) {
                DSIconTile(symbol: story.symbol, tint: tint, side: DS.Story.hand)
                Text(LocalizedStringKey(story.title)).recipe(.cardTitle, color: DS.paper)
                Text("\(String(index + 1)) de \(String(story.cards.count))").recipe(.footnote, color: DS.paper.opacity(DS.Opacity.dimmed))
                Spacer()
                DSIconButton(symbol: "xmark", label: "Cerrar", size: .regular, action: close)
                    .accessibilityIdentifier("story-close")
            }
            Spacer(minLength: 0)
            StoryCardView(card: card, tint: tint).id(index).transition(.opacity.combined(with: .move(edge: .trailing)))
            Spacer(minLength: 0)
            if last, let action = story.action {
                Button { onAction(action.destination) } label: { Text(LocalizedStringKey(action.title)).frame(maxWidth: .infinity) }
                    .dsPrimaryButton().controlSize(.large)
                    .accessibilityIdentifier("story-action")
            }
        }
        .padding(DS.Space.gutter)
        .frame(maxWidth: DS.Guide.readable, maxHeight: .infinity, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background { ZStack { DS.backdropDeep; tint.opacity(DS.Explainer.tileFill) }.ignoresSafeArea() }
        .foregroundStyle(DS.paper)
        .offset(y: max(0, drag))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { g in step(g.location.x < width * DS.Watching.backZone ? -1 : 1) })
        .onLongPressGesture(minimumDuration: DS.Watching.holdToPause, perform: {}, onPressingChanged: { paused = $0 })
        .simultaneousGesture(DragGesture().onChanged { g in if abs(g.translation.height) > abs(g.translation.width) { drag = g.translation.height } }.onEnded { g in
            if g.translation.height > DS.Story.closeDrag { close() } else { withAnimation(DS.Motion.spring(reduceMotion)) { drag = 0 } }
        })
        .animation(DS.Motion.base(reduceMotion), value: index)
        .task(id: "\(index)|\(paused)|\(active)|\(scenePhase == .active)") { await tick() }
        .onChange(of: index) { _, _ in if last { onFinish() } }
        .onAppear { if story.cards.count == 1 { onFinish() } }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .accessibilityAction(named: Text("Siguiente")) { step(1) }
        .accessibilityAction(named: Text("Anterior")) { step(-1) }
        .accessibilityAction(.escape) { close() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("story")
    }

    private func tick() async {
        guard autoAdvance, active, !paused, scenePhase == .active else { return }
        let length = card.body.count > DS.Story.longText || (last && story.action != nil) ? DS.Story.longCard : DS.Story.card
        for i in 0..<DS.Story.ticks {
            try? await Task.sleep(for: length / DS.Story.ticks)
            if Task.isCancelled { return }
            progress = Double(i + 1) / Double(DS.Story.ticks)
        }
        step(1)
    }

    private func step(_ by: Int) {
        let next = index + by
        if next >= story.cards.count { if let onNextStory { onNextStory() } else { close() }; return }
        if next < 0 { onPreviousStory?(); return }
        index = next; progress = 0
    }

    private var bars: some View {
        HStack(spacing: DS.Space.s1) {
            ForEach(story.cards.indices, id: \.self) { i in
                GeometryReader { geo in
                    Capsule().fill(DS.paper.opacity(DS.Watching.barTrack)).overlay(alignment: .leading) {
                        Capsule().fill(DS.paper).frame(width: geo.size.width * (i < index ? 1 : i == index ? (autoAdvance ? progress : 1) : 0))
                    }
                }
                .frame(height: DS.Watching.storyBar)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Las historias en fila, como Instagram: se abre en la que tocaste y, al terminar una (o al deslizar a la izquierda), sigue
/// la próxima; a la derecha, la anterior. El paso es un cubo que gira con el dedo y se acomoda con su resorte (física del
/// desplazamiento por páginas). Con «Reducir movimiento», páginas planas. Recibe sus datos.
struct StoryDeck: View {
    let stories: [LearnStory]
    let start: String
    var onSeen: (LearnStory) -> Void = { _ in }
    var onAction: (LearnStory.Destination) -> Void = { _ in }
    let close: () -> Void
    @State private var current: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(stories.enumerated()), id: \.element.id) { i, story in
                        StoryPlayer(story: story, active: current == story.id, onFinish: { onSeen(story) }, onAction: onAction,
                                    onNextStory: { go(i + 1) }, onPreviousStory: i > 0 ? { go(i - 1) } : nil, close: close)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .visualEffect { content, proxy in
                                // -1…1: cuánto se fue a la izquierda o a la derecha; gira sobre la orilla que comparte con la otra.
                                let shift = proxy.frame(in: .scrollView(axis: .horizontal)).minX / max(proxy.size.width, 1)
                                return content.rotation3DEffect(.degrees(reduceMotion ? 0 : Double(shift) * DS.Story.cubeAngle), axis: (x: 0, y: 1, z: 0),
                                                                anchor: shift < 0 ? .trailing : .leading, perspective: DS.Story.cubePerspective)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .scrollIndicators(.hidden)
        }
        .background(DS.backdropDeep.ignoresSafeArea())
        .onAppear { current = start }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("story-deck")
    }

    private func go(_ i: Int) {
        guard stories.indices.contains(i) else { return close() }
        withAnimation(DS.Motion.smooth(reduceMotion) ?? DS.Motion.fade) { current = stories[i].id }
    }
}

/// Una tarjeta de historia con su plantilla: portada (el planeta chico), tres pasos de la nube, gesto (una mano fantasma lo
/// repite dos veces), antes y ahora (un deslizador que se mueve solo) o el símbolo grande en su color.
struct StoryCardView: View {
    let card: LearnStory.Card
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            art.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(LocalizedStringKey(card.title)).recipe(.display, color: DS.paper).fixedSize(horizontal: false, vertical: true)
                Text(LocalizedStringKey(card.body)).recipe(.body, color: DS.paper).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var art: some View {
        switch card.template {
        case .cover: OrbitalMark(size: DS.Story.symbol, animated: true).foregroundStyle(DS.paper)
        case .threeSteps: DebridFlowStrip()
        case .gesture(let symbol, let motion): StoryGesture(symbol: symbol, motion: motion, tint: tint)
        case .beforeAfter(let before, let after): StoryBeforeAfter(before: before, after: after, tint: tint)
        case .symbol(let symbol):
            Image(systemName: symbol).font(.system(size: DS.Story.symbol)).symbolRenderingMode(.hierarchical).foregroundStyle(tint)   // ds-exception: un dibujo, no texto: no crece con Dynamic Type
                .accessibilityHidden(true)
        }
    }
}

/// La mano fantasma: un círculo del tamaño de un dedo que repite el gesto dos veces sobre el símbolo.
struct StoryGesture: View {
    let symbol: String
    let motion: LearnStory.Motion
    let tint: Color
    @State private var round = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Image(systemName: symbol).font(.system(size: DS.Story.symbol)).symbolRenderingMode(.hierarchical).foregroundStyle(tint)   // ds-exception: un dibujo, no texto: no crece con Dynamic Type
            Circle().fill(DS.paper.opacity(DS.Opacity.faint)).frame(width: DS.Story.hand, height: DS.Story.hand)
                .keyframeAnimator(initialValue: Finger(), trigger: round) { finger, value in
                    finger.scaleEffect(value.scale).offset(x: value.x, y: value.y).opacity(value.shown)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(1, duration: 0.2); CubicKeyframe(motion == .pinch ? 1.6 : 0.8, duration: 0.3)   // ds-exception: la coreografía de un gesto
                        CubicKeyframe(1, duration: 0.3)
                    }
                    KeyframeTrack(\.x) {
                        CubicKeyframe(0, duration: 0.2); CubicKeyframe(motion == .swipeSide ? DS.Story.handTravel : 0, duration: 0.5)   // ds-exception: la coreografía de un gesto
                        CubicKeyframe(0, duration: 0.1)
                    }
                    KeyframeTrack(\.y) {
                        CubicKeyframe(0, duration: 0.2); CubicKeyframe(motion == .swipeUp ? -DS.Story.handTravel : 0, duration: 0.5)   // ds-exception: la coreografía de un gesto
                        CubicKeyframe(0, duration: 0.1)
                    }
                    KeyframeTrack(\.shown) { CubicKeyframe(1, duration: 0.7); CubicKeyframe(0, duration: 0.1) }   // ds-exception: la coreografía de un gesto
                }
        }
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else { return }
            for _ in 0..<2 { round += 1; try? await Task.sleep(for: DS.Attract.scene) }
        }
    }

    struct Finger { var scale: CGFloat = 1, x: CGFloat = 0, y: CGFloat = 0, shown: Double = 0 }
}

/// Antes y ahora: dos estados y un deslizador que va de uno al otro solo.
struct StoryBeforeAfter: View {
    let before: String
    let after: String
    let tint: Color
    @State private var moved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            HStack {
                Text(LocalizedStringKey(before)).recipe(.label, color: moved ? DS.paper.opacity(DS.Opacity.dimmed) : DS.paper)
                Spacer()
                Text(LocalizedStringKey(after)).recipe(.label, color: moved ? DS.paper : DS.paper.opacity(DS.Opacity.dimmed))
            }
            GeometryReader { geo in
                Capsule().fill(DS.paper.opacity(DS.Watching.barTrack)).overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: moved ? geo.size.width : geo.size.width * DS.Watching.backZone)
                }
            }
            .frame(height: DS.Space.s2)
        }
        .padding(DS.Space.s4)
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else { moved = true; return }
            try? await Task.sleep(for: DS.Attract.scene)
            withAnimation(DS.Motion.spring(reduceMotion)) { moved = true }
        }
    }
}

/// La fila de historias de «Aprende Orbital» (G3) en el encabezado de Inicio (HE1-B): hasta cuatro sin ver, con su anillo de
/// «nuevo». `compact`: al bajar, cada círculo se achica en su mismo lugar y su nombre se va. Recibe sus datos.
struct LearnRings: View {
    let stories: [LearnStory]
    var compact = false
    let open: (LearnStory) -> Void

    var body: some View {
        // Repartidos a lo ancho: caben cuatro en un iPhone SE y se quedan en su lugar al encogerse.
        HStack(alignment: .top, spacing: DS.Space.s2) {
            ForEach(stories) { story in
                Button { open(story) } label: { LearnRing(story: story, unseen: true, compact: compact).frame(maxWidth: .infinity) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("learn-ring-\(story.id)")
            }
        }
    }
}

/// Un círculo: el cuadro de color de la historia y, si no la has visto, el anillo de «nuevo». `compact`: al bajar, se achica
/// en su mismo lugar y su nombre se desvanece (HE1-B).
struct LearnRing: View {
    let story: LearnStory
    let unseen: Bool
    var compact = false
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ring = compact ? DS.HomeStories.compactRing : DS.Story.ring
        let tile = compact ? DS.HomeStories.compactTile : DS.Story.tile
        VStack(spacing: DS.Space.s2) {
            LearnRingMark(story: story, unseen: unseen, drawn: drawn || reduceMotion, ring: ring, tile: tile)
            if !compact {
                Text(LocalizedStringKey(story.title)).recipe(.footnote, color: unseen ? DS.text : DS.textMuted)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: DS.Story.ring)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(story.title)))
        .accessibilityHint(unseen ? Text("Sin ver") : Text(verbatim: ""))
        .task { withAnimation(DS.Motion.tint(reduceMotion)) { drawn = true } }
    }
}

/// El dibujo del círculo: el anillo (de «nuevo», que se dibuja una vez) y el cuadro de color con su símbolo.
struct LearnRingMark: View {
    let story: LearnStory
    let unseen: Bool
    var drawn = true
    var ring: CGFloat = DS.Story.ring
    var tile: CGFloat = DS.Story.tile

    var body: some View {
        ZStack {
            Circle().fill(DS.bg)
            Circle().trim(from: 0, to: unseen ? (drawn ? 1 : 0) : 1)
                .stroke(unseen ? DS.fresh : DS.fill, style: StrokeStyle(lineWidth: DS.Story.ringStroke * ring / DS.Story.ring, lineCap: .round))   // más fino en los chicos
                .rotationEffect(.degrees(-90))
            Circle().fill(DS.ListTint.named(story.tint).opacity(DS.Explainer.tileFill))
                .frame(width: tile, height: tile)
            Image(systemName: story.symbol).font(DS.TextRecipe.section.font).symbolRenderingMode(.hierarchical)
                .foregroundStyle(DS.ListTint.named(story.tint))
                .scaleEffect(tile / DS.Story.tile)
        }
        .frame(width: ring, height: ring)
    }
}

/// Lo que se asoma en la orilla derecha de Inicio (HE1-B): dos círculos encimados, el segundo medio escondido tras la orilla.
/// El primero da un empujoncito cada tanto, como invitando a deslizar. Es un botón: con el puntero o el teclado se toca.
struct LearnPeek: View {
    let stories: [LearnStory]
    let open: () -> Void
    @State private var nudged = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            HStack(spacing: -DS.HomeStories.peekOverlap) {
                ForEach(Array(stories.prefix(2).enumerated()), id: \.element.id) { i, story in
                    LearnRingMark(story: story, unseen: true, ring: DS.HomeStories.peekRing, tile: DS.HomeStories.peekRing - DS.Space.s2)
                        .offset(x: i == 0 && nudged ? -DS.HomeStories.nudge : 0)
                        .zIndex(Double(2 - i))
                }
            }
            .offset(x: DS.HomeStories.peekRing * DS.HomeStories.peekHidden)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Historias de Aprende Orbital: \(String(stories.count)) sin ver"))
        .accessibilityIdentifier("home-stories-peek")
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: DS.HomeStories.nudgeEvery)
                withAnimation(DS.Motion.pop(reduceMotion)) { nudged = true }
                try? await Task.sleep(for: DS.Explainer.step / 4)
                withAnimation(DS.Motion.spring(reduceMotion)) { nudged = false }
            }
        }
    }
}
