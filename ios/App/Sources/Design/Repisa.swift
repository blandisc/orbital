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
            case "criterion": CriterionEmblem(height: height)
            case "top250": IMDbEmblem(height: height)
            case "nyt-movies": ClapperEmblem(height: height)
            case "nyt-series": NewspaperEmblem(height: height, series: true)
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

/// Criterion: un disco plateado que sale de su estuche negro de coleccionista, con su brillo.
private struct CriterionEmblem: View {
    let height: CGFloat
    var body: some View {
        let box = height * DS.Repisa.caseSize
        ZStack(alignment: .leading) {
            // El disco, asomando a la derecha del estuche.
            Circle()
                .fill(AngularGradient(colors: [DS.paper, DS.textMuted, DS.paper, DS.textFaint, DS.paper], center: .center))
                .overlay(Circle().fill(DS.backdropDeep).padding(box * DS.Repisa.discHole))
                .overlay(Circle().strokeBorder(DS.paper.opacity(DS.Repisa.sheen), lineWidth: DS.Size.hairline))
                .frame(width: box * DS.Repisa.discRatio, height: box * DS.Repisa.discRatio)
                .offset(x: box * DS.Repisa.discOut)
            // El estuche, negro mate, con su «C» y el canto claro.
            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                .fill(DS.Repisa.objectFill)
                .overlay(alignment: .leading) { DS.paper.opacity(DS.Repisa.sheen).frame(width: DS.Size.hairline * 2) }
                .overlay {
                    Text(verbatim: "C").font(.system(size: box * DS.Repisa.caseLetter, weight: .black, design: .serif))   // ds-exception: la letra crece con el estuche
                        .foregroundStyle(DS.paper)
                }
                .frame(width: box * DS.Repisa.caseWidth, height: box)
        }
        .frame(width: box * (DS.Repisa.caseWidth + DS.Repisa.discOut), alignment: .leading)
        .shadow(color: DS.scrimStrong, radius: DS.Space.s2, y: DS.Space.s1)
    }
}

/// El Top 250 de IMDb: una placa de oro con «IMDb» en su sello amarillo y «250» grabado.
private struct IMDbEmblem: View {
    let height: CGFloat
    var body: some View {
        VStack(spacing: DS.Space.s1) {
            Text(verbatim: "IMDb").font(.system(size: height * DS.Repisa.seal, weight: .black))   // ds-exception: el sello crece con la placa
                .foregroundStyle(DS.backdropDeep)
                .padding(.horizontal, DS.Space.s1)
                .background(DS.warning, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
            Text(verbatim: "250").font(.system(size: height * DS.Repisa.plaqueNumber, weight: .black, design: .serif)).monospacedDigit()   // ds-exception: el número crece con la placa
                .foregroundStyle(LinearGradient(colors: [DS.paper, DS.warning], startPoint: .top, endPoint: .bottom))
        }
        .lineLimit(1).minimumScaleFactor(DS.Size.statScale)
        .frame(width: height * DS.Repisa.plaqueWidth, height: height * DS.Repisa.plaqueHeight)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(DS.Repisa.objectFill)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [DS.warning, DS.warning.opacity(DS.Repisa.sheen)], startPoint: .top, endPoint: .bottom), lineWidth: DS.Repisa.frame))
        )
        .shadow(color: DS.scrimStrong, radius: DS.Space.s2, y: DS.Space.s1)
    }
}

