import SwiftUI
import OrbitalCore

// Piezas de Colecciones, la repisa (docs/producto/muvy-busqueda-premios/prototipo-repisa.html): la estatuilla o el objeto de
// cada colección, la repisa (una línea fina con su sombra) y el póster que está en gris hasta que lo ves.

/// La estatuilla de un premio (Óscar, Palma, Ariel…) completa, o el objeto de una lista famosa (el disco de Criterion, la
/// placa del Top 250). Con una luz tenue encima, como en una vitrina.
struct ShelfEmblem: View {
    let id: String
    var height: CGFloat = DS.Repisa.emblem

    var body: some View {
        Group {
            switch id {
            case "criterion":
                Text(verbatim: "C").font(DS.TextRecipe.title.font.weight(.heavy)).foregroundStyle(DS.backdropDeep)
                    .frame(width: height * DS.Repisa.discRatio, height: height * DS.Repisa.discRatio)
                    .background(DS.paper, in: Circle())
                    .shadow(color: DS.scrimStrong, radius: DS.Space.s2, y: DS.Space.s1)
            case "top250":
                VStack(spacing: 0) {
                    Text(verbatim: "IMDb").font(DS.TextRecipe.caption.font.weight(.heavy))
                    Text(verbatim: "250").font(DS.TextRecipe.cardTitle.font.weight(.black)).monospacedDigit()
                }
                .foregroundStyle(DS.backdropDeep).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                .padding(.horizontal, DS.Space.s1)
                .frame(width: height * DS.Repisa.plaqueWidth, height: height * DS.Repisa.plaqueHeight)
                .background(DS.warning, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .shadow(color: DS.scrimStrong, radius: DS.Space.s2, y: DS.Space.s1)
            default:
                Image("Awards/" + id).resizable().scaledToFit()
                    .shadow(color: DS.scrimStrong, radius: DS.Space.s2, y: DS.Space.s1)
            }
        }
        .frame(height: height, alignment: .bottom)
        .background(alignment: .top) {
            // La luz de la vitrina: un halo cálido muy tenue arriba de cada objeto.
            Ellipse().fill(DS.Repisa.lamp).frame(width: height * DS.Repisa.lampWidth, height: height * DS.Repisa.lampHeight)
                .blur(radius: DS.Space.s6).offset(y: -DS.Space.s4)
        }
        .accessibilityHidden(true)
    }
}

/// La repisa: lo que va encima y, abajo, una línea fina que se desvanece en las orillas con su sombra.
struct ShelfLedge<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.bottom, DS.Space.s3)
            .overlay(alignment: .bottom) {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: DS.Repisa.line, location: DS.Repisa.lineFade),
                                       .init(color: DS.Repisa.line, location: 1 - DS.Repisa.lineFade), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: DS.Size.hairline * 2)
                    .padding(.horizontal, -DS.Space.gutter)
            }
    }
}

/// Un título en su repisa: en gris y apagado mientras no lo ves; a color (y con sombra) cuando ya lo viste. Una línea ámbar
/// abajo si le diste 5 estrellas. Debajo, su año (o su lugar).
struct CanonPoster: View {
    let url: String
    let title: String
    let label: String
    let seen: Bool
    var favorite = false
    var rank: Int?

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            PosterView(url: url, title: title)
                .saturation(seen ? 1 : 0)
                .brightness(seen ? 0 : DS.Repisa.unseenDim)
                .overlay(alignment: .bottom) { if favorite, seen { DS.warning.frame(height: DS.Repisa.favoriteLine) } }
                .overlay(alignment: .topLeading) {
                    if let rank {
                        Text(verbatim: "\(rank)").font(DS.TextRecipe.caption.font.weight(.heavy)).foregroundStyle(DS.paper)
                            .shadow(color: DS.scrimStrong, radius: DS.Space.s1).padding(DS.Space.s1)
                    }
                }
                .shadow(color: seen ? DS.scrimStrong : .clear, radius: DS.Space.s2, y: DS.Space.s1)
                .animation(DS.Motion.tint(false), value: seen)
            Text(verbatim: label).font(DS.TextRecipe.caption.font.weight(.semibold)).monospacedDigit()
                .foregroundStyle(seen ? DS.textMuted : DS.textFaint).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(seen ? Text("Vista") : Text("Te falta"))
    }
}

/// La tarjeta de Colecciones en Para ti: tres estatuillas en su repisa y cuántas del canon llevas.
struct CollectionsCard: View {
    let seen: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ShelfLedge {
                    HStack(alignment: .bottom, spacing: DS.Space.s6) {
                        ForEach(["oscar", "palm", "ariel"], id: \.self) { ShelfEmblem(id: $0, height: DS.Repisa.cardEmblem) }
                    }
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Colecciones").recipe(.cardTitle, color: DS.text)
                    (seen == 0 ? Text("Los premios y listas que hay que ver") : Text("\(seen) del canon en tu repisa")).recipe(.footnote, color: DS.textMuted)
                }
            }
            .padding(DS.Space.s4)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("collections-card")
    }
}
