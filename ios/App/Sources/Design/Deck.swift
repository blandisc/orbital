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
            let value = reduceMotion ? 0 : phase.value
            let distance = abs(value)
            return content
                .scaleEffect(1 - distance * DS.Deck.sideShrink)
                .blur(radius: distance * DS.Deck.sideBlur)
                .brightness(-distance * DS.Deck.sideDim)
                .rotation3DEffect(.degrees(style == .coverflow ? -value * DS.Deck.coverflowAngle : 0), axis: (x: 0, y: 1, z: 0),
                                  perspective: DS.Deck.perspective)
                .rotationEffect(.degrees(style == .fan ? value * DS.Deck.fanAngle : 0), anchor: .bottom)
                .offset(y: style == .fan ? distance * DS.Deck.fanDrop : 0)
        }
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
        .overlay(alignment: .topTrailing) { badge }
        .overlay { if timeStyle == .edge, let progress { EdgeProgress(fraction: progress) } }
        .clipShape(RoundedRectangle(cornerRadius: DS.Deck.radius, style: .continuous))
        .shadow(color: DS.scrimStrong, radius: DS.Deck.shadow, y: DS.Deck.shadowY)
    }

    @ViewBuilder private var badge: some View {
        if minutesLeft > 0, let progress {
            switch timeStyle {
            case .pill: TimePill(minutes: minutesLeft, fraction: progress).padding(DS.Space.s3)
            case .edge: MinutesText(minutes: minutesLeft).padding(DS.Space.s3)
            case .arc: OrbitArc(minutes: minutesLeft, fraction: progress)
            case .fill: EmptyView()
            }
        }
    }
}

/// «32 min» en la tarjeta, en una cápsula de vidrio (se lee aunque el arte sea claro).
private struct MinutesText: View {
    let minutes: Int
    var body: some View {
        Text("\(minutes) min").recipe(.footnote, color: DS.accent).fontWeight(.bold)
            .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s1)
            .glassEffect(.regular, in: Capsule())
            .onArt()
    }
}

/// Píldora de vidrio con los minutos y una barrita de avance.
private struct TimePill: View {
    let minutes: Int
    let fraction: Double
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("\(minutes) min").recipe(.footnote).fontWeight(.bold)
            DSProgress(fraction: fraction).frame(width: DS.Deck.pillBar)
        }
        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .onArt()
        .accessibilityElement(children: .combine)
    }
}

/// El borde de la tarjeta como barra de avance.
private struct EdgeProgress: View {
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
private struct OrbitArc: View {
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
                    Capsule().fill(DS.accent.opacity(DS.Deck.fillOpacity)).frame(width: geo.size.width * min(1, max(0, fraction)))
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
