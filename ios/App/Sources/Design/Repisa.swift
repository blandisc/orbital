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
/// La vitrina de Colecciones en Para ti (decisión 5A, 31 oct 2026): los objetos de cada colección sobre su repisa, cada uno
/// con su nombre y una barra de cuánto llevas («5/26»); al final «Ver todas». Debajo, la frase de la más cercana a completarse.
/// A dónde lleva cada uno lo dice quien la usa (`route` por colección, `all` para la repisa completa).
struct CollectionsShowcase<Route: Hashable, AllRoute: Hashable>: View {
    struct Entry: Identifiable { let id: String; let name: Text; let seen: Int; let total: Int }
    let entries: [Entry]
    var hint: Text?
    let route: (String) -> Route
    let all: AllRoute

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: DS.Space.s4) {
                    ForEach(entries) { e in
                        NavigationLink(value: route(e.id)) { item(e) }.buttonStyle(.plain).accessibilityIdentifier("showcase-\(e.id)")
                    }
                    NavigationLink(value: all) { seeAll }.buttonStyle(.plain).accessibilityIdentifier("showcase-all")
                }
                .padding(.horizontal, DS.Space.gutter)
                .padding(.top, DS.Space.s2)
            }
            .scrollClipDisabled()
            if let hint { hint.recipe(.footnote, color: DS.textMuted).padding(.horizontal, DS.Space.gutter) }
        }
    }

    private func item(_ e: Entry) -> some View {
        VStack(spacing: DS.Space.s1) {
            ShelfEmblem(id: e.id, height: DS.Repisa.showcaseEmblem)
            e.name.font(DS.TextRecipe.caption.font.weight(.semibold)).foregroundStyle(DS.text).lineLimit(1)
            Capsule().fill(DS.fillStrong)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in Capsule().fill(DS.warning).frame(width: geo.size.width * CGFloat(e.seen) / CGFloat(max(e.total, 1))) }
                }
                .frame(height: DS.Repisa.showcaseBar)
            Text(verbatim: "\(e.seen)/\(e.total)").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).monospacedDigit()
        }
        .frame(width: DS.Repisa.showcaseWidth)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(e.name)
        .accessibilityValue(Text("\(e.seen) de \(e.total)"))
    }

    private var seeAll: some View {
        VStack(spacing: DS.Space.s1) {
            Image(systemName: "chevron.forward").font(DS.TextRecipe.cardTitle.font.weight(.semibold)).foregroundStyle(DS.text)
                .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                .background(DS.surfaceRaised, in: Circle())
            Text("Ver todas").font(DS.TextRecipe.caption.font.weight(.semibold)).foregroundStyle(DS.textMuted)
        }
        .frame(width: DS.Repisa.showcaseWidth, height: DS.Repisa.showcaseEmblem + DS.Space.s14)
        .contentShape(Rectangle())
    }
}


