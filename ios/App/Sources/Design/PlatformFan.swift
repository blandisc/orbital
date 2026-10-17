import SwiftUI

/// Una plataforma en «Tus plataformas» (Para ti): su top 3 en abanico, «TOP» arriba y su logo abajo con el brillo de su
/// color. Tocarla abre sus rankings.
struct PlatformFanCard: View {
    let name: String
    let logo: String?
    /// Los pósters del 1, 2 y 3 (en ese orden).
    let posters: [String?]
    let tint: Color

    var body: some View {
        FanCard(name: name, eyebrow: Text("TOP"), posters: posters, tint: tint) {
            PlatformLogoTile(url: logo, name: name, size: DS.PlatformFan.logo, radius: DS.PlatformFan.logoRadius, tint: tint, glow: DS.PlatformFan.glow)
        }
        .accessibilityLabel(Text("Rankings de \(name)"))
    }
}

/// La tarjeta en abanico (plataformas y colecciones): tres pósters, el brillo de su color desde abajo y, al frente abajo,
/// su emblema (el logo de la plataforma, la estatuilla del premio, el sello de Trakt).
struct FanCard<Emblem: View>: View {
    let name: String
    var eyebrow: Text?
    /// Los pósters del 1, 2 y 3 (en ese orden).
    let posters: [String?]
    let tint: Color
    @ViewBuilder var emblem: () -> Emblem

    var body: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(colors: [tint.opacity(DS.PlatformFan.tintTop), .clear], center: .bottom, startRadius: 0,
                           endRadius: DS.PlatformFan.height)
            if let eyebrow { eyebrow.recipe(.eyebrow, color: tint).padding(DS.Space.s3) }
            fan.frame(maxWidth: .infinity)
            VStack { Spacer(); emblem().padding(.bottom, DS.Space.s3) }.frame(maxWidth: .infinity)
        }
        .frame(width: DS.PlatformFan.width, height: DS.PlatformFan.height)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.PlatformFan.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.PlatformFan.radius, style: .continuous).stroke(tint.opacity(DS.PlatformFan.tintEdge)))
        // Peso: una sombra de su color, como si flotara sobre el piso.
        .shadow(color: tint.opacity(DS.Collections.weightTint), radius: DS.Collections.weight, y: DS.Collections.weightY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
    }

    /// El 2 a la izquierda, el 3 a la derecha y el 1 al frente.
    private var fan: some View {
        let poster = DS.PlatformFan.poster
        return ZStack {
            card(1).rotationEffect(.degrees(-DS.PlatformFan.angle), anchor: .bottom).offset(x: -DS.PlatformFan.spread)
            card(2).rotationEffect(.degrees(DS.PlatformFan.angle), anchor: .bottom).offset(x: DS.PlatformFan.spread)
            card(0).offset(y: -DS.PlatformFan.lift)
        }
        .frame(width: poster, height: poster / DS.Poster.aspect)
        .padding(.top, DS.PlatformFan.posterTop)
    }

    @ViewBuilder private func card(_ index: Int) -> some View {
        PosterView(url: index < posters.count ? posters[index] : nil, title: name).frame(width: DS.PlatformFan.poster)
            .shadow(color: DS.scrimStrong, radius: DS.Space.s2, y: DS.Space.s1)
    }
}

/// El logo cuadrado de una plataforma con el brillo de su color (la tarjeta en abanico y la página de rankings).
struct PlatformLogoTile: View {
    let url: String?
    let name: String
    let size: CGFloat
    let radius: CGFloat
    let tint: Color
    let glow: CGFloat

    var body: some View {
        Group {
            if let link = url.flatMap(URL.init(string:)) {
                RemoteImage(url: link, maxPoints: size) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: initial
                    }
                }
            } else { initial }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: tint, radius: glow)
        .accessibilityHidden(true)
    }

    /// Sin logo: la inicial sobre su color.
    private var initial: some View {
        Text(verbatim: String(name.prefix(1))).recipe(.cardTitle).frame(maxWidth: .infinity, maxHeight: .infinity).background(tint)
    }
}
