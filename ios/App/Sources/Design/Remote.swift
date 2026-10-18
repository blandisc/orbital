import SwiftUI
import OrbitalCore

// El control completo de tu Orbital (la hoja de «Viendo en la TV» estirada hacia arriba): piezas del catálogo.

/// El pad táctil, como el del control del Apple TV: deslizar = flechas (una por cada `DS.Remote.swipeStep`, con toque
/// háptico; al seguir deslizando se repite), tocar = A (elegir). Se usa sin mirar.
struct TouchPad: View {
    /// Lo que hace tocar (la A) en la pantalla de la TV ahora («Ver», «Escribir», «Jugar»…), de su leyenda; nil: «A».
    var selectLabel: String?
    let onAction: (OrbitalRemote.InputAction) -> Void
    @State private var origin: CGPoint?
    @State private var gestureStart: CGPoint?
    @State private var moved = false
    @State private var touch: CGPoint?
    @State private var ticks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
            .fill(DS.fill)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous).strokeBorder(DS.hairline, lineWidth: DS.Size.hairline))
            .overlay { hints }
            .overlay {
                if let touch {
                    Circle().fill(DS.fillStrong).frame(width: DS.Remote.touchGlow, height: DS.Remote.touchGlow)
                        .position(touch).allowsHitTesting(false)
                }
            }
            .frame(minHeight: DS.Remote.padHeight)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Un toque nuevo empieza de cero: si la hoja canceló el anterior (sin `onEnded`), su origen viejo
                        // convertía este toque en flecha y la A no llegaba («le toco varias veces y no abre»).
                        if gestureStart != value.startLocation { gestureStart = value.startLocation; origin = nil; moved = false }
                        touch = value.location
                        let start = origin ?? value.startLocation
                        if origin == nil { origin = start }
                        let dx = value.location.x - start.x, dy = value.location.y - start.y
                        guard max(abs(dx), abs(dy)) >= DS.Remote.swipeStep else { return }
                        moved = true
                        fire(abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up))
                        origin = value.location   // la siguiente flecha cuenta desde aquí: seguir deslizando repite
                    }
                    .onEnded { value in
                        let total = hypot(value.translation.width, value.translation.height)
                        if !moved, total < DS.Remote.tapSlop { fire(.select) }
                        origin = nil; moved = false; gestureStart = nil
                        withAnimation(DS.Motion.base(reduceMotion)) { touch = nil }
                    }
            )
            .sensoryFeedback(.selection, trigger: ticks)
            .accessibilityElement()
            .accessibilityLabel(Text("Pad de la TV"))
            .accessibilityHint(selectLabel.map { Text("Desliza para moverte; toca para \($0)") } ?? Text("Desliza para moverte; toca para elegir"))
            .accessibilityAction(named: Text("Arriba")) { onAction(.up) }
            .accessibilityAction(named: Text("Abajo")) { onAction(.down) }
            .accessibilityAction(named: Text("Izquierda")) { onAction(.left) }
            .accessibilityAction(named: Text("Derecha")) { onAction(.right) }
            .accessibilityAction { onAction(.select) }
    }

    private func fire(_ action: OrbitalRemote.InputAction) {
        ticks += 1
        onAction(action)
    }

    /// Las flechas apenas marcadas en las orillas y, al centro, qué hace tocar.
    private var hints: some View {
        ZStack {
            VStack { chevron("chevron.up"); Spacer(); chevron("chevron.down") }
            HStack { chevron("chevron.left"); Spacer(); chevron("chevron.right") }
            VStack(spacing: DS.Space.s1) {
                // La A dice lo que va a pasar al tocar, como el pie de la TV; sin leyenda, la letra del mando.
                Text(verbatim: selectLabel ?? "A").recipe(.title, color: DS.textMuted).lineLimit(1).contentTransition(.opacity)
                (selectLabel == nil ? Text("Desliza · toca para elegir") : Text("A · desliza para moverte")).recipe(.caption, color: DS.textFaint)
            }
        }
        .padding(DS.Space.s4)
        .allowsHitTesting(false)
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name).font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.textFaint)
    }
}

/// Una tecla de la consola en el control completo: ícono, nombre (lo que hace en la pantalla de la TV, si la consola lo dice) y
/// la letra del botón del mando en la esquina (A, B, X, LB…), para quien ya conoce el mando. Del mismo tamaño todas.
struct RemoteKey: View {
    let symbol: String
    let title: Text
    var glyph: String?
    /// La TV dice que en esta pantalla no hace nada: se atenúa, sin moverse de lugar.
    var idle = false
    /// Mantener el dedo (como en el control del Apple TV: mantener «Atrás» lleva al inicio).
    var longPress: (() -> Void)?
    let action: () -> Void
    @State private var taps = 0
    @State private var held = 0