/// El momento de «Ya la vi» en una colección (Fernando, 31 oct 2026: «que sea un momento más bonito, memorable»). Como un
/// ritual corto, no un aviso: sobre su fondo desenfocado, el póster aparece en gris (como los que te faltan en la repisa),
/// se revela a color con un destello que lo cruza, baja a su repisa con un rebote y un golpecito en la mano, la estatuilla se
/// enciende y el número sube con su barra. Debajo, lo que sigue: cuántas faltan para completar su década (o «Completaste…»).
/// Sin confeti. Con «Reducir movimiento», todo aparece de una vez. Tocar cierra; se va solo.
struct ShelfMoment: View {
    let poster: String
    let backdrop: String
    let title: String
    let emblem: String
    /// Cuántas llevas ya con esta y de cuántas.
    let seen: Int
    let total: Int
    /// Lo que sigue: «Te faltan 3 para completar Los 2010» o «Completaste Los 2010».
    let next: Text?
    let completed: Bool
    let onClose: () -> Void
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PosterView(url: backdrop, title: "", aspect: nil, bleed: true, maxPoints: DS.Image.wide)
                .blur(radius: DS.Repisa.momentBlur).opacity(DS.Repisa.momentBackdrop)
                .ignoresSafeArea().accessibilityHidden(true)
            DS.bg.opacity(DS.Repisa.momentVeil).ignoresSafeArea()
            VStack(spacing: DS.Space.s4) {
                Text(completed ? "¡Década completa!" : "A tu repisa").recipe(.footnote, color: completed ? DS.warning : DS.textMuted).fontWeight(.semibold)
                ShelfLedge {
                    PosterView(url: poster, title: title).frame(width: DS.Repisa.momentPoster)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .saturation(step >= 1 ? 1 : 0)
                        .brightness(step >= 1 ? 0 : DS.Repisa.unseenDim)
                        .overlay { shine }
                        .shadow(color: step >= 2 ? DS.scrimStrong : .clear, radius: DS.Space.s3, y: DS.Space.s2)
                        .offset(y: step >= 2 ? 0 : -DS.Repisa.momentDrop)
                        .scaleEffect(step >= 2 ? 1 : DS.Repisa.momentLift)
                }
                Text(verbatim: title).recipe(.title).multilineTextAlignment(.center).lineLimit(2)
                HStack(spacing: DS.Space.s3) {
                    ShelfEmblem(id: emblem, height: DS.Repisa.momentEmblem)
                        .shadow(color: step >= 3 ? DS.warning.opacity(DS.Repisa.momentGlow) : .clear, radius: DS.Space.s4)
                        .scaleEffect(step >= 3 ? 1 : DS.Repisa.momentEmblemStart)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(verbatim: "\(step >= 3 ? seen : max(seen - 1, 0)) de \(total)").recipe(.cardTitle).monospacedDigit()
                            .contentTransition(.numericText(value: Double(step >= 3 ? seen : seen - 1)))
                        Capsule().fill(DS.fillStrong)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Capsule().fill(DS.warning)
                                        .frame(width: geo.size.width * CGFloat(step >= 3 ? seen : max(seen - 1, 0)) / CGFloat(max(total, 1)))
                                }
                            }
                            .frame(width: DS.Repisa.momentBar, height: DS.Repisa.showcaseBar)
                    }
                }
                if let next { next.recipe(.footnote, color: completed ? DS.warning : DS.textMuted).multilineTextAlignment(.center).opacity(step >= 3 ? 1 : 0) }
            }
            .padding(DS.Space.s8)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .sensoryFeedback(.impact(weight: .light), trigger: step == 1)
        .sensoryFeedback(.success, trigger: step == 3)
        .task {
            if reduceMotion { step = 3 } else {
                // El ritual: aparece en gris, se revela, baja a la repisa, se enciende la estatuilla.
                try? await Task.sleep(for: DS.Repisa.momentBeat)
                withAnimation(.easeInOut(duration: DS.Repisa.momentReveal)) { step = 1 }
                try? await Task.sleep(for: DS.Repisa.momentBeat * 2)
                withAnimation(.spring(response: DS.Repisa.momentSpring, dampingFraction: DS.Repisa.momentBounce)) { step = 2 }
                try? await Task.sleep(for: DS.Repisa.momentBeat)
                withAnimation(.easeOut(duration: DS.Repisa.momentReveal)) { step = 3 }
            }
            try? await Task.sleep(for: DS.Repisa.momentHold)
            onClose()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(Text("\(title) a tu repisa: \(seen) de \(total)"))
    }

    /// El destello que cruza el póster al revelarse (de izquierda a derecha, una vez).
    private var shine: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, DS.paper.opacity(DS.Repisa.momentShine), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * DS.Repisa.momentShineWidth)
                .rotationEffect(.degrees(DS.Repisa.momentShineTilt))
                .offset(x: step >= 1 ? geo.size.width * (1 + DS.Repisa.momentShineWidth) : -geo.size.width * DS.Repisa.momentShineWidth)
                .animation(.easeInOut(duration: DS.Repisa.momentReveal * 1.4), value: step >= 1)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
