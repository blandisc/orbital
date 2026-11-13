import SwiftUI
import OrbitalCore

// El control completo de tu Orbital (la hoja de «Viendo en la TV» estirada hacia arriba): piezas del catálogo.

/// El pad táctil, como el del control del Apple TV: deslizar = flechas (una por cada `DS.Remote.swipeStep`, con toque
/// háptico; al seguir deslizando se repite), tocar = A (elegir). Se usa sin mirar.
struct TouchPad: View {
    /// Lo que hace tocar (la A) en la pantalla de la TV ahora («Ver», «Escribir», «Jugar»…), de su leyenda; nil: «A».
    var selectLabel: String?
    let onAction: (OrbitalRemote.InputAction) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var origin: CGPoint?
    @State private var gestureStart: CGPoint?
    @State private var moved = false
    @State private var touch: CGPoint?
    @State private var ticks = 0
    /// La flecha que se acaba de mandar: se enciende un instante en su orilla (sabes a dónde fue sin mirar la TV).
    @State private var flash: OrbitalRemote.InputAction?
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
            .frame(minHeight: DS.Remote.padHeightFitted)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            .gesture(padGesture)
            .dsFeedback(.selection, trigger: ticks)
            .modifier(PadAccessibility(selectLabel: selectLabel, onAction: onAction))
    }

    /// En partes: el compilador de la CI (Xcode 26.3) no alcanzaba a revisar el pad de una vez.
    private var padGesture: some Gesture {
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
    }

    private func fire(_ action: OrbitalRemote.InputAction) {
        ticks += 1
        onAction(action)
        flash = action
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(DesignTokens.Motion.fast))
            if flash == action { withAnimation(DS.Motion.fade) { flash = nil } }
        }
    }

    /// Las flechas apenas marcadas en las orillas y, al centro, qué hace tocar.
    private var hints: some View {
        ZStack {
            VStack { chevron("chevron.up", .up); Spacer(); chevron("chevron.down", .down) }
            HStack { chevron("chevron.left", .left); Spacer(); chevron("chevron.right", .right) }
            VStack(spacing: DS.Space.s1) {
                // Dice lo que va a pasar al tocar, como el pie de la TV; sin leyenda, «Elegir» (no la letra del mando: A16).
                (selectLabel.map { Text(verbatim: $0) } ?? Text("Elegir")).recipe(.title, color: DS.textMuted).lineLimit(1).contentTransition(.opacity)
                // Con letra de accesibilidad el pad no da para dos renglones entre las flechas: queda solo lo que hace tocar.
                if !typeSize.isAccessibilitySize {
                    Text("Desliza para moverte").recipe(.caption, color: DS.textFaint)
                        .lineLimit(1)
                }
            }
            .minimumScaleFactor(DS.Size.statScale)
            // Entre las flechas, sin encimarse: con letra de accesibilidad «Reproducir» tapaba las de arriba y abajo.
            .padding(.horizontal, DS.Space.s6).padding(.vertical, DS.Space.s5)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .padding(DS.Space.s4)
        .allowsHitTesting(false)
    }

    private func chevron(_ name: String, _ direction: OrbitalRemote.InputAction) -> some View {
        Image(systemName: name).font(DS.TextRecipe.labelLarge.font).foregroundStyle(flash == direction ? DS.text : DS.textFaint)
            .scaleEffect(flash == direction && !reduceMotion ? DS.Remote.arrowFlash : 1)
    }
}

