import SwiftUI
import OrbitalCore

// Piezas de la dirección «Editorial» (A + una portada): la portada de una sección (lo más importante, en grande, con su
// porqué en ámbar) y la pieza panorámica con su dato en la esquina (lo que sale pronto).

/// La portada de una sección: el arte ancho, el logo del título y, debajo, por qué está aquí («Hoy · 21:00 · T2 E5»).
struct CoverCard: View {
    let art: String?
    let logo: String?
    let title: String
    let why: Text
    var detail: Text?
    /// Su alto (¿Qué vemos? la achica al elegir; Buscar, para el mejor resultado).
    var height: CGFloat = DS.Editorial.coverHeight

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterView(url: art, title: title, aspect: nil, bleed: true, maxPoints: DS.Image.card)
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            LinearGradient(stops: [.init(color: .clear, location: DS.Editorial.veilStart), .init(color: DS.scrimStrong, location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                TitleLogo(url: logo, title: title, size: .tile)
                    .frame(maxWidth: DS.Editorial.coverLogo.width, maxHeight: DS.Editorial.coverLogo.height, alignment: .bottomLeading)
                (why + (detail.map { Text(verbatim: " · ") + $0 } ?? Text(verbatim: ""))).recipe(.footnote, color: DS.accent).fontWeight(.semibold).lineLimit(1)
            }
            .padding(DS.Space.s4)
            .onArt()
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Una pieza panorámica: el arte con el logo abajo, un dato corto en la esquina («Mañana») y una línea debajo.
struct WideCard: View {
    let art: String?
    let logo: String?
    let title: String
    let badge: Text
    let caption: Text

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            ZStack(alignment: .bottomLeading) {
                PosterView(url: art, title: title, aspect: DS.Poster.stillAspect)
                LinearGradient(stops: [.init(color: .clear, location: DS.Editorial.veilStart), .init(color: DS.scrimStrong, location: 1)], startPoint: .top, endPoint: .bottom)
                TitleLogo(url: logo, title: title, size: .tile)
                    .frame(maxWidth: DS.Editorial.wideLogo.width, maxHeight: DS.Editorial.wideLogo.height, alignment: .bottomLeading)
                    .padding(DS.Space.s3).onArt()
            }
            .overlay(alignment: .topTrailing) {
                badge.recipe(.caption, color: DS.text).fontWeight(.semibold)
                    .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
                    .glassEffect(.regular, in: Capsule()).padding(DS.Space.s2).onArt()
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            caption.recipe(.footnote).lineLimit(1)
        }
        .frame(width: DS.Editorial.wideWidth)
        .accessibilityElement(children: .combine)
    }
}