    var body: some View {
        Button { taps += 1; action() } label: {
            VStack(spacing: DS.Space.s1) {
                Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font)
                title.recipe(.caption, color: DS.textMuted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: DS.Remote.keyHeight)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let glyph {
                    Text(verbatim: glyph).recipe(.caption, color: DS.textFaint).padding(.top, DS.Space.s1).padding(.trailing, DS.Space.s2)
                        .accessibilityHidden(true)
                }
            }
            .opacity(idle ? DesignTokens.Opacity.disabled : 1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.text)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: taps)
        .simultaneousGesture(LongPressGesture(minimumDuration: DS.Remote.holdSeconds).onEnded { _ in
            guard let longPress else { return }
            held += 1; longPress()
        })
        .sensoryFeedback(.impact(weight: .heavy), trigger: held)
    }
}

/// Escribir en la TV (la búsqueda de la consola): el campo con el estilo de las teclas del control.
struct RemoteTextField: View {
    @Binding var text: String
    /// La TV abrió un campo de texto: el teclado sale solo (como el control del Apple TV).
    var autoFocus = false
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "keyboard").foregroundStyle(DS.textMuted).accessibilityHidden(true)
            TextField("Escribir en la TV", text: $text)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(onSubmit)
                .foregroundStyle(DS.text)
                .focused($focused)
        }
        .onChange(of: autoFocus, initial: true) { _, wants in if wants { focused = true } }
        .font(DS.TextRecipe.body.font)
        .padding(.horizontal, DS.Space.s4)
        .frame(minHeight: DS.Remote.keyHeight)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }
}

/// «Dile a Orbital»: el micrófono del control. Mientras escucha enseña lo que va entendiendo; al terminar, lo que contestó tu
/// Orbital (que además se dice en voz alta). Las mismas órdenes que a Alexa.
struct VoiceCommandBar: View {
    let listening: Bool
    let transcript: String
    let reply: OrbitalRemote.VoiceReply?
    let denied: Bool
    var heardNothing = false
    /// Esperando lo que contesta tu Orbital.
    var asking = false
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button { taps += 1; action() } label: {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: listening ? "waveform" : "mic.fill")
                    .font(DS.TextRecipe.cardTitle.font)
                    .symbolEffect(.variableColor.iterative, isActive: listening)
                    .foregroundStyle(listening ? DS.onPrimary : DS.text)
                    .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                    .background(listening ? DS.primary : DS.fillStrong, in: Circle())
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    title.recipe(.cardTitle).lineLimit(2)
                    subtitle.recipe(.caption, color: DS.textMuted).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: DS.Remote.keyHeight, alignment: .leading)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: taps)
        .accessibilityLabel(listening ? Text("Terminar la orden") : Text("Dile a Orbital"))
    }

    private var title: Text {
        if listening { return transcript.isEmpty ? Text("Te escucho…") : Text(verbatim: transcript) }
        if denied { return Text("Permite el micrófono y el dictado en Ajustes") }
        if asking { return Text("Preguntándole a tu Orbital…") }
        if heardNothing { return Text("No te escuché. Toca y vuelve a intentar") }
        if let reply, !reply.speech.isEmpty { return Text(verbatim: reply.speech) }
        return Text("Dile a Orbital")
    }

    private var subtitle: Text {
        if listening { return Text("Toca para terminar") }
        // Lo que se entendió, para ver si el dictado escribió bien el nombre.
        if !asking, let reply, !reply.heard.isEmpty { return Text("Entendí: «\(reply.heard)»") }
        return Text("«Pon The Office», «pausa», «descárgalo»")
    }
}

