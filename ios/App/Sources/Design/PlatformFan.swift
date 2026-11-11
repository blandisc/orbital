import SwiftUI

/// Una plataforma en «Tus plataformas» (Para ti): su top 3 en abanico, «TOP» arriba y su logo abajo con el brillo de su
/// color. Tocarla abre sus rankings.
struct PlatformFanCard: View {
    let name: String
    let logo: String?
    /// Los pósters del 1, 2 y 3 (en ese orden).
    let posters: [String?]
    let tint: Color

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        FanCard(name: name, eyebrow: Text("Top"), posters: posters, tint: tint) {
            PlatformLogoTile(url: logo, name: name, size: DS.PlatformFan.logo, radius: DS.Radius.logo(DS.PlatformFan.logo), tint: tint, glow: DS.PlatformFan.glow)
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

    /// Sin póster (aún no llega, o sin TMDB): su forma en gris, como `ShelfSkeleton`. Antes el póster vacío escribía el
    /// nombre de la plataforma en su lugar y se partía («Disney» / «+») (I10, revisión del 10 nov).
    @ViewBuilder private func card(_ index: Int) -> some View {
        if index < posters.count, let url = posters[index], !url.isEmpty {
            PosterView(url: url, title: name).frame(width: DS.PlatformFan.poster)
                .shadow(DS.Elevation.high)
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.fill)
                .aspectRatio(DS.Poster.aspect, contentMode: .fit)
                .frame(width: DS.PlatformFan.poster)
                .accessibilityHidden(true)
        }
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

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
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
        .glow(glow > 0 ? tint : .clear, .strong)   // `glow: 0` lo apaga
        .accessibilityHidden(true)
    }

    /// Sin logo: la inicial sobre su color.
    private var initial: some View {
        Text(verbatim: String(name.prefix(1))).recipe(.cardTitle).frame(maxWidth: .infinity, maxHeight: .infinity).background(tint)
    }
}

/// Una plataforma para elegir de cuál es una lista: su logo redondo, la elegida con el anillo (el Top 10 de Inicio).
struct PlatformPill: View {
    let name: String
    let logo: String?
    let brand: String
    let selected: Bool
    let action: () -> Void

    var body: some View { bodyContent.pointerHover(.highlight) }
    // Solo el logo redondo, sin el nombre en una cápsula de texto (Fernando, 2 nov 2026, D2): la elegida lleva el anillo de lo
    // elegido. El nombre va para VoiceOver.
    @ViewBuilder private var bodyContent: some View {
        Button(action: action) {
            PlatformLogoTile(url: logo, name: name, size: DS.PlatformFan.pickLogo, radius: DS.PlatformFan.pickLogo / 2,
                             tint: DS.PlatformTint.color(brand), glow: 0)
                .overlay(Circle().strokeBorder(DS.hairline, lineWidth: DS.Size.hairline))
                .opacity(selected ? 1 : DS.Opacity.dimmed)
        }
        .buttonStyle(.plain)   // ds-exception: el logo es el botón (un círculo con su anillo), no un botón con texto
        .dsSelectionRing(selected, in: Circle())
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
