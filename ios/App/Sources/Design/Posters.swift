import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// El póster (con su avance e insignias) y la tarjeta de póster.
/// El póster de un título: la imagen, o su nombre sobre un fondo si no carga. La imagen llena su marco y se recorta:
/// nunca agranda la vista (con `aspect: nil` ocupa el espacio que le den, como el destacado).
struct PosterView: View {
    let url: String?
    let title: String
    var aspect: CGFloat? = DS.Poster.aspect
    /// Arte a sangre (`BleedArt`): sin esquinas ni borde, solo recortado al marco.
    var bleed = false
    /// El lado más largo, en puntos, al que se reduce la imagen al bajarla (no se decodifica a tamaño completo).
    var maxPoints: CGFloat = DS.Image.card
    /// La imagen completa, con su propia forma (sin recortar): el arte que manda la TV no siempre es un póster vertical.
    /// `aspect` queda solo para el lugar que ocupa mientras carga.
    var whole = false
    /// Otra imagen si la primera no carga (la ficha y «Seguir viendo»: el fondo, y si metahub no lo tiene, el póster), en vez del
    /// nombre sobre el degradado.
    var fallback: String? = nil
    /// Solo de adorno (el muro de Explorar, la tira de «Decide por mí»): la imagen recortada y nada más, sin borde, sin el
    /// marco del puntero, sin buscar al sujeto ni nombre para VoiceOver. Son cientos a la vez y cada pieza de más se pagaba
    /// al abrir la pantalla (Explorar trababa ~0.5 s; 17 nov 2026).
    var decorative = false
    @State private var primaryFailed = false

    private var shownURL: String? { primaryFailed ? fallback : url }

    var body: some View {
        content.onChange(of: url) { primaryFailed = false }
    }

    @ViewBuilder private var content: some View {
        if decorative, Self.lightDecor { decorativeArt }
        else if whole { wholeArt.accessibilityLabel(Text(title)) }
        else if bleed { art.clipped().accessibilityLabel(Text(title)) }
        else {
            art
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(DS.hairline))
                .macPosterBounds()   // RP2: su enlace le dibuja el marco del foco de la TV y ▶ ＋ al pasar el puntero (solo Mac)
                .accessibilityLabel(Text(title))
        }
    }

    private var art: some View {
        frame
            .overlay {
                if let url = shownURL, let u = URL(string: url) {
                    RemoteImage(url: u, maxPoints: maxPoints) { phase, source in
                        switch phase {
                        case .success(let image): filled(image, source: source, key: url)
                        case .failure where !primaryFailed && fallback != nil: Color.clear.onAppear { primaryFailed = true }
                        case .failure: PosterStandIn(title: title)
                        default: Color.clear   // mientras llega, el marco quieto (sin nombre que luego brinca a la imagen)
                        }
                    }
                } else { PosterStandIn(title: title) }
            }
    }

    /// Llena el marco y se recorta (hacia el sujeto si el recorte es grande, `FocusedFill`); si la imagen es mucho más angosta
    /// que el marco (un póster en un lugar ancho), va completa sobre su copia difuminada: se ve el póster entero, no una tira
    /// del medio (`ArtFit`). A sangre (la portada de Inicio, la ficha ancha) va a la derecha y se funde hacia la izquierda en
    /// esa copia, sin orillas duras: ahí queda el texto (Fernando, 17 nov 2026: en el monitor ultrawide salía al centro, con
    /// dos cortes a los lados).
    private func filled(_ image: Image, source: UIImage?, key: String) -> some View {
        GeometryReader { box in
            if let size = source?.size, ArtFit.choose(image: size, box: box.size) == .whole {
                ZStack(alignment: bleed ? .trailing : .center) {
                    image.resizable().scaledToFill().frame(width: box.size.width, height: box.size.height).clipped()
                        .blur(radius: DS.Image.wholeBlur, opaque: true).overlay(DS.scrim)
                    image.resizable().scaledToFit()
                        .mask(LinearGradient(stops: [.init(color: bleed ? .clear : .black, location: 0), .init(color: .black, location: bleed ? DS.HomeHero.sideFade : 0)],
                                             startPoint: .leading, endPoint: .trailing))
                }
                .frame(width: box.size.width, height: box.size.height)
            } else {
                FocusedFill(image: image, source: source, key: key, box: box.size)
            }
        }
    }

    /// En las pruebas de la Mac, `off decor` pinta los de adorno completos, para comparar.
    private static var lightDecor: Bool {
        #if DEBUG
        if MacSelfCheck.off.contains("decor") { return false }
        #endif
        return true
    }

    /// Sin caja gris mientras llega: de adorno, un hueco vacío se veía roto (la tira de «Decide por mí» con cajas sin póster);
    /// la imagen entra con su fundido cuando llega.
    private var decorativeArt: some View {
        Color.clear.aspectRatio(aspect ?? DS.Poster.aspect, contentMode: .fit)
            .overlay {
                if let url, let u = URL(string: url) {
                    RemoteImage(url: u, maxPoints: maxPoints) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var wholeArt: some View {
        if let url = shownURL, let u = URL(string: url) {
            RemoteImage(url: u, maxPoints: maxPoints) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()   // sin redondear: las esquinas del arte se ven completas
                case .failure where !primaryFailed && fallback != nil:   // el arte de la TV no cargó: el póster de siempre
                    frame.clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)).onAppear { primaryFailed = true }
                default: frame.clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
            }
        } else { frame.clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)) }
    }

    /// El fondo marca el tamaño: con proporción, la del póster; sin ella, todo lo que le den.
    @ViewBuilder private var frame: some View {
        let fill = LinearGradient(colors: [DS.surfaceRaised, DS.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
        if let aspect { fill.aspectRatio(aspect, contentMode: .fit) } else { fill }
    }

}

/// El póster de un título sin imagen: el resplandor de su color, la película tenue y su nombre completo abajo, legible.
struct PosterStandIn: View {
    let title: String

    var body: some View {
        let hue = DS.Poster.missingHue(title)
        GeometryReader { box in
            ZStack(alignment: .bottomLeading) {
                EllipticalGradient(colors: [hue.opacity(DS.Poster.missingGlow), hue.opacity(DS.Poster.missingBase)],
                                   center: UnitPoint(x: 0.25, y: 0.15), startRadiusFraction: 0, endRadiusFraction: 1)
                Image(systemName: "film")
                    .resizable().scaledToFit()
                    .frame(width: box.size.width * DS.Poster.missingIconShare)
                    .foregroundStyle(DS.text.opacity(DS.Opacity.faint))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.bottom, box.size.height * DS.Poster.missingIconShare)
                Text(title)
                    .recipe(.cardTitle, color: DS.text)
                    .lineLimit(4).minimumScaleFactor(DS.Poster.missingTextShrink)
                    .multilineTextAlignment(.leading)
                    .padding(DS.Space.s2)
            }
        }
        .background(DS.surface)
        .accessibilityHidden(true)   // el póster ya dice su nombre a VoiceOver
    }
}

