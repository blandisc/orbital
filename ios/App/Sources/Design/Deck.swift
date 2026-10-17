import SwiftUI

// El carrusel de «Seguir viendo» en Inicio: la tarjeta del frente nítida y las que siguen a los lados, más chicas, oscuras
// y desenfocadas. Cómo se acomodan (coverflow o abanico) y cómo se dice cuánto falta (píldora, borde, botón u órbita) lo
// elige el usuario en Ajustes › Inicio.

/// Cómo se ven las tarjetas que siguen.
enum DeckStyle: String, CaseIterable {
    /// Las de los lados giran en 3D.
    case coverflow
    /// Las de los lados se inclinan desde abajo, como cartas abiertas.
    case fan
}

/// Cómo se dice cuánto falta en la tarjeta.
enum TimeStyle: String, CaseIterable {
    /// Una píldora de vidrio arriba a la derecha, con su barrita.
    case pill
    /// El borde de la tarjeta se va llenando.
    case edge
    /// El botón «Continuar» se llena con el avance y dice los minutos.
    case fill
    /// Una órbita en la esquina, con la luna donde vas.
    case arc
}

extension View {
    /// El efecto del carrusel: según qué tan lejos del centro está la tarjeta (`phase.value`, −1 a 1), se achica, se
    /// oscurece, se desenfoca y gira (coverflow) o se inclina (abanico). Con «Reducir movimiento», quietas.
    func deckTransition(_ style: DeckStyle, reduceMotion: Bool) -> some View {
        scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content.deckEffect(style, value: reduceMotion ? 0 : phase.value)
        }
    }

    /// El mismo efecto con la distancia dada (−1 a 1), para la vista previa de Ajustes (que se mueve sola, sin desplazarse).
    func deckEffect(_ style: DeckStyle, value: Double, blur: CGFloat = DS.Deck.sideBlur, drop: CGFloat = DS.Deck.fanDrop) -> some View {
        let distance = abs(value)
        return scaleEffect(1 - distance * DS.Deck.sideShrink)
            .blur(radius: distance * blur)
            .brightness(-distance * DS.Deck.sideDim)
            .rotation3DEffect(.degrees(style == .coverflow ? -value * DS.Deck.coverflowAngle : 0), axis: (x: 0, y: 1, z: 0),
                              perspective: DS.Deck.perspective)
            .rotationEffect(.degrees(style == .fan ? value * DS.Deck.fanAngle : 0), anchor: .bottom)
            .offset(y: style == .fan ? distance * drop : 0)
    }
}

extension VisualEffect {
    /// `View.deckEffect` dentro de `scrollTransition` (los mismos pasos, en su tipo).
    func deckEffect(_ style: DeckStyle, value: Double) -> some VisualEffect {
        let distance = abs(value)
        // El desenfoque se queda: además de alejar lo de los lados, dibuja cada tarjeta aparte antes de girarla; sin él, en
        // coverflow el vidrio de sus botones girado en 3D dejaba una capa con posición inválida y la app se cerraba.
        return scaleEffect(1 - distance * DS.Deck.sideShrink)
            .blur(radius: distance * DS.Deck.sideBlur)
            .brightness(-distance * DS.Deck.sideDim)
            .rotation3DEffect(.degrees(style == .coverflow ? -value * DS.Deck.coverflowAngle : 0), axis: (x: 0, y: 1, z: 0),
                              perspective: DS.Deck.perspective)
            .rotationEffect(.degrees(style == .fan ? value * DS.Deck.fanAngle : 0), anchor: .bottom)
            .offset(y: style == .fan ? distance * DS.Deck.fanDrop : 0)
    }
}