/// Una tecla de la consola en el control completo: ícono y nombre (lo que hace en la pantalla de la TV, si la consola lo dice).
/// Del mismo tamaño todas. Sin la letra del mando (A, B, LB…): el iPhone no es un mando (A16, 10 nov 2026).
struct RemoteKey: View {
    let symbol: String
    let title: Text
    /// La TV dice que en esta pantalla no hace nada: se atenúa, sin moverse de lugar.
    var idle = false
    /// Mantener el dedo (como en el control del Apple TV: mantener «Atrás» lleva al inicio).
    var longPress: (() -> Void)?
    let action: () -> Void
    @State private var taps = 0
    @State private var held = 0
    /// Cuándo se disparó «mantener»: el toque que llega justo después (al soltar) no se manda; uno de verdad, luego, sí.
    @State private var heldAt: Date?
    /// El dedo encima: la tecla se hunde un poco, como un botón de verdad.
    @GestureState private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View { bodyContent.pointerHover(.highlight) }
    @ViewBuilder private var bodyContent: some View {
        Button {
            // Si se mantuvo (su segunda acción ya se mandó), soltar no manda también la de un toque.
            if let held = heldAt, Date().timeIntervalSince(held) < DS.Remote.holdTapWindow { heldAt = nil; return }
            heldAt = nil
            taps += 1; action()
        } label: {
            // La tarjeta de acción del catálogo (aire parejo arriba y abajo, 11 nov 2026).
            ActionTileLabel(style: .key, title: title, symbol: symbol)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .opacity(idle ? DS.Opacity.disabled : 1)
                .scaleEffect(pressed && !reduceMotion ? DS.Remote.keyPress : 1)
                .animation(DS.Motion.snap(reduceMotion), value: pressed)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.text)
        .simultaneousGesture(DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = true })
        .dsFeedback(.impact(flexibility: .soft), trigger: taps)
        .simultaneousGesture(LongPressGesture(minimumDuration: DS.Remote.holdSeconds).onEnded { _ in
            guard let longPress else { return }
            held += 1; heldAt = Date(); longPress()
        })
        .accessibilityActions { if let longPress { Button("Mantener") { longPress() } } }
        .dsFeedback(.impact(weight: .heavy), trigger: held)
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
        .frame(minHeight: DS.Remote.keyHeightFitted)
        .dsCard(translucent: true)
    }
}

