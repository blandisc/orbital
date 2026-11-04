import SwiftUI
import OrbitalModels

/// Las escenas de «Aprende Orbital» (versión final, 4 nov 2026: «que las animaciones representen los elementos reales… show,
/// don't tell»): la pantalla de la app en miniatura, un dedo fantasma que hace el gesto y lo que pasa. Cada escena avanza por
/// compases (`SceneLoop`) y vuelve a empezar; con «Reducir movimiento» se queda en su último compás, quieta y entendible.
/// Las piezas en miniatura (póster, botón, renglón) usan los mismos papeles y radios que las de verdad.
struct StorySceneView: View {
    let scene: LearnStory.Scene
    let tint: Color

    var body: some View {
        SceneScreen {
            switch scene {
            case .titlePlay: SceneTitlePlay()
            case .versionLight: SceneVersionLight()
            case .storageStill: SceneStorageStill()
            case .payPlans: ScenePayPlans()
            case .twoPhones: SceneTwoPhones()
            case .typedVersion: SceneTypedVersion()
            case .languageOrder: SceneLanguages(drag: false)
            case .languageDrag: SceneLanguages(drag: true)
            case .versionsSheet: SceneVersionsSheet()
            case .cloudRequest: SceneCloudRequest()
            case .mosaicDrift: SceneMosaic(zoom: false)
            case .mosaicZoom: SceneMosaic(zoom: true)
            case .deckSwipe: SceneDeck()
            case .decideShuffle: SceneDecide()
            case .filterTiles: SceneFilters()
            case .playerBare: ScenePlayer(gesture: .none)
            case .playerDoubleTap: ScenePlayer(gesture: .doubleTap)
            case .playerPinch: ScenePlayer(gesture: .pinch)
            case .playerLock: ScenePlayer(gesture: .lock)
            case .downloadRing: SceneDownload(next: false)
            case .nextEpisode: SceneDownload(next: true)
            case .handoff: SceneHandoff()
            case .becauseRow: SceneBecause()
            case .lockScreenAlert: SceneLockAlert()
            case .releaseCalendar: SceneCalendar()
            case .alertToggles: SceneToggles()
            case .yearCount: SceneYear()
            case .remoteFocus: SceneRemote()
            case .sendToTV: SceneSendToTV(back: false)
            case .continueHere: SceneSendToTV(back: true)
            case .voiceAsk: SceneVoice()
            }
        }
    }
}

// MARK: piezas de las escenas

/// Avanza por compases (0, 1, 2…) y vuelve a empezar, con el resorte de la app. Con «Reducir movimiento», el último quieto.
struct SceneLoop<Content: View>: View {
    let steps: Int
    var beat: Duration = DS.Scene.beat
    @ViewBuilder let content: (Int) -> Content
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.storyTurn) private var turn

    var body: some View {
        let waiting = turn?.waiting == true
        content(waiting ? 0 : reduceMotion ? steps - 1 : step)
            .task(id: "\(reduceMotion)|\(waiting)") {
                guard !reduceMotion, !waiting else { return }
                step = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: beat)
                    withAnimation(DS.Motion.spring(reduceMotion)) { step = (step + 1) % steps }
                }
            }
    }
}

/// La pantalla del iPhone en miniatura: su marco y su fondo; adentro, la escena en proporción.
struct SceneScreen<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            // Con mínimo cero la pantallita mide lo que le dan y recorta lo que sobre (sin él, una escena alta se salía).
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)   // ds-exception: cero es «sin mínimo», no una medida
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            .background(DS.bg, in: RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous).strokeBorder(DS.fill, lineWidth: DS.Stroke.regular) }
            .aspectRatio(DS.Scene.phoneAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
    }
}

/// El dedo fantasma: una yema translúcida que se hunde al tocar.
struct SceneFinger: View {
    var pressed = false
    var shown = true

    var body: some View {
        Circle().fill(DS.paper.opacity(DS.Opacity.faint))
            .overlay { Circle().strokeBorder(DS.paper, lineWidth: DS.Stroke.selected) }
            .frame(width: DS.Scene.finger, height: DS.Scene.finger)
            .scaleEffect(pressed ? DS.Scene.pressed : 1)
            .opacity(shown ? 1 : 0)
    }
}

