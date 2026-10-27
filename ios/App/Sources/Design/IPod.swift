import SwiftUI

// «Modo iPod»: el reproductor vertical con la cara de un iPod Classic. Por dentro es el mismo reproductor; cambian la cara y
// los controles (la rueda). Se prende y se apaga en «⋯ › Modo iPod» (blanco, negro o no) y se queda para la próxima.

/// La cara del iPod: blanca o negra (la negra es todo oscuro, para ver de noche).
enum IPodFace: String {
    case white, black

    /// «⋯ › Modo iPod» va de no → blanco → negro → no.
    static func next(after stored: String) -> String {
        switch IPodFace(rawValue: stored) {
        case nil: IPodFace.white.rawValue
        case .white: IPodFace.black.rawValue
        case .black: ""
        }
    }
    static func name(_ stored: String) -> String {
        switch IPodFace(rawValue: stored) {
        case nil: "No"
        case .white: "Blanco"
        case .black: "Negro"
        }
    }

    var body: LinearGradient {
        let colors = self == .white ? [DS.IPod.whiteTop, DS.IPod.whiteBottom] : [DS.IPod.blackTop, DS.IPod.blackBottom]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    var wheel: LinearGradient {
        let colors = self == .white ? [DS.IPod.wheelWhiteTop, DS.IPod.wheelWhiteBottom] : [DS.IPod.wheelBlackTop, DS.IPod.wheelBlackBottom]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    var center: LinearGradient {
        let colors = self == .white ? [DS.IPod.centerWhiteTop, DS.IPod.centerWhiteBottom] : [DS.IPod.centerBlackTop, DS.IPod.centerBlackBottom]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    var edge: Color { self == .white ? DS.IPod.wheelWhiteEdge : DS.IPod.wheelBlackEdge }
    var label: Color { self == .white ? DS.IPod.labelWhite : DS.IPod.labelBlack }
    /// Los botones de arriba (✕, AirPlay, «⋯») se pintan para la caja: oscuros sobre la blanca, claros sobre la negra.
    var scheme: ColorScheme { self == .white ? .light : .dark }
    // La pantalla: clara en el blanco; oscura en el negro.
    var lcd: Color { self == .white ? DS.IPod.lcd : DS.IPod.lcdDark }
    var lcdText: Color { self == .white ? DS.IPod.lcdText : DS.IPod.lcdDarkText }
    var lcdMuted: Color { self == .white ? DS.IPod.lcdMuted : DS.IPod.lcdDarkMuted }
    var bar: LinearGradient {
        let colors = self == .white ? [DS.IPod.barTop, DS.IPod.barBottom] : [DS.IPod.barDarkTop, DS.IPod.barDarkBottom]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    var barLine: Color { self == .white ? DS.IPod.barLine : DS.IPod.barDarkLine }
}

/// Dónde va cada parte, dentro del área segura: arriba los botones de siempre, la pantalla (con el video en `video`) y la rueda
/// centrada en lo que queda. El hueco del video toma la forma del video (`aspect`): uno en 4:3, como Los Simpson, llena
/// la pantalla a lo ancho sin franjas a los lados. Crece hasta donde la rueda aún cabe cómoda; de ahí en adelante, el video
/// se ajusta dentro (franjas arriba y abajo).
struct IPodLayout {
    let screen: CGRect, video: CGRect, wheel: CGRect

    init(in size: CGSize, aspect: Double = Double(DS.Poster.stillAspect)) {
        let top = DS.Space.s2 * 2 + DS.Size.touchTarget
        let width = max(0, size.width - DS.IPod.inset * 2)
        let inner = max(0, width - DS.IPod.bezel * 2)
        let chrome = DS.IPod.bezel * 2 + DS.IPod.statusHeight + DS.IPod.infoHeight
        let roomy = size.height - top - chrome - DS.Space.s4 * 2 - size.width * DS.IPod.wheelMinShare
        let videoHeight = max(0, min(inner / CGFloat(max(aspect, 0.1)), max(roomy, inner / DS.Poster.stillAspect)))
        let height = DS.IPod.bezel * 2 + DS.IPod.statusHeight + videoHeight + DS.IPod.infoHeight
        screen = CGRect(x: DS.IPod.inset, y: top, width: width, height: height)
        video = CGRect(x: screen.minX + DS.IPod.bezel, y: screen.minY + DS.IPod.bezel + DS.IPod.statusHeight, width: inner, height: videoHeight)
        let free = CGRect(x: 0, y: screen.maxY + DS.Space.s4, width: size.width, height: max(0, size.height - screen.maxY - DS.Space.s4 * 2))
        let diameter = min(size.width * DS.IPod.wheelShare, free.height)
        wheel = CGRect(x: free.midX - diameter / 2, y: free.midY - diameter / 2, width: diameter, height: diameter)
    }
}

/// La pantalla del iPod: el marco negro, la barra «Reproduciendo», el hueco del video (el reproductor lo pone ahí), el nombre,
/// la versión o el episodio y el avance azul con las horas.
struct IPodScreen: View {
    let face: IPodFace
    let status: LocalizedStringKey
    let playing: Bool
    let title: String
    let detail: String
    let position: Double
    let duration: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: playing ? "play.fill" : "pause.fill").font(DS.TextRecipe.caption.font.weight(.bold))
                Text(status).font(DS.TextRecipe.footnote.font.weight(.bold)).frame(maxWidth: .infinity)
                Image(systemName: "play.fill").font(DS.TextRecipe.caption.font.weight(.bold)).hidden()   // equilibra el de la izquierda
            }
            .foregroundStyle(face.lcdText)
            .padding(.horizontal, DS.Space.s3)
            .frame(height: DS.IPod.statusHeight)
            .background(face.bar)
            .overlay(alignment: .bottom) { Rectangle().fill(face.barLine).frame(height: DS.IPod.line) }
            Color.clear.frame(maxHeight: .infinity)   // el video
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: title).recipe(.cardTitle, color: face.lcdText).lineLimit(1)
                if !detail.isEmpty { Text(verbatim: detail).recipe(.caption, color: face.lcdMuted).lineLimit(1) }
                IPodProgress(face: face, fraction: duration > 0 ? position / duration : 0).padding(.top, DS.Space.s1)
                HStack {
                    Text(verbatim: Self.clock(position))
                    Spacer()
                    Text(verbatim: "−" + Self.clock(max(0, duration - position)))
                }
                .font(DS.TextRecipe.data.font.weight(.semibold)).foregroundStyle(face.lcdText)
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: DS.IPod.infoHeight, maxHeight: DS.IPod.infoHeight, alignment: .leading)
            .background(face.lcd)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.IPod.lcdRadius, style: .continuous))
        .padding(DS.IPod.bezel)
        .background(RoundedRectangle(cornerRadius: DS.IPod.bezelRadius, style: .continuous).strokeBorder(DS.IPod.bezelColor, lineWidth: DS.IPod.bezel))
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