/// El volumen de la TV en el control: silencio, −, la barra con el nivel, el número y +. Sin el dato de la consola, la barra
/// se queda vacía y los botones funcionan igual.
/// Con un video abierto (`extra` no es nil) la barra es la cápsula de la TV acostada (V4-A, Fernando, 4 nov 2026): va de 0 a
/// 200, el 100 de Windows queda a dos tercios con su rayita y, de ahí para arriba, el Extra en ámbar con la palabra EXTRA
/// bajo el número (en minúsculas, la regla de mayúsculas del iPhone). Sin video la zona del Extra se ve punteada (V6-A);
/// con una consola de antes es la barra de siempre, de 0 a 100.
struct VolumeControl: View {
    let volume: OrbitalRemote.Volume?
    let down: () -> Void
    let up: () -> Void
    let mute: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var muted: Bool { volume?.muted ?? false }
    private var extraScale: Bool { volume?.extra != nil || volume?.extraMax != nil }
    private var top: CGFloat { volume?.extraMax.map(CGFloat.init) ?? DS.Remote.volumeTop }
    private var inExtra: Bool { (volume?.extra ?? 100) > 100 && !muted }
    /// Hasta dónde llega lo normal (0…1 del ancho) y cuánto ocupa el Extra encima.
    private var normalShare: CGFloat {
        let level = CGFloat(volume?.level ?? 0) / 100
        return extraScale ? level * DS.Remote.volumeNormal : level
    }
    private var extraShare: CGFloat {
        guard inExtra, let extra = volume?.extra else { return 0 }
        return (1 - DS.Remote.volumeNormal) * CGFloat(extra - 100) / (top - 100)
    }

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Button(action: mute) { Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).contentShape(Rectangle()) }
                .accessibilityLabel(muted ? Text("Quitar silencio") : Text("Silencio"))
            // Mantener presionado repite (como los botones del iPhone).
            Button(action: down) { Image(systemName: "minus").frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).contentShape(Rectangle()) }
                .buttonRepeatBehavior(.enabled)
                .accessibilityLabel(Text("Bajar volumen"))
            bar
            number
            Button(action: up) { Image(systemName: "plus").frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).contentShape(Rectangle()) }
                .buttonRepeatBehavior(.enabled)
                .accessibilityLabel(Text("Subir volumen"))
        }
        .font(DS.TextRecipe.cardTitle.font)
        .foregroundStyle(DS.text)
        .buttonStyle(.plain)
        // Como las teclas y «Dile a Orbital»: el mismo relleno, esquinas y alto (antes era una cápsula de vidrio, distinta).
        .padding(.horizontal, DS.Space.s2).frame(minHeight: DS.Remote.keyHeightFitted)
        .dsCard(translucent: true)
        .dsFeedback(.selection, trigger: volume?.shown)
        .accessibilityElement(children: .contain)
        .accessibilityValue(volume.map { inExtra ? Text("\($0.shown) %, Extra") : Text("\($0.shown) %") } ?? Text(""))
    }

    private var bar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(DS.fill).frame(height: DS.Remote.volumeBar)
                Capsule().fill(muted ? DS.textFaint : DS.text).frame(width: w * normalShare, height: DS.Remote.volumeBar)
                // El Extra, en ámbar, sigue desde el 100 (como en la TV, encima de lo normal).
                Capsule().fill(DS.warning).frame(width: w * extraShare, height: DS.Remote.volumeBar).offset(x: w * DS.Remote.volumeNormal)
                if extraScale && volume?.extra == nil {   // sin video no hay Extra: su zona, punteada (V6-A)
                    let y = geo.size.height / 2
                    Path { $0.move(to: .init(x: w * DS.Remote.volumeNormal, y: y)); $0.addLine(to: .init(x: w, y: y)) }
                        .stroke(DS.textFaint, style: StrokeStyle(lineWidth: DS.Remote.volumeBar, dash: [DS.Remote.volumeDash]))
                }
                if extraScale {   // la rayita del 100: hasta aquí es lo normal
                    Capsule().fill(DS.warning.opacity(DS.Opacity.dimmed))
                        .frame(width: DS.Remote.volumeMarkWidth, height: DS.Remote.volumeMarkHeight)
                        .offset(x: w * DS.Remote.volumeNormal - DS.Remote.volumeMarkWidth / 2)
                }
            }
            .frame(height: geo.size.height)
            // La barra se desliza al nuevo nivel en vez de brincar.
            .animation(DS.Motion.snap(reduceMotion), value: volume)
        }
        .frame(height: DS.Remote.volumeMarkHeight)
        .accessibilityHidden(true)
    }

    /// El número de la TV («80», o «150» con «Extra» debajo en ámbar); con silencio, «—».
    private var number: some View {
        VStack(spacing: 0) {
            Text(verbatim: muted ? "—" : volume.map { "\($0.shown)" } ?? "")
                .recipe(.data, color: muted ? DS.textMuted : DS.text)
                .contentTransition(.numericText())
            if inExtra { Text("Extra").recipe(.badge, color: DS.warning).lineLimit(1).minimumScaleFactor(DS.Size.statScale) }
        }
        .frame(width: DS.Remote.volumeNumberWidth, alignment: .center)
        .animation(DS.Motion.snap(reduceMotion), value: volume?.shown)
        .accessibilityHidden(true)
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
                    .shadow(DS.Elevation.low.color(DS.scrimStrong))
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

/// La línea de tiempo del control que se arrastra (Fernando, 6 nov: «la barrita está para adelantar y atrasar»): al deslizar,
/// el punto sigue tu dedo y arriba dice a qué minuto vas; al soltar, la TV brinca ahí (`seek`). VoiceOver: subir o bajar
/// adelanta o atrasa 30 s.
struct RemoteScrubber: View {
    let position: Double
    let duration: Double
    var scares: [JumpScare] = []
    let seek: (Double) -> Void
    @State private var target: Double?

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            if let target {
                Text(verbatim: Self.clock(target) + " / " + Self.clock(duration)).recipe(.caption, color: DS.text).monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            GeometryReader { geo in
                ScareTimeline(position: target ?? position, duration: duration, scares: scares)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: DS.Remote.scrubSlop)
                        .onChanged { g in
                            guard duration > 0 else { return }
                            target = min(duration, max(0, Double(g.location.x / max(1, geo.size.width)) * duration))
                        }
                        .onEnded { _ in
                            if let target { seek(target) }
                            target = nil
                        })
            }
            .frame(height: DS.Size.touchTarget)
        }
        .dsFeedback(.selection, trigger: target.map { Int($0 / 60) })
        .accessibilityElement()
        .accessibilityLabel(Text("Línea de tiempo"))
        .accessibilityValue(Text(verbatim: Self.clock(position)))
        .accessibilityAdjustableAction { direction in
            let step = DS.Remote.scrubAccessibilityStep
            seek(min(duration, max(0, position + (direction == .increment ? step : -step))))
        }
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(max(0, seconds)), h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s % 60) : String(format: "%d:%02d", m, s % 60)
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
            let position = now.position(at: context.date, since: fetchedAt)
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
            let majorCount = left.filter(\.major).count
            // Sin línea base dentro de `ViewThatFits` (regla «ViewThatFits no se anida ni vive bajo alineación por línea base»).
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("Sustos", systemImage: "bolt.heart").recipe(.cardTitle).fixedSize()
                    Spacer()
                    summary(left: left.count, major: majorCount)
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Label("Sustos", systemImage: "bolt.heart").recipe(.cardTitle)
                    summary(left: left.count, major: majorCount)
                }
            }
            ScareTimeline(position: position, duration: duration, scares: scares)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s3) { countdown(next); Spacer(); warnToggle.fixedSize() }
                VStack(alignment: .leading, spacing: DS.Space.s2) { countdown(next); warnToggle }
            }
            Text("Tiempos de Where's The Jump").recipe(.caption, color: DS.textFaint)
        }
        .padding(DS.Space.s4)
        .dsCard(translucent: true)

    }

    /// «3 por delante · 1 fuerte»: con uno, en singular (decía «1 fuertes»).
    private func summary(left: Int, major: Int) -> some View {
        (major == 1 ? Text("\(Int(left)) por delante · 1 fuerte") : Text("\(Int(left)) por delante · \(Int(major)) fuertes")).recipe(.caption, color: DS.textMuted)
    }

    @ViewBuilder private func countdown(_ next: JumpScare?) -> some View {
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
    }

    private var warnToggle: some View {
        Toggle(isOn: $warn) { Label("Avisarme", systemImage: "iphone.radiowaves.left.and.right").recipe(.footnote, color: DS.text) }
            .toggleStyle(.button).buttonStyle(.bordered).tint(warn ? DS.accent : DS.textMuted)
            .accessibilityHint(Text("Vibra unos segundos antes de cada susto"))
    }

    private func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
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
            .onChange(of: soon, initial: true) { _, time in if enabled, let time, time != warned { warned = time; buzz += 1 } }
            .dsFeedback(.warning, trigger: buzz)
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
            let position = now.position(at: context.date, since: fetchedAt)
            Color.clear.scareWarning(position: position, scares: scares, enabled: warn && !now.paused)
        }
        .accessibilityHidden(true)
    }
}