/// Un póster en miniatura: su color y su nombre (como el póster de la app cuando aún no carga su imagen).
struct ScenePoster: View {
    let title: String
    var tint: Color = DS.ListTint.series

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(tint.opacity(DS.Opacity.dimmed))
            .aspectRatio(DS.Poster.aspect, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                Text(verbatim: title).recipe(.footnote, color: DS.paper).lineLimit(2).padding(DS.Space.s1)
            }
    }
}

/// Un botón en miniatura («Ver», «Versión»): lleno o de vidrio, y se hunde al tocarlo.
struct SceneButton: View {
    let title: LocalizedStringKey
    var symbol: String?
    var prominent = true
    var pressed = false

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(DS.TextRecipe.label.font).foregroundStyle(prominent ? DS.onPrimary : DS.text)
        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
        .frame(maxWidth: .infinity)
        .background(prominent ? DS.primary : DS.fill, in: Capsule())
        .scaleEffect(pressed ? DS.Scene.pressed : 1)
    }
}

/// Un renglón en miniatura: su texto y, a la derecha, su estado.
struct SceneRow<Trailing: View>: View {
    let title: Text
    var lit = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            title.recipe(.footnote, color: DS.text).lineLimit(1)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s2)
        .dsCard(.row, fill: lit ? DS.fresh.opacity(DS.Opacity.selectedFill) : nil)
    }
}

/// Las líneas grises de una ficha (el texto que no importa en la escena).
struct SceneLines: View {
    var count = 2

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(DS.fill).frame(height: DS.Scene.line).frame(maxWidth: .infinity)
                    .padding(.trailing, i == count - 1 ? DS.Space.s8 : 0)
            }
        }
    }
}

// MARK: H1 · Ver al instante

/// La ficha de Dune: el dedo toca «Ver», la ficha se vuelve el reproductor y el video corre.
struct SceneTitlePlay: View {
    var body: some View {
        SceneLoop(steps: 4) { step in
            ZStack {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.ListTint.flame.opacity(DS.Opacity.dimmed))
                        .overlay { Text(verbatim: "Dune").recipe(.title, color: DS.paper) }
                    SceneButton(title: "Ver", symbol: "play.fill", pressed: step == 1)
                    SceneLines(count: 3)
                }
                .padding(DS.Space.s3)
                .opacity(step >= 2 ? 0 : 1)
                ScenePlayerFrame(playing: step >= 2, progress: step == 3 ? DS.Explainer.restScale : 0)
                    .scaleEffect(step >= 2 ? 1 : DS.Motion.leaveScale)
                    .opacity(step >= 2 ? 1 : 0)
                SceneFinger(pressed: step == 1, shown: step == 1).offset(y: DS.Space.s6)
            }
        }
    }
}

/// El reproductor en miniatura: el cuadro del video y su barrita.
struct ScenePlayerFrame: View {
    var playing = true
    var progress: Double = 0
    var filled = false

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.backdropDeep
            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                .fill(DS.ListTint.flame.opacity(DS.Opacity.dimmed))
                .aspectRatio(filled ? nil : DS.Poster.stillAspect, contentMode: .fit)
                .frame(maxHeight: .infinity)
                .overlay { Image(systemName: playing ? "play.fill" : "pause.fill").font(DS.TextRecipe.section.font).foregroundStyle(DS.paper.opacity(DS.Opacity.dimmed)) }
            GeometryReader { geo in
                Capsule().fill(DS.paper.opacity(DS.Opacity.faint)).overlay(alignment: .leading) {
                    Capsule().fill(DS.paper).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: DS.Scene.line / 2)
            .padding(DS.Space.s3)
        }
    }
}

/// La lista de versiones: la que está «Al instante» se enciende y su luz baja al reproductor.
struct SceneVersionLight: View {
    var body: some View {
        SceneLoop(steps: 4) { step in
            VStack(spacing: DS.Space.s2) {
                Text("Versión").recipe(.cardTitle, color: DS.text).frame(maxWidth: .infinity, alignment: .leading)
                SceneRow(title: Text(verbatim: "🇲🇽 Latino · 1080p"), lit: step >= 1) { Text("Al instante").recipe(.footnote, color: DS.fresh) }
                SceneRow(title: Text(verbatim: "🇺🇸 Inglés · 4K")) { Text("Al instante").recipe(.footnote, color: DS.textMuted) }
                SceneRow(title: Text(verbatim: "🇪🇸 Castellano · 1080p")) { Text("Por pedir").recipe(.footnote, color: DS.textMuted) }
                Spacer(minLength: 0)
                ScenePlayerFrame(playing: step >= 3, progress: step >= 3 ? DS.Opacity.faint : 0)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .frame(maxHeight: .infinity)
                    .overlay { if step == 2 { Capsule().fill(DS.fresh).frame(width: DS.Stroke.focus).transition(.move(edge: .top)) } }
            }
            .padding(DS.Space.s3)
        }
    }
}