/// Una tarjeta del carrusel: el arte con su velo, el rótulo, el logo, los datos, las acciones y cuánto falta.
struct DeckCard<Actions: View>: View {
    let title: String
    let background: String?
    var logo: String?
    var eyebrow: Text?
    var data: [String] = []
    var progress: Double?
    var minutesLeft = 0
    var timeStyle: TimeStyle = .pill
    /// Abrir la ficha: VoiceOver con la acción «Ver ficha» sobre el nombre (la tarjeta, con su toque).
    var open: (() -> Void)?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterView(url: background, title: title, aspect: nil, bleed: true, maxPoints: DS.Image.bleed)
            LinearGradient(stops: [.init(color: .clear, location: DS.Deck.veilStart), .init(color: DS.scrimStrong, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if let eyebrow { Eyebrow(text: eyebrow, accent: true, onArt: true) }
                    TitleLogo(url: logo, title: title, size: .hero)
                    if !data.isEmpty { DataLine(parts: data, color: DS.onArtSecondary) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text("Ver ficha")) { open?() }
                actions()
            }
            .onArt()
            .padding(DS.Space.s4)
        }
        .frame(height: DS.Deck.height)
        .overlay { if minutesLeft > 0, let progress { TimeBadge(style: timeStyle, minutes: minutesLeft, fraction: progress) } }
        .clipShape(RoundedRectangle(cornerRadius: DS.Deck.radius, style: .continuous))
        .shadow(color: DS.scrimStrong, radius: DS.Deck.shadow, y: DS.Deck.shadowY)
    }
}

/// Cuánto falta, sobre la tarjeta, en el estilo elegido (el botón que se llena va en las acciones: aquí, nada).
struct TimeBadge: View {
    let style: TimeStyle
    let minutes: Int
    let fraction: Double

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            switch style {
            case .pill: TimePill(minutes: minutes, fraction: fraction).padding(DS.Space.s3)
            case .edge: EdgeProgress(fraction: fraction); MinutesText(minutes: minutes).padding(DS.Space.s3)
            case .arc: OrbitArc(minutes: minutes, fraction: fraction)
            case .fill: EmptyView()
            }
        }
    }
}

/// «32 min» en la tarjeta, en una cápsula de vidrio (se lee aunque el arte sea claro).
struct MinutesText: View {
    let minutes: Int
    var body: some View {
        Text("\(minutes) min").recipe(.footnote, color: DS.accent).fontWeight(.bold)
            .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s1)
            .glassEffect(.regular, in: Capsule())
            .onArt()
    }
}

/// Píldora de vidrio con los minutos y una barrita de avance.
struct TimePill: View {
    let minutes: Int
    let fraction: Double
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("\(minutes) min").recipe(.footnote).fontWeight(.bold)
            DSProgress(fraction: fraction).frame(width: DS.Deck.pillBar)
        }
        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
        // Velo oscuro, no vidrio ni material: girados en 3D por el coverflow dejaban una capa con posición inválida y la app se
        // cerraba al deslizar el carrusel.
        .background(DS.scrimStrong, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).strokeBorder(DS.hairline, lineWidth: DS.Size.hairline))
        .onArt()
        .accessibilityElement(children: .combine)
    }
}

/// El borde de la tarjeta como barra de avance.
struct EdgeProgress: View {
    let fraction: Double
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Deck.radius, style: .continuous).stroke(DS.track, lineWidth: DS.Deck.edgeStroke)
            RoundedRectangle(cornerRadius: DS.Deck.radius, style: .continuous).trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(DS.accent, style: StrokeStyle(lineWidth: DS.Deck.edgeStroke, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Una órbita en la esquina: su centro está en la esquina de arriba a la derecha y dentro de la tarjeta se ve su cuarto de
/// abajo a la izquierda; el avance recorre ese cuarto y la luna marca dónde vas. Los minutos, en la esquina.
struct OrbitArc: View {
    let minutes: Int
    let fraction: Double
    var body: some View {
        let done = min(1, max(0, fraction))
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle().trim(from: 0, to: DS.Deck.arcQuarter).stroke(DS.track, lineWidth: DS.Deck.arcStroke)
                Circle().trim(from: 0, to: DS.Deck.arcQuarter * done)
                    .stroke(DS.accent, style: StrokeStyle(lineWidth: DS.Deck.arcStroke, lineCap: .round))
                Circle().fill(DS.accent).frame(width: DS.Deck.moonDot, height: DS.Deck.moonDot)
                    .offset(x: DS.Deck.arcSize / 2)
                    .rotationEffect(.degrees(DS.Deck.arcQuarterDegrees * done))
            }
            .rotationEffect(.degrees(DS.Deck.arcQuarterDegrees))   // empieza abajo y va hacia la izquierda
            .frame(width: DS.Deck.arcSize, height: DS.Deck.arcSize)
            .offset(x: DS.Deck.arcSize / 2 - DS.Deck.arcInset, y: DS.Deck.arcInset - DS.Deck.arcSize / 2)
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: "\(minutes)").recipe(.cardTitle).fontWeight(.heavy)
                Text("min").recipe(.caption, color: DS.onArtSecondary)
            }
            .shadow(color: DS.scrim, radius: DS.Space.s1)
            .padding(DS.Space.s3)
        }
        .onArt()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Quedan \(minutes) min"))
    }
}