/// Portada con sus etiquetas y su barra de avance.
struct PosterCard: View {
    let title: String
    let poster: String?
    var badge: LocalizedStringKey?
    /// El ícono de la placa (el calendario de cuándo sale).
    var badgeSymbol: String?
    /// Su puesto en una plataforma («N.º 1» en la píldora de Disney+, con su logo): gana a `badge`.
    var platformRank: (rank: Int, platform: String)?
    /// En tu watchlist: un marcador (ícono) en la esquina.
    var bookmarked = false
    /// El puesto en un Top 10: sustituye a `badge` en la esquina (una sola pieza, no dos encimadas).
    var rank: Int?
    var progress: Double?
    var width: CGFloat = DS.Poster.railWidth
    /// Otro póster si el primero no carga (Buscar: el de TMDB cuando metahub no tiene el suyo).
    var fallback: String? = nil

    var body: some View { bodyContent.pointerHover(.lift, radius: DS.Radius.md) }   // el realce sigue la esquina del póster (D14)
    @ViewBuilder private var bodyContent: some View {
        ZStack(alignment: .topLeading) {
            PosterView(url: poster, title: title, fallback: fallback)
            if let rank { DSRankBadge(rank: rank).padding(DS.Space.s2) }
            else if let platformRank { PlatformBadge(name: platformRank.platform, rank: platformRank.rank).padding(DS.Space.s2) }
            else if let badge { DSBadge(text: badge, symbol: badgeSymbol).padding(DS.Space.s2) }
            else if bookmarked { DSIconBadge(symbol: "bookmark.fill", label: "En Mi lista").padding(DS.Space.s2) }
            if let progress { VStack { Spacer(); DSProgress(fraction: progress) } }
        }
        .frame(width: width)
        .accessibilityElement(children: .combine)
    }
}

/// La imagen llenando su marco. Si el recorte es grande (un fondo 16:9 en un marco alto, un póster en la portada de la ficha),
/// se corre hacia el sujeto (`FocalPoint`: caras, o lo que llama la atención) en vez de quedarse en el centro. Mientras lo busca
/// (una fracción de segundo, una sola vez por imagen) no se ve: así no brinca de lugar.
private struct FocusedFill: View {
    let image: Image
    let source: UIImage?
    let key: String
    let box: CGSize
    @State private var focus: CGPoint?
    @State private var gaveUp = false

    var body: some View {
        let size = source?.size ?? .zero
        let needed = source != nil && ArtFit.needsFocus(image: size, box: box)
        let point = focus ?? FocalPoint.cached(key)
        let drawn = ArtFit.filled(image: size, box: box)
        Group {
            if needed {
                image.resizable().frame(width: drawn.width, height: drawn.height)
                    .offset(ArtFit.offset(image: size, box: box, focus: point ?? CGPoint(x: 0.5, y: 0.5)))
                    .opacity(point == nil && !gaveUp ? 0 : 1)
            } else {
                image.resizable().scaledToFill()
            }
        }
        .frame(width: box.width, height: box.height)
        // Con `needed` en el id: el primer cuadro mide el marco en cero y la búsqueda no arrancaba nunca.
        .task(id: needed ? key : nil) {
            guard needed, point == nil, let source else { return }
            focus = await FocalPoint.find(source, key: key)
        }
        .task(id: needed ? key : nil) {
            guard needed, point == nil else { return }
            guard (try? await Task.sleep(for: DS.Image.focusWait)) != nil else { return }
            gaveUp = true   // si tarda, al centro (y si lo encuentra después, se corre)
        }
    }
}

extension DS.Image {
    /// Lo más que se espera a encontrar al sujeto antes de mostrar la imagen al centro.
    static let focusWait: Duration = .milliseconds(350)
}