/// Las opciones cuando tu Orbital no supo cuál («pon Dune»: la de 1984 o la de 2021): un renglón por opción, con su póster;
/// tocar una la pone en la TV (una serie abre allá su ficha).
struct VoiceChoices: View {
    let choices: [OrbitalRemote.VoiceChoice]
    let action: (OrbitalRemote.VoiceChoice) -> Void
    @State private var taps = 0

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            ForEach(choices) { choice in
                Button { taps += 1; action(choice) } label: {
                    HStack(spacing: DS.Space.s3) {
                        PosterView(url: choice.image, title: choice.title, aspect: DS.Poster.aspect).frame(width: DS.Size.thumbSmall)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: choice.title).recipe(.cardTitle).lineLimit(1)
                            if !choice.subtitle.isEmpty { Text(verbatim: choice.subtitle).recipe(.footnote, color: DS.textMuted).lineLimit(1) }
                        }
                        Spacer(minLength: DS.Space.s2)
                        Image(systemName: "play.fill").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
                    }
                    .padding(DS.Space.s2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: [choice.title, choice.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")))
                .accessibilityHint(Text("Ponerla en la TV"))
            }
        }
        .sensoryFeedback(.selection, trigger: taps)
    }
}

/// El volumen de la TV en el control: silencio, −, la barra con el nivel y +. Sin el dato de la consola, la barra se
/// queda vacía y los botones funcionan igual.
struct VolumeControl: View {
    let level: Int?
    let muted: Bool
    let down: () -> Void
    let up: () -> Void
    let mute: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Button(action: mute) { Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: DS.Size.touchTarget * 3 / 4) }
                .accessibilityLabel(muted ? Text("Quitar silencio") : Text("Silencio"))
            Button(action: down) { Image(systemName: "minus") }.accessibilityLabel(Text("Bajar volumen"))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill)
                    Capsule().fill(muted ? DS.textFaint : DS.text).frame(width: geo.size.width * CGFloat(level ?? 0) / 100)
                }
            }
            .frame(height: DS.Remote.volumeBar)
            .accessibilityHidden(true)
            Button(action: up) { Image(systemName: "plus") }.accessibilityLabel(Text("Subir volumen"))
        }
        .font(DS.TextRecipe.cardTitle.font.weight(.semibold))
        .foregroundStyle(DS.text)
        .buttonStyle(.plain)
        // Como las teclas y «Dile a Orbital»: el mismo relleno, esquinas y alto (antes era una cápsula de vidrio, distinta).
        .padding(.horizontal, DS.Space.s4).frame(minHeight: DS.Remote.keyHeight)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .sensoryFeedback(.selection, trigger: level)
        .accessibilityElement(children: .contain)
        .accessibilityValue(level.map { Text("\($0) %") } ?? Text(""))
    }
}

// MARK: sustos (Where's The Jump)

/// La línea de tiempo de lo que suena con sus sustos marcados: una raya por susto (los fuertes, más altos y en rojo), lo que
/// llevas relleno y un punto donde vas. Sin sustos, una barra de avance normal.
struct ScareTimeline: View {
    let position: Double
    let duration: Double
    var scares: [JumpScare] = []

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = { (t: Double) in duration > 0 ? CGFloat(min(1, max(0, t / duration))) * w : 0 }
            ZStack(alignment: .leading) {
                Capsule().fill(DS.fill).frame(height: DS.Remote.timelineBar)
                Capsule().fill(DS.text).frame(width: x(position), height: DS.Remote.timelineBar)
                ForEach(Array(scares.enumerated()), id: \.offset) { _, scare in
                    Capsule()
                        .fill(scare.time <= position ? DS.textFaint : (scare.major ? DS.danger : DS.warning))
                        .frame(width: DS.Remote.scareMarkWidth, height: scare.major ? DS.Remote.scareMarkMajor : DS.Remote.scareMark)
                        .offset(x: x(scare.time) - DS.Remote.scareMarkWidth / 2)
                }
                Circle().fill(DS.paper).frame(width: DS.Remote.playhead, height: DS.Remote.playhead)
                    .shadow(color: DS.scrimStrong, radius: DS.Space.s1)
                    .offset(x: x(position) - DS.Remote.playhead / 2)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: DS.Remote.scareMarkMajor)
        .accessibilityElement()
        .accessibilityLabel(Text("Línea de tiempo"))
        .accessibilityValue(scares.isEmpty ? Text("") : Text("\(scares.filter { $0.time > position }.count) sustos por delante"))
    }
}

/// El mapa de sustos de la película que suena en la TV: la línea de tiempo, cuánto falta para el siguiente (y si es fuerte),
/// cuántos quedan y «Avisarme» (vibra unos segundos antes de cada uno, con el control abierto). Sin spoilers: no dice qué pasa.
struct ScarePanel: View {
    let now: OrbitalRemote.NowPlaying
    let fetchedAt: Date
    let scares: [JumpScare]
    @AppStorage("scare-warnings") private var warn = true