extension OrbitalRemote.NowPlaying {
    /// Dónde va, contando lo que avanzó desde el último sondeo (en pausa, donde quedó). Sin duración conocida no se topa en 0.
    func position(at date: Date, since fetchedAt: Date) -> Double {
        guard !paused else { return position }
        let moved = position + max(0, date.timeIntervalSince(fetchedAt))
        return duration > 0 ? min(duration, moved) : moved
    }
}

/// Lo que dice VoiceOver del pad y sus cinco acciones (aparte: así el cuerpo del pad se revisa en partes).
private struct PadAccessibility: ViewModifier {
    let selectLabel: String?
    let onAction: (OrbitalRemote.InputAction) -> Void

    func body(content: Content) -> some View {
        content.accessibilityElement()
            .accessibilityLabel(Text("Pad de la TV"))
            .accessibilityHint(selectLabel.map { Text("Desliza para moverte; toca para \($0)") } ?? Text("Desliza para moverte; toca para elegir"))
            .accessibilityAction(named: Text("Arriba")) { onAction(.up) }
            .accessibilityAction(named: Text("Abajo")) { onAction(.down) }
            .accessibilityAction(named: Text("Izquierda")) { onAction(.left) }
            .accessibilityAction(named: Text("Derecha")) { onAction(.right) }
            .accessibilityAction { onAction(.select) }
    }
}
