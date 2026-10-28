import SwiftUI

// El carrusel de «En tendencia» en Inicio: la tarjeta del frente nítida y las que siguen a los lados, más chicas, oscuras,
// desenfocadas y giradas en 3D (coverflow).

extension View {
    /// El efecto del carrusel: según qué tan lejos del centro está la tarjeta (`phase.value`, −1 a 1), se achica, se
    /// oscurece, se desenfoca y gira en 3D. Con «Reducir movimiento», quietas.
    func deckTransition(reduceMotion: Bool) -> some View {
        scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content.deckEffect(value: reduceMotion ? 0 : phase.value)
        }
    }
}

extension VisualEffect {
    /// Lo que le pasa a una tarjeta a `value` lugares del centro (−1 a 1), dentro de `scrollTransition`.
    func deckEffect(value: Double) -> some VisualEffect {
        let distance = abs(value)
        // El desenfoque se queda: además de alejar lo de los lados, dibuja cada tarjeta aparte antes de girarla; sin él, en
        // coverflow el vidrio de sus botones girado en 3D dejaba una capa con posición inválida y la app se cerraba.
        return scaleEffect(1 - distance * DS.Deck.sideShrink)
            .blur(radius: distance * DS.Deck.sideBlur)
            .brightness(-distance * DS.Deck.sideDim)
            .rotation3DEffect(.degrees(-value * DS.Deck.coverflowAngle), axis: (x: 0, y: 1, z: 0), perspective: DS.Deck.perspective)
    }
}

/// Una tarjeta del carrusel: el arte con su velo, el rótulo, el logo, los datos y las acciones.
struct DeckCard<Actions: View>: View {
    let title: String
    let background: String?
    var logo: String?
    var eyebrow: Text?
    var data: [String] = []
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
        .clipShape(RoundedRectangle(cornerRadius: DS.Deck.radius, style: .continuous))
        .shadow(color: DS.scrimStrong, radius: DS.Deck.shadow, y: DS.Deck.shadowY)
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
