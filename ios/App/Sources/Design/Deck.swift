import SwiftUI
import OrbitalModels

// Tu avatar y el ícono de la app (Ajustes). El carrusel 3D de Inicio (`DeckCard`) se quitó con la portada nueva (30 oct 2026).

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
            UIApplication.shared.setAlternateIconName(name) { error in if error == nil { Task { @MainActor in current = name } } }
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