/// «Continuar» que se llena con el avance y dice cuánto falta (estilo de tiempo «botón»).
struct ProgressFillLabel: View {
    let text: Text
    let minutes: Int
    let fraction: Double
    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "play.fill")
            text.lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            if minutes > 0 { Text("\(minutes) min").fontWeight(.regular).opacity(DS.Deck.fillMinutesOpacity) }
        }
        .font(DS.TextRecipe.secondary.font.weight(.bold))
        .foregroundStyle(DS.backdropDeep)
        .padding(.horizontal, DS.Space.s4)
        .frame(width: DS.Deck.fillWidth, height: DS.Size.touchTarget)   // ancho fijo: junto al botón de la TV, en un renglón
        .background {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.paper)
                    if fraction > 0 { Capsule().fill(DS.accent.opacity(DS.Deck.fillOpacity)).frame(width: max(DS.Size.hairline, geo.size.width * min(1, fraction))) }
                }
            }
        }
        .clipShape(Capsule())
    }
}

/// Tu avatar (Assets › Avatars): un círculo con la ilustración.
struct AvatarImage: View {
    let id: String
    var size: CGFloat = DS.Avatar.toolbar

    /// Los que hay, en el orden del selector.
    static let all = ["planet", "moon", "eclipse", "orbit", "comet", "star", "phases", "sun", "rocket", "binary", "saturn", "horizon"]

    var body: some View {
        Image("Avatars/" + (Self.all.contains(id) ? id : Self.all[0]))
            .resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// Elegir tu avatar: la rejilla con todos; el elegido, con un anillo.
struct AvatarPicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Avatar.picker), spacing: DS.Space.s3)], spacing: DS.Space.s3) {
            ForEach(AvatarImage.all, id: \.self) { id in
                Button { selection = id } label: {
                    AvatarImage(id: id, size: DS.Avatar.picker)
                        .overlay(Circle().stroke(selection == id ? DS.accent : .clear, lineWidth: DS.Avatar.ring).padding(-DS.Avatar.ring * 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: id))
                .accessibilityAddTraits(selection == id ? .isSelected : [])
            }
        }
        .padding(.vertical, DS.Space.s2)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// El ícono de la app: el de siempre o Cielo nocturno (un ícono alterno de iOS; el sistema avisa al cambiarlo).
struct AppIconPicker: View {
    @State private var current = UIApplication.shared.alternateIconName

    var body: some View {
        HStack(spacing: DS.Space.s5) {
            option(nil, preview: "AppIconPreview/day", label: Text("Clásico"))
            option("AppIconNight", preview: "AppIconPreview/night", label: Text("Cielo nocturno"))
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.s2)
        .sensoryFeedback(.selection, trigger: current)
    }

    private func option(_ name: String?, preview: String, label: Text) -> some View {
        Button {
            guard current != name else { return }
            UIApplication.shared.setAlternateIconName(name) { error in if error == nil { current = name } }
        } label: {
            VStack(spacing: DS.Space.s2) {
                Image(preview).resizable().scaledToFit()
                    .frame(width: DS.Avatar.picker, height: DS.Avatar.picker)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Avatar.picker * DS.Avatar.iconCorner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.Avatar.picker * DS.Avatar.iconCorner, style: .continuous)
                        .stroke(current == name ? DS.accent : .clear, lineWidth: DS.Avatar.ring).padding(-DS.Avatar.ring * 2))
                label.recipe(.caption, color: current == name ? DS.text : DS.textMuted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current == name ? .isSelected : [])
    }
}