/// El espacio del iPhone se queda quieto mientras el video corre.
struct SceneStorageStill: View {
    var body: some View {
        SceneLoop(steps: 3) { step in
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ScenePlayerFrame(playing: true, progress: Double(step + 1) / 4).clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                Text("Espacio en tu iPhone").recipe(.footnote, color: DS.textMuted)
                GeometryReader { geo in
                    Capsule().fill(DS.fill).overlay(alignment: .leading) { Capsule().fill(DS.text).frame(width: geo.size.width * DS.Opacity.faint) }
                }
                .frame(height: DS.Scene.line)
                Label("Igual", systemImage: "checkmark.circle.fill").recipe(.label, color: DS.success)
            }
            .padding(DS.Space.s3)
        }
    }
}

/// La página de Real-Debrid: se elige 15 días; luego el aviso de Orbital antes de que se acabe.
struct ScenePayPlans: View {
    var body: some View {
        SceneLoop(steps: 4) { step in
            ZStack(alignment: .top) {
                VStack(spacing: DS.Space.s2) {
                    Text(verbatim: "real-debrid.com").recipe(.footnote, color: DS.textMuted)
                    ForEach(["15", "30", "90"], id: \.self) { days in
                        SceneRow(title: Text("\(days) días"), lit: days == "15" && step >= 1) {
                            Image(systemName: days == "15" && step >= 1 ? "checkmark.circle.fill" : "circle").foregroundStyle(DS.fresh)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.s3)
                SceneFinger(pressed: step == 1, shown: step == 1).offset(y: DS.Space.s10)
                if step >= 2 {
                    SceneNotice(symbol: "bell.badge.fill", text: Text("Te quedan 3 días · Renovar"))
                        .padding(DS.Space.s2).transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}

/// Un aviso que baja desde arriba, como los de la app y los de la pantalla bloqueada.
struct SceneNotice: View {
    let symbol: String
    let text: Text

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: symbol).foregroundStyle(DS.fresh)
            text.recipe(.footnote, color: DS.text).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s2)
        .dsCard(.card)
    }
}

/// Dos iPhone con la misma cuenta: el segundo se congela con su aviso.
struct SceneTwoPhones: View {
    var body: some View {
        SceneLoop(steps: 3) { step in
            HStack(spacing: DS.Space.s2) {
                ScenePlayerFrame(playing: true, progress: Double(step + 1) / 4).clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                ScenePlayerFrame(playing: step < 2, progress: DS.Opacity.faint)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay { if step >= 2 { Image(systemName: "exclamationmark.triangle.fill").font(DS.TextRecipe.section.font).foregroundStyle(DS.warning).transition(.scale) } }
                    .saturation(step >= 2 ? 0 : 1)
            }
            .padding(DS.Space.s3)
        }
    }
}

// MARK: H2 · En tu idioma

/// El botón «Ver» en grande y, debajo, tu versión que se escribe letra por letra.
struct SceneTypedVersion: View {
    private let words = "🇲🇽 Latino · 1080p"

    var body: some View {
        SceneLoop(steps: words.count + 4, beat: DS.Scene.beat / 6) { step in
            VStack(spacing: DS.Space.s3) {
                Spacer(minLength: 0)
                SceneButton(title: "Ver", symbol: "play.fill")
                Text(verbatim: String(words.prefix(step))).recipe(.label, color: DS.textMuted)
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s4)
        }
    }
}

/// Ajustes › Tus idiomas: si no hay en latino, arranca con el siguiente; o el dedo sube «Inglés» al primer lugar.
struct SceneLanguages: View {
    let drag: Bool
    private let base = ["Latino", "Idioma original", "Inglés", "Castellano"]
    @Environment(\.storyTurn) private var turn
    /// Tu turno: lo que llevas arrastrado «Inglés» y si ya lo subiste.
    @State private var pull: CGFloat = 0
    @State private var moved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SceneLoop(steps: 4) { step in
            let order = drag && (step >= 2 || moved) ? ["Inglés", "Latino", "Idioma original", "Castellano"] : base
            VStack(spacing: DS.Space.s2) {
                Text("Tus idiomas").recipe(.cardTitle, color: DS.text).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(order.enumerated()), id: \.element) { i, name in
                    let missing = !drag && name == "Latino" && step >= 1
                    let starts = !drag && name == "Idioma original" && step >= 2
                    SceneRow(title: Text(LocalizedStringKey(name)), lit: starts) {
                        if missing { Text("No hay").recipe(.footnote, color: DS.textMuted) }
                        else if starts { Image(systemName: "play.fill").foregroundStyle(DS.fresh) }
                        else { Image(systemName: "line.3.horizontal").foregroundStyle(DS.textMuted) }
                    }
                    .opacity(missing ? DS.Opacity.dimmed : 1)
                    .scaleEffect(drag && name == "Inglés" && (step == 1 || pull != 0) ? DS.Scene.lifted : 1)
                    .offset(y: drag && name == "Inglés" ? pull : 0)
                    .gesture(drag && name == "Inglés" && turn?.waiting == true ? DragGesture().onChanged { pull = min(0, $0.translation.height) }.onEnded { g in
                        withAnimation(DS.Motion.spring(reduceMotion)) { pull = 0; if g.translation.height < -DS.Scene.finger * 2 { moved = true } }
                        if moved { turn?.done() }
                    } : nil)
                    .zIndex(name == "Inglés" ? 1 : 0)   // ds-exception: lo que se arrastra va encima
                    .overlay(alignment: .trailing) {
                        if drag && name == "Inglés" && (step == 1 || step == 2) { SceneFinger(pressed: true).offset(x: -DS.Space.s1) }
                    }
                    .id(i)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
        }
    }
}

/// La ficha: el dedo toca «Versión» y sube la lista, «Al instante» arriba y «Por pedir» abajo.
struct SceneVersionsSheet: View {
    var body: some View {
        SceneLoop(steps: 3) { step in
            ZStack(alignment: .bottom) {
                VStack(spacing: DS.Space.s2) {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.ListTint.series.opacity(DS.Opacity.dimmed))
                    HStack(spacing: DS.Space.s2) {
                        SceneButton(title: "Ver", symbol: "play.fill")
                        SceneButton(title: "Versión", prominent: false, pressed: step == 1)
                            .overlay { SceneFinger(pressed: step == 1, shown: step == 1) }
                    }
                    SceneLines(count: 2)
                }
                .padding(DS.Space.s3)
                if step >= 2 {
                    VStack(spacing: DS.Space.s2) {
                        SceneRow(title: Text(verbatim: "🇲🇽 Latino · 1080p")) { Text("Al instante").recipe(.footnote, color: DS.fresh) }
                        SceneRow(title: Text(verbatim: "🇯🇵 Japonés · 4K")) { Text("Al instante").recipe(.footnote, color: DS.fresh) }
                        SceneRow(title: Text(verbatim: "🇪🇸 Castellano · 720p")) { Text("Por pedir").recipe(.footnote, color: DS.textMuted) }
                    }
                    .padding(DS.Space.s3)
                    .dsCard(.card)
                    .transition(.move(edge: .bottom))
                }
            }
        }
    }
}

/// Una versión «Por pedir»: el dedo la toca, baja en la nube y llega el aviso «Lista para ver».
struct SceneCloudRequest: View {
    var body: some View {
        SceneLoop(steps: 5) { step in
            ZStack(alignment: .top) {
                VStack(spacing: DS.Space.s2) {
                    Spacer(minLength: 0)
                    SceneRow(title: step == 0 ? Text("4K · Latino · Por pedir") : step < 3 ? (Text("Bajando en la nube") + Text(verbatim: " · \(step == 1 ? "12" : "42") %")) : Text("Lista para ver"),
                             lit: step >= 3) {
                        Image(systemName: step >= 3 ? "play.fill" : DS.Symbol.cloud).foregroundStyle(DS.fresh)
                    }
                    .overlay { SceneFinger(pressed: step == 0, shown: step == 0) }
                    GeometryReader { geo in
                        Capsule().fill(DS.fill).overlay(alignment: .leading) {
                            Capsule().fill(DS.fresh).frame(width: geo.size.width * [0, 0.12, 0.42, 1, 1][step])   // ds-exception: el avance que cuenta la escena
                        }
                    }
                    .frame(height: DS.Scene.line / 2)
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.s3)
                if step >= 4 {
                    SceneNotice(symbol: "checkmark.icloud.fill", text: Text("Lista para ver"))
                        .padding(DS.Space.s2).transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}