/// El avance del iPod: la barra con brillo y lo visto en azul.
struct IPodProgress: View {
    let face: IPodFace
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(face.bar)
                Capsule().fill(LinearGradient(colors: [DS.IPod.fillTop, DS.IPod.fillBottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
            .overlay(Capsule().strokeBorder(face.barLine, lineWidth: DS.IPod.line))
        }
        .frame(height: DS.IPod.progressHeight)
        .accessibilityHidden(true)
    }
}

/// La rueda: MENU arriba (tocar cierra, mantener bloquea), ⏮ y ⏭ (−10 / +10 s), ▶❚❚ abajo y el botón del centro
/// («Audio y subtítulos»). Girar con el dedo busca: cada muesca 10 s, con un clic que se siente (rápido, de a minuto).
struct IPodWheel: View {
    let face: IPodFace
    let menu: () -> Void
    let hold: () -> Void
    let back: () -> Void
    let forward: () -> Void
    let playPause: () -> Void
    let center: () -> Void
    /// Una muesca: +1 en el sentido del reloj (adelante), −1 al revés.
    let turn: (Int) -> Void
    /// Soltó la rueda: ahí se va al tiempo elegido.
    let turned: () -> Void

    @State private var lastAngle: Double?
    @State private var travelled: Double = 0
    @State private var clicks = 0
    @State private var held = false

