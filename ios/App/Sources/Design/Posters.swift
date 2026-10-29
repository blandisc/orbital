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
                    RemoteImage(url: u, maxPoints: maxPoints) { phase, source in
                        switch phase {
                        case .success(let image): filled(image, source: source, key: url)
                        case .failure where !primaryFailed && fallback != nil: placeholder.onAppear { primaryFailed = true }
                        default: placeholder
                        }
                    }
                } else { placeholder }
            }
    }

    /// Llena el marco y se recorta (hacia el sujeto si el recorte es grande, `FocusedFill`); si la imagen es mucho más angosta
    /// que el marco (un póster en un lugar ancho), va completa sobre su copia difuminada: se ve el póster entero, no una tira
    /// del medio (`ArtFit`).
    private func filled(_ image: Image, source: UIImage?, key: String) -> some View {
        GeometryReader { box in
            if let size = source?.size, ArtFit.choose(image: size, box: box.size) == .whole {
                ZStack {
                    image.resizable().scaledToFill().frame(width: box.size.width, height: box.size.height).clipped()
                        .blur(radius: DS.Image.wholeBlur, opaque: true).overlay(DS.scrim)
                    image.resizable().scaledToFit()
                }
                .frame(width: box.size.width, height: box.size.height)
            } else {
                FocusedFill(image: image, source: source, key: key, box: box.size)
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

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
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
            try? await Task.sleep(for: DS.Image.focusWait)
            gaveUp = true   // si tarda, al centro (y si lo encuentra después, se corre)
        }
    }
}

extension DS.Image {
    /// Lo más que se espera a encontrar al sujeto antes de mostrar la imagen al centro.
    static let focusWait: Duration = .milliseconds(350)
}

