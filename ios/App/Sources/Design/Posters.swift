import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// El póster (con su avance, insignias y reflejo) y la tarjeta de póster.
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
    @State private var primaryFailed = false

    private var shownURL: String? { primaryFailed ? fallback : url }

    var body: some View {
        content.onChange(of: url) { primaryFailed = false }
    }

    @ViewBuilder private var content: some View {
        if whole { wholeArt.accessibilityLabel(Text(title)) }
        else if bleed { art.clipped().accessibilityLabel(Text(title)) }
        else {
            art
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.hairline))
                .accessibilityLabel(Text(title))
        }
    }

    private var art: some View {
        frame
            .overlay {
                if let url = shownURL, let u = URL(string: url) {
                    RemoteImage(url: u, maxPoints: maxPoints) { phase, size in
                        switch phase {
                        case .success(let image): filled(image, size: size)
                        case .failure where !primaryFailed && fallback != nil: placeholder.onAppear { primaryFailed = true }
                        default: placeholder
                        }
                    }
                } else { placeholder }
            }
    }

    /// Llena el marco y se recorta; si la imagen es mucho más angosta que el marco (un póster en un lugar ancho), va completa
    /// sobre su copia difuminada: se ve el póster entero, no una tira del medio (`ArtFit`).
    private func filled(_ image: Image, size: CGSize?) -> some View {
        GeometryReader { box in
            if let size, ArtFit.choose(image: size, box: box.size) == .whole {
                ZStack {
                    image.resizable().scaledToFill().frame(width: box.size.width, height: box.size.height).clipped()
                        .blur(radius: DS.Image.wholeBlur, opaque: true).overlay(DS.scrim)
                    image.resizable().scaledToFit()
                }
                .frame(width: box.size.width, height: box.size.height)
            } else {
                image.resizable().scaledToFill().frame(width: box.size.width, height: box.size.height)
            }
        }
    }

    @ViewBuilder private var wholeArt: some View {
        if let url, let u = URL(string: url) {
            RemoteImage(url: u, maxPoints: maxPoints) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()   // sin redondear: las esquinas del arte se ven completas
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

    private var placeholder: some View {
        Text(title).font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(DS.Space.s2)
    }
}

/// Portada con sus etiquetas y su barra de avance.
struct PosterCard: View {
    let title: String
    let poster: String?
    var badge: LocalizedStringKey?
    /// En tu watchlist: un marcador (ícono) en la esquina.
    var bookmarked = false
    /// El puesto en un Top 10: sustituye a `badge` en la esquina (una sola pieza, no dos encimadas).
    var rank: Int?
    var progress: Double?
    var width: CGFloat = DS.Poster.railWidth

    var body: some View {
        ZStack(alignment: .topLeading) {
            PosterView(url: poster, title: title)
            if let rank { DSRankBadge(rank: rank).padding(DS.Space.s2) }
            else if let badge { DSBadge(text: badge).padding(DS.Space.s2) }
            else if bookmarked { DSIconBadge(symbol: "bookmark.fill", label: "En tu watchlist").padding(DS.Space.s2) }
            if let progress { VStack { Spacer(); DSProgress(fraction: progress) } }
        }
        .frame(width: width)
        .accessibilityElement(children: .combine)
    }
}