    var body: some View {
        GeometryReader { geo in
            let diameter = min(geo.size.width, geo.size.height)
            let mid = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let reach = diameter * DS.IPod.labelReach
            ZStack {
                Circle().fill(face.wheel)
                    .overlay(Circle().strokeBorder(face.edge, lineWidth: DS.IPod.line))
                    .frame(width: diameter, height: diameter).position(mid)
                    .accessibilityHidden(true)
                // Un botón (con un toque suelto, el giro de la rueda se lo comía); mantenerlo bloquea y el toque de
                // soltar ya no cierra.
                Button { if held { held = false } else { click(menu) } } label: {
                    Text(verbatim: "MENU").font(DS.TextRecipe.footnote.font.weight(.bold)).tracking(DS.IPod.menuTracking)
                        .foregroundStyle(face.label)
                        .frame(width: DS.Size.touchTarget * 2, height: DS.Size.touchTarget).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture(minimumDuration: DS.Timing.longPressDelay).onEnded { _ in held = true; click(hold) })
                    .accessibilityLabel(Text("Menú: cerrar el reproductor"))
                    .accessibilityAction(named: Text("Bloquear pantalla")) { hold() }
                    .accessibilityIdentifier("ipod-menu")
                    .position(x: mid.x, y: mid.y - diameter / 2 + reach)
                key("backward.end.alt.fill", "Atrás 10 segundos", back).position(x: mid.x - diameter / 2 + reach, y: mid.y)
                key("forward.end.alt.fill", "Adelante 10 segundos", forward).position(x: mid.x + diameter / 2 - reach, y: mid.y)
                key("playpause.fill", "Reproducir o pausar", playPause).accessibilityIdentifier("ipod-play")
                    .position(x: mid.x, y: mid.y + diameter / 2 - reach)
                Button { click(center) } label: {
                    Circle().fill(face.center).overlay(Circle().strokeBorder(face.edge, lineWidth: DS.IPod.line))
                }
                .buttonStyle(.plain)
                .frame(width: diameter * DS.IPod.centerShare, height: diameter * DS.IPod.centerShare)
                .accessibilityLabel(Text("Audio y subtítulos"))
                .accessibilityIdentifier("ipod-center")
                .position(mid)
            }
            // Girar: solo desde el aro (no desde el botón del centro). Los toques siguen siendo de los botones: el giro
            // empieza cuando el dedo ya se movió.
            .highPriorityGesture(DragGesture(minimumDistance: DS.Gesture.axisThreshold)
                .onChanged { value in
                    let start = value.startLocation
                    guard hypot(start.x - mid.x, start.y - mid.y) > diameter * DS.IPod.centerShare / 2 else { return }
                    let angle = atan2(Double(value.location.y - mid.y), Double(value.location.x - mid.x))
                    if let last = lastAngle {
                        var delta = angle - last
                        if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
                        travelled += delta
                        let notch = DS.IPod.notchDegrees * .pi / 180
                        while travelled >= notch { travelled -= notch; clicks += 1; turn(1) }
                        while travelled <= -notch { travelled += notch; clicks += 1; turn(-1) }
                    }
                    lastAngle = angle
                }
                .onEnded { _ in
                    if lastAngle != nil { turned() }
                    lastAngle = nil; travelled = 0
                })
        }
        .sensoryFeedback(.selection, trigger: clicks)
        .accessibilityElement(children: .contain)
    }

    private func click(_ action: () -> Void) { clicks += 1; action() }

    private func key(_ symbol: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button { click(action) } label: {
            Image(systemName: symbol).font(DS.TextRecipe.body.font.weight(.bold)).foregroundStyle(face.label)
                .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