    var body: some View {
        TimelineView(.periodic(from: fetchedAt, by: DS.Remote.scareTick)) { context in
            let position = now.paused ? now.position : min(now.duration, now.position + max(0, context.date.timeIntervalSince(fetchedAt)))
            ScareStatus(position: position, duration: now.duration, scares: scares, warn: $warn)
        }
    }
}

private struct ScareStatus: View {
    let position: Double
    let duration: Double
    let scares: [JumpScare]
    @Binding var warn: Bool

    var body: some View {
        let next = scares.first { $0.time > position }
        let left = scares.filter { $0.time > position }
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Label("Sustos", systemImage: "bolt.heart").recipe(.cardTitle)
                Spacer()
                Text("\(left.count) por delante · \(left.filter(\.major).count) fuertes").recipe(.caption, color: DS.textMuted)
            }
            ScareTimeline(position: position, duration: duration, scares: scares)
            HStack(spacing: DS.Space.s3) {
                if let next {
                    let seconds = Int(next.time - position)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: clock(seconds)).recipe(.title, color: seconds <= Int(DS.Remote.scareLead) ? DS.danger : DS.text).monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        (next.major ? Text("para el siguiente · fuerte") : Text("para el siguiente · leve")).recipe(.caption, color: DS.textMuted)
                    }
                } else {
                    Label("Ya no quedan sustos", systemImage: "checkmark.circle").recipe(.secondary, color: DS.good)
                }
                Spacer()
                Toggle(isOn: $warn) { Label("Avisarme", systemImage: "iphone.radiowaves.left.and.right").recipe(.footnote, color: DS.text) }
                    .toggleStyle(.button).buttonStyle(.bordered).tint(warn ? DS.accent : DS.textMuted)
                    .accessibilityHint(Text("Vibra unos segundos antes de cada susto"))
            }
            Text("Tiempos de Where's The Jump").recipe(.caption, color: DS.textFaint)
        }
        .padding(DS.Space.s4)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))

    }

    private func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Solo las marcas de los sustos (sin barra), para ponerlas sobre la barra de avance del reproductor del iPhone.
struct ScareMarks: View {
    let position: Double
    let duration: Double
    let scares: [JumpScare]

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(scares.enumerated()), id: \.offset) { _, scare in
                Capsule()
                    .fill(scare.time <= position ? DS.textFaint : (scare.major ? DS.danger : DS.warning))
                    .frame(width: DS.Remote.scareMarkWidth, height: scare.major ? DS.Remote.scareMark : DS.Remote.scareMark / 2)
                    .position(x: duration > 0 ? CGFloat(min(1, scare.time / duration)) * geo.size.width : 0, y: geo.size.height / 2)
            }
        }
        .frame(height: DS.Remote.scareMark)
        .accessibilityElement()
        .accessibilityLabel(Text("Sustos"))
        .accessibilityValue(Text("\(scares.filter { $0.time > position }.count) sustos por delante"))
    }
}

extension View {
    /// Vibra unos segundos antes de cada susto (una vez por susto, aunque dos vengan juntos).
    func scareWarning(position: Double, scares: [JumpScare], enabled: Bool) -> some View {
        modifier(ScareWarning(position: position, scares: scares, enabled: enabled))
    }
}

private struct ScareWarning: ViewModifier {
    let position: Double
    let scares: [JumpScare]
    let enabled: Bool
    @State private var warned: Double?
    @State private var buzz = 0

    func body(content: Content) -> some View {
        // El siguiente que está a menos de `scareLead` segundos: su tiempo identifica el aviso (dos seguidos vibran dos veces).
        let soon = scares.first { $0.time > position && $0.time - position <= DS.Remote.scareLead }?.time
        content
            .onChange(of: soon) { _, time in if enabled, let time, time != warned { warned = time; buzz += 1 } }
            .sensoryFeedback(.warning, trigger: buzz)
    }
}

/// El aviso de los sustos con el control abierto, se vea o no el panel: sigue el avance (interpolado entre sondeos) y vibra.
struct ScareWatcher: View {
    let now: OrbitalRemote.NowPlaying
    let fetchedAt: Date
    let scares: [JumpScare]
    @AppStorage("scare-warnings") private var warn = true

    var body: some View {
        TimelineView(.periodic(from: fetchedAt, by: DS.Remote.scareTick)) { context in
            let position = now.paused ? now.position : min(now.duration, now.position + max(0, context.date.timeIntervalSince(fetchedAt)))
            Color.clear.scareWarning(position: position, scares: scares, enabled: warn && !now.paused)
        }
        .accessibilityHidden(true)
    }
}
