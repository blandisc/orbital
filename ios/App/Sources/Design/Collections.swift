import SwiftUI
import OrbitalCore

/// Una colección (Para ti › Listas): la tarjeta en abanico con su emblema al frente y, debajo, su nombre y su dato
/// («Óscar · Mejor película», «Para ver en pareja · 24 títulos»).
struct CollectionCard<Emblem: View>: View {
    let title: Text
    let detail: Text
    let name: String
    let posters: [String?]
    let tint: Color
    @ViewBuilder var emblem: () -> Emblem

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            FanCard(name: name, posters: posters, tint: tint, emblem: emblem)
            VStack(alignment: .leading, spacing: 0) {
                title.recipe(.cardTitle).lineLimit(1)
                detail.recipe(.caption).lineLimit(1)
            }
            .padding(.horizontal, DS.Space.s1)
        }
        .frame(width: DS.PlatformFan.width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// La estatuilla de un premio, recortada, con el halo de su color (el emblema de su colección).
struct AwardEmblem: View {
    let id: String
    var body: some View {
        Image("Awards/" + id).resizable().scaledToFit()
            .frame(height: DS.Collections.emblem)
            .shadow(color: DS.Collections.tint(id), radius: DS.Collections.glow)
            .accessibilityHidden(true)
    }
}

/// El sello de Trakt (el emblema de tus listas).
struct TraktEmblem: View {
    var body: some View {
        Image(systemName: "checkmark").font(DS.TextRecipe.section.font.weight(.heavy)).foregroundStyle(DS.paper)
            .frame(width: DS.PlatformFan.logo, height: DS.PlatformFan.logo)
            .background(DS.RatingBrand.trakt, in: Circle())
            .shadow(color: DS.RatingBrand.trakt, radius: DS.PlatformFan.glow)
            .accessibilityHidden(true)
    }
}

/// Un premio en Colecciones: su estatuilla al frente, sobre sus tres ganadores más recientes, y su nombre debajo.
struct AwardCard: View {
    let award: AwardCollection

    var body: some View {
        CollectionCard(title: AwardNames.title(award.id), detail: AwardNames.category(award.id), name: award.id,
                       posters: award.suggestions.prefix(3).map { Optional($0.poster) }, tint: DS.Collections.tint(award.id)) {
            AwardEmblem(id: award.id)
        }
    }
}

/// Cómo se llama cada premio y qué categoría es la colección.
enum AwardNames {
    static func title(_ id: String) -> Text {
        switch id {
        case "oscar": Text("Óscar"); case "emmy": Text("Emmy"); case "globe": Text("Globos de Oro"); case "palm": Text("Cannes")
        case "bafta": Text(verbatim: "BAFTA"); case "ariel": Text("Ariel"); default: Text(verbatim: id)
        }
    }

    static func category(_ id: String) -> Text {
        switch id {
        case "emmy": Text("Mejor serie de drama"); case "globe": Text("Mejor película dramática"); case "palm": Text("Palma de Oro")
        case "ariel": Text("Cine mexicano"); default: Text("Mejor película")
        }
    }
}