/// Las listas del New York Times: un periódico doblado, con su «T» gótica y sus columnas.
private struct NewspaperEmblem: View {
    let height: CGFloat
    let series: Bool
    var body: some View {
        let w = height * DS.Repisa.paperWidth
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: "T").font(.system(size: height * DS.Repisa.seal, weight: .black, design: .serif))   // ds-exception: la letra crece con el periódico
                .foregroundStyle(DS.backdropDeep).frame(maxWidth: .infinity)
            DS.backdropDeep.frame(height: DS.Size.hairline)
            HStack(alignment: .top, spacing: DS.Space.s1) {
                ForEach(0..<3, id: \.self) { column in
                    VStack(spacing: DS.Repisa.lineGap) {
                        ForEach(0..<DS.Repisa.paperLines, id: \.self) { _ in DS.textFaint.frame(height: DS.Size.hairline * 2) }
                    }
                }
            }
            Image(systemName: series ? "tv" : "film").font(DS.TextRecipe.caption.font.weight(.bold)).foregroundStyle(DS.backdropDeep)
                .frame(maxWidth: .infinity)
        }
        .padding(DS.Space.s1)
        .frame(width: w, height: height * DS.Repisa.paperHeight, alignment: .top)
        .background(LinearGradient(colors: [DS.paper, DS.paper.opacity(DS.Repisa.paperFold)], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        .rotationEffect(.degrees(DS.Repisa.paperTilt))
        .shadow(color: DS.scrimStrong, radius: DS.Space.s2, y: DS.Space.s1)
    }
}

/// Las 100 películas del NYT: una claqueta de papel periódico, con la «T» del Times y su barra a rayas.
private struct ClapperEmblem: View {
    let height: CGFloat
    var body: some View {
        let w = height * DS.Repisa.paperWidth * DS.Repisa.clapperWide
        VStack(spacing: DS.Repisa.lineGap) {
            // La barra de arriba, abierta, con sus rayas.
            HStack(spacing: 0) {
                ForEach(0..<DS.Repisa.clapperStripes, id: \.self) { i in (i.isMultiple(of: 2) ? DS.backdropDeep : DS.paper).frame(maxWidth: .infinity) }
            }
            .frame(height: height * DS.Repisa.clapperBar)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
            .rotationEffect(.degrees(DS.Repisa.clapperOpen), anchor: .bottomLeading)
            // El cuerpo: papel, la «T» y dos renglones.
            VStack(spacing: DS.Space.s1) {
                Text(verbatim: "T").font(.system(size: height * DS.Repisa.seal, weight: .black, design: .serif))   // ds-exception: la letra crece con la claqueta
                    .foregroundStyle(DS.backdropDeep)
                ForEach(0..<2, id: \.self) { _ in DS.textFaint.frame(height: DS.Size.hairline * 2) }
            }
            .padding(DS.Space.s1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [DS.paper, DS.paper.opacity(DS.Repisa.paperFold)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        }
        .frame(width: w, height: height * DS.Repisa.paperHeight * DS.Repisa.clapperTall)
        .shadow(color: DS.scrimStrong, radius: DS.Space.s2, y: DS.Space.s1)
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

/// La entrada a Colecciones en Para ti (Fernando, 31 oct 2026): las listas famosas (Criterion, IMDb Top 250…), cada una
/// con sus primeros pósters en abanico y su nombre; sin las estatuillas, que ya salen arriba en Premios.
struct CollectionsCard: View {
    struct Entry: Identifiable { let id: String; let name: Text; let posters: [String] }
    let shelves: [Entry]
    /// nil: solo la tarjeta (va dentro de un `NavigationLink`, que es quien recibe el toque). Con botón adentro y los toques
    /// apagados para no chocar, el enlace se quedaba sin dónde tocar y no se podía entrar (Fernando, 30 oct 2026).
    var action: (() -> Void)?

    var body: some View {
        if let action { Button(action: action) { card }.buttonStyle(.plain).accessibilityIdentifier("collections-card") }
        else { card.accessibilityIdentifier("collections-card") }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .bottom, spacing: DS.Space.s4) {
                ForEach(shelves.prefix(DS.Repisa.cardShelves)) { shelf in
                    VStack(spacing: DS.Space.s2) {
                        PosterFan(posters: shelf.posters, width: DS.Repisa.cardPoster)
                        shelf.name.recipe(.caption, color: DS.textMuted).fontWeight(.semibold).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(minHeight: DS.Repisa.cardFan)
            HStack {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Colecciones").recipe(.cardTitle, color: DS.text)
                    Text("Las listas que hay que ver").recipe(.footnote, color: DS.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted)
            }
        }
        .padding(DS.Space.s4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }
}
