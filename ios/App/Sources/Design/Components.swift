import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.

/// Un dato corto: «2,1 GB», «HDR», «Al instante» (`good`) o «34 GB» (`warn`). Una línea, nunca se parte.
struct DSChip: View {
    enum Tone { case normal, good, warn }
    let label: Text
    var tone: Tone = .normal

    init(text: LocalizedStringKey, tone: Tone = .normal) { label = Text(text); self.tone = tone }
    /// Texto ya armado (nombres, tamaños): no se traduce.
    init(verbatim: String, tone: Tone = .normal) { label = Text(verbatim: verbatim); self.tone = tone }

    var body: some View {
        label.font(DS.TextRecipe.caption.font).lineLimit(1).fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    private var color: Color { switch tone { case .normal: DS.textMuted; case .good: DS.good; case .warn: DS.warning } }
}

/// Un dato ya armado (nombres, tamaños): no se traduce.
struct DSChipText: View {
    let text: String
    var tone: DSChip.Tone = .normal
    var body: some View { DSChip(verbatim: text, tone: tone) }
}

/// Etiqueta que llama la atención sobre el arte: «Recomendada», «En tu lista» (sin mayúsculas).
struct DSBadge: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text).font(DS.TextRecipe.caption.font.weight(.semibold)).lineLimit(1).foregroundStyle(DS.paper)   // sobre la placa oscura del arte, en los dos modos
            .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
            .background(DS.badgeBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }
}

/// Una marca de una sola idea en la esquina de un póster (en tu watchlist): el ícono sobre la placa oscura, con su nombre para VoiceOver.
struct DSIconBadge: View {
    let symbol: String
    let label: LocalizedStringKey
    var body: some View {
        Image(systemName: symbol).font(DS.TextRecipe.caption.font.weight(.semibold)).foregroundStyle(DS.paper)
            .padding(DS.Space.s1 + DS.Space.s1 / 2)
            .background(DS.badgeBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            .accessibilityLabel(Text(label))
    }
}

/// El puesto en un Top 10 (chart de Netflix, JustWatch…): una sola pieza, número grande sobre una placa oscura,
/// con el mismo radio que la portada que acompaña (esquina superior izquierda).
struct DSRankBadge: View {
    let rank: Int
    var body: some View {
        Text(verbatim: "\(rank)").font(DS.TextRecipe.section.font.weight(.bold)).foregroundStyle(DS.paper).lineLimit(1)   // sobre la placa oscura, en los dos modos
            .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
            .background(DS.badgeBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .accessibilityLabel(Text("Puesto \(rank)"))
    }
}

/// El logo de una plataforma (Netflix, Disney+…) en un chip o un encabezado: siempre la misma altura, venga el
/// logo cuadrado o apaisado, para que la tira no «baile».
struct DSPlatformLogo: View {
    let url: String?

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                RemoteImage(url: u, maxPoints: DS.Image.platformLogo) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFit() } else { Color.clear }
                }
            } else { Color.clear }
        }
        .frame(height: DS.Size.platformLogo)
    }
}

/// Cuánto llevas de un video.
struct DSProgress: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(DS.track)
                // Sin avance no se dibuja (una forma de ancho cero, dentro del vidrio y girada en 3D en el carrusel, cerraba la app).
                if fraction > 0 { Rectangle().fill(DS.accent).frame(width: max(DS.Size.hairline, geo.size.width * min(1, fraction))) }   // el acento es avance
            }
        }
        .frame(height: DS.Space.s1).clipShape(Capsule())
        .accessibilityLabel(Text("Avance")).accessibilityValue(Text("\(Int(fraction * 100)) %"))
    }
}

/// El encabezado de toda sección de la app (dirección «Editorial»): el título grande, a la derecha «Ver todo» si abre la
/// lista completa (o un dato corto), y debajo una línea gris solo cuando ayuda a decidir. Sin íconos: el color lo pone el
/// arte de abajo. Una sola pieza: todas las secciones se ven igual.
struct DSSectionHead: View {
    let title: Text
    var trailing: Text?
    var action: (() -> Void)?
    /// Cuántos hay (en gris), en listas que son herramienta (Descargas); en un escaparate, mejor «Ver todo».
    var count: Int?
    /// Abre la lista completa: «Ver todo».
    var chevron = false
    /// La línea gris de abajo.
    var meta: Text?
    /// De dónde viene (Trakt, Stremio, tu Orbital): su sello junto al título.
    var source: ListSource?
    /// El porqué, en una línea ámbar arriba del título («Lo que dejaste pendiente»), como en una revista.
    var eyebrow: Text?

    init(title: Text, trailing: Text? = nil, action: (() -> Void)? = nil, count: Int? = nil, chevron: Bool = false, meta: Text? = nil, source: ListSource? = nil, eyebrow: Text? = nil) {
        self.title = title; self.trailing = trailing; self.action = action; self.count = count; self.chevron = chevron; self.meta = meta; self.source = source
        self.eyebrow = eyebrow
    }

    init(title: LocalizedStringKey, trailing: LocalizedStringKey? = nil, action: (() -> Void)? = nil, count: Int? = nil, chevron: Bool = false, meta: Text? = nil, source: ListSource? = nil, eyebrow: Text? = nil) {
        self.init(title: Text(title), trailing: trailing.map { Text($0) }, action: action, count: count, chevron: chevron, meta: meta, source: source, eyebrow: eyebrow)
    }

    var body: some View {
        // Sin texto a la derecha, la acción es de todo el encabezado (el «Ver todo» de Buscar): antes solo se conectaba
        // con `trailing` y la cápsula «Ver todo» no hacía nada al tocarla.
        if trailing == nil, let action { Button(action: action) { head }.buttonStyle(.plain) } else { head }
    }

    private var head: some View {
        // Lo de la derecha («Ver todo», el número) va a la altura del título, no de la línea ámbar de arriba.
        HStack(alignment: .sectionTitle, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // Un solo lugar para el porqué de una sección en toda la app: arriba del título, en ámbar (como una revista).
                // Antes unas lo ponían arriba en ámbar y otras abajo en gris.
                if let line = eyebrow ?? meta { line.recipe(.eyebrow, color: DS.eyebrow).lineLimit(2).multilineTextAlignment(.leading) }
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    title.recipe(.section).lineLimit(2).multilineTextAlignment(.leading)
                        // El centro que se ve (la mitad de las mayúsculas sobre la línea base), no el de la caja del texto:
                        // así lo de la derecha no queda alto.
                        .alignmentGuide(.sectionTitle) { $0[.firstTextBaseline] - UIFont.preferredFont(forTextStyle: .title2).capHeight / 2 }
                    if let source { SourceBadge(source: source) }
                }
                if eyebrow != nil, let meta { meta.recipe(.footnote).lineLimit(2).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: DS.Space.s2)
            if let trailing {
                if let action { Button(action: action) { trailing }.font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted) }
                else { trailing.font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted) }
            }
            if chevron { SeeAllLabel() }
            else if let count { Text(verbatim: "\(count)").recipe(.secondary, color: DS.textMuted) }
        }
        .textCase(nil)   // también como encabezado de una lista (Descargas): sin las mayúsculas del sistema
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Una imagen remota (pósters, fondos, logos): la baja `ImagePipeline` reducida al tamaño en que se ve, con caché en
/// memoria y disco compartido por toda la app, y la decodifica fuera del hilo principal. Si ya estaba en memoria
/// aparece en el primer fotograma (sin parpadeo al reciclar la pieza). Mismo contrato que `AsyncImage`.
enum RemoteImagePhase { case loading, success(Image), failure }

struct RemoteImage<Content: View>: View {
    let url: URL
    let maxPoints: CGFloat
    @ViewBuilder let content: (RemoteImagePhase) -> Content
    @State private var loaded: UIImage?
    @State private var didFail = false
    @Environment(\.perfTag) private var perfTag

    init(url: URL, maxPoints: CGFloat, @ViewBuilder content: @escaping (RemoteImagePhase) -> Content) {
        self.url = url; self.maxPoints = maxPoints; self.content = content
    }

    var body: some View {
        content(phase).task(id: url) { await load() }
    }

    /// La caché se consulta al pintar, no al crear la vista: SwiftUI crea la vista cada vez que se pinta su padre (cada
    /// póster de cada estante), pero solo la vuelve a pintar si cambió algo suyo.
    private var phase: RemoteImagePhase {
        if let loaded { return .success(Image(uiImage: loaded)) }
        if let hit = ImagePipeline.shared.cached(url, maxPixel: maxPoints * ImagePipeline.screenScale) { return .success(Image(uiImage: hit)) }
        return didFail ? .failure : .loading
    }

    private func load() async {
        let pixels = maxPoints * ImagePipeline.screenScale
        if let hit = ImagePipeline.shared.cached(url, maxPixel: pixels) { loaded = hit; if let perfTag { Perf.mark(perfTag + ".image") }; return }
        loaded = nil   // otra URL en la misma vista: no se queda la imagen de antes mientras llega (o si falla) la nueva
        if ImagePipeline.shared.recentlyFailed(url, maxPixel: pixels) { didFail = true; return }
        didFail = false
        // Un fondo o un póster: primero su versión ligera (llega en una fracción) y encima la buena cuando esté.
        // (También si la buena ya está en el disco: decodificar 1920 px tarda; la ligera sale casi al instante.)
        if let preview = Artwork.preview(url.absoluteString), pixels > CGFloat(preview.pixels), let quickURL = URL(string: preview.url) {
            async let full = ImagePipeline.shared.image(url, maxPixel: pixels)
            if let quick = await ImagePipeline.shared.image(quickURL, maxPixel: CGFloat(preview.pixels), urgent: true), !Task.isCancelled {
                if loaded == nil { loaded = quick; if let perfTag { Perf.mark(perfTag + ".image") } }
            }
            let image = await full
            if Task.isCancelled { return }
            if let image { loaded = image; if let perfTag { Perf.mark(perfTag + ".sharp") } } else if loaded == nil { didFail = true }
            return
        }
        let image = await ImagePipeline.shared.image(url, maxPixel: pixels)
        if Task.isCancelled { return }
        if let image { loaded = image; if let perfTag { Perf.mark(perfTag + ".image") } } else { didFail = true }
    }
}

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

    var body: some View {
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
                if let url, let u = URL(string: url) {
                    RemoteImage(url: u, maxPoints: maxPoints) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: placeholder
                        }
                    }
                } else { placeholder }
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

/// Arte a sangre (de borde a borde, sin esquinas) que se funde con el fondo por abajo con una máscara de gradiente: el
/// destacado de Inicio y el encabezado de la ficha (`.title__backdrop` y el arte del `FeatureTile` en la TV). Lo que va encima
/// (`content`) queda abajo, sobre el velo, y no se desvanece.
struct BleedArt<Content: View>: View {
    let url: String?
    let title: String
    /// Sin proporción llena el espacio que le den (con un mínimo, como el destacado); con ella, esa relación (la de la ficha).
    var aspect: CGFloat?
    var minHeight: CGFloat = 0
    /// Dentro de un `ScrollView` (la ficha): al desplazar, el arte se recoge hacia este color (el del fondo detrás del arte,
    /// `Backdrop.tone`). Ver `DS.TitleHero` y `OrbitalModels.HeroCollapse`. nil: arte quieto (el destacado de Inicio).
    var collapse: Color? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // En oscuro el arte se funde con el fondo de borde a borde; en claro es una tarjeta con esquinas (la sala oscura no se
        // funde con el papel: el texto claro de encima dejaría de leerse).
        ZStack(alignment: .bottomLeading) {
            Group {
                if scheme == .dark {
                    art.mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: (1 - DS.Backdrop.artFadeStart) / 2),
                                                    .init(color: .black, location: DS.Backdrop.artFadeStart),
                                                    .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                } else {
                    art.clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
                }
            }
            // Al recogerse: se queda un poco atrás, se encoge apenas, se difumina al final y se desvanece. Todo con
            // `visualEffect` (en el render, sin volver a medir ni a dibujar la imagen); al jalar hacia abajo se estira desde abajo.
            .visualEffect { [on = collapse != nil, still = reduceMotion] view, proxy in
                let s = Self.collapseState(proxy, on: on, still: still)
                return view.offset(y: s.offset).scaleEffect(s.scale, anchor: .bottom).blur(radius: s.blur).opacity(s.artOpacity)
            }
            // El logo y la frase se van con el contenido (sin parallax) y antes que el arte: no se quedan detrás de los datos.
            content().onArt().padding(.horizontal, DS.Space.gutter).padding(.bottom, scheme == .dark ? DS.Space.s3 : DS.Space.s5)
                .visualEffect { [on = collapse != nil, still = reduceMotion] view, proxy in
                    let s = Self.collapseState(proxy, on: on, still: still)
                    return view.scaleEffect(s.contentScale, anchor: .bottom).opacity(s.contentOpacity)
                }
        }
        .coordinateSpace(.named(Self.space))
        .frame(minHeight: minHeight)      // con letra grande crece en vez de encimar el texto
        .padding(.horizontal, scheme == .dark ? 0 : DS.Space.gutter)
        .accessibilityElement(children: .contain)
    }

    private var art: some View {
        PosterView(url: url, title: title, aspect: aspect, bleed: true, maxPoints: DS.Image.bleed)
            // El velo sube hasta donde empieza el texto: rótulo, logo y datos se leen aunque el arte sea claro.
            .overlay(LinearGradient(stops: [.init(color: .clear, location: DS.Backdrop.scrimStart), .init(color: DS.scrim, location: DS.Backdrop.scrimMid),
                                            .init(color: DS.scrimStrong, location: 1)], startPoint: .top, endPoint: .bottom))
            .overlay { if let collapse { veil(collapse) } }
    }

    /// Al recogerse, el arte se oscurece hacia el color del fondo: un velo parejo que crece poco a poco y un degradado que
    /// sube desde abajo (como Apple TV y Música). Solo cambian su opacidad y su alto, en el render.
    private func veil(_ color: Color) -> some View {
        ZStack {
            color.visualEffect { [still = reduceMotion] view, proxy in view.opacity(Self.collapseState(proxy, on: true, still: still).dim) }
            LinearGradient(stops: [.init(color: color.opacity(DS.TitleHero.riseTopOpacity), location: 0), .init(color: color.opacity(DS.TitleHero.riseSolidOpacity), location: DS.TitleHero.riseSolidAt),
                                   .init(color: color, location: 1)], startPoint: .top, endPoint: .bottom)
                .visualEffect { [still = reduceMotion] view, proxy in
                    let rise = Self.collapseState(proxy, on: true, still: still).rise
                    return view.scaleEffect(x: 1, y: max(rise, DS.TitleHero.riseMin), anchor: .bottom).opacity(rise > 0 ? 1 : 0)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private nonisolated static var space: String { "bleed-art" }

    /// Cuánto se ha recogido el arte entero (no la capa que pregunta): su lugar en el desplazamiento y su alto salen del
    /// espacio con nombre del arte, así el logo, el velo y el arte usan la misma cuenta.
    private nonisolated static func collapseState(_ proxy: GeometryProxy, on: Bool, still: Bool) -> HeroCollapse {
        let tuning = HeroCollapse.Tuning(parallax: DS.TitleHero.parallax, shrink: DS.TitleHero.shrink, blur: DS.TitleHero.blur, blurFrom: DS.TitleHero.blurFrom,
                                         dim: DS.TitleHero.dim, riseEnd: DS.TitleHero.riseEnd, fadeFrom: DS.TitleHero.fadeFrom,
                                         contentFadeEnd: DS.TitleHero.contentFadeEnd, contentShrink: DS.TitleHero.contentShrink)
        guard on, let hero = proxy.bounds(of: .named(space)) else { return HeroCollapse.at(minY: 0, height: 1, reduceMotion: true, tuning: tuning) }
        // `bounds(of:)` es el arte entero visto desde esta capa: su origen es lo que esta capa está corrida dentro del arte.
        let top = proxy.frame(in: .scrollView).minY + hero.minY
        return HeroCollapse.at(minY: top, height: hero.height, reduceMotion: still, tuning: tuning)
    }
}

/// El logo del título (metahub); si no carga o no hay, su nombre en texto (misma regla que `--logo` en la TV). `.tile` es el de una
/// pieza del mosaico; `.hero`, el del destacado y la ficha (más grande, hasta dos líneas). `dark`: el logo es oscuro y se pinta blanco.
struct TitleLogo: View {
    enum Size { case tile, hero }
    let url: String?
    let title: String
    var size: Size = .tile
    var dark = false
    /// Centrado (la ficha): el logo y, si no hay, el nombre, al centro.
    var centered = false
    /// Si el logo resultó oscuro al medirlo (un logo negro sobre la sala oscura no se lee): se pinta claro.
    @State private var measuredDark = false
    /// El logo sin su margen transparente (metahub los trae con ~25 % vacío arriba y abajo: el rótulo se veía flotando).
    @State private var trimmed: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                Group {
                    if let trimmed { Image(uiImage: trimmed).resizable().scaledToFit().brightness(dark || measuredDark ? 1 : 0) }
                    else if failed { name }
                    else { name.hidden() }     // mientras carga guarda el sitio del nombre: no brinca si el logo llega
                }
                // Su alto real (por su proporción, con el tope de siempre): una caja más alta que el logo dejaba un hueco
                // entre el rótulo y el logo.
                .frame(maxWidth: DS.Size.cardMax, maxHeight: fittedHeight, alignment: centered ? .bottom : .bottomLeading)
                .shadow(DS.Elevation.low)
                .task(id: url) {
                    trimmed = LogoTrim.cached(u)
                    if trimmed == nil {
                        if let found = await LogoTrim.load(u) { trimmed = found } else { failed = true }
                    }
                    measuredDark = await LogoTone.isDark(u)
                }
            } else { name }
        }
        .accessibilityLabel(Text(title))
    }

    private var height: CGFloat { size == .hero ? DS.Size.logoHero : DS.Size.logo }

    /// El alto que de verdad ocupa el logo recortado a lo ancho de siempre (sin pasar del tope).
    private var fittedHeight: CGFloat {
        guard let trimmed, trimmed.size.width > 0, trimmed.size.height > 0 else { return height }
        return min(height, DS.Size.cardMax * trimmed.size.height / trimmed.size.width)
    }

    private var name: some View {
        // En una pieza, una sola línea (con puntos suspensivos si no cabe): en una columna angosta dos líneas se encimaban con el dato.
        Text(title).font((size == .hero ? DS.TextRecipe.section : DS.TextRecipe.cardTitle).font.weight(.bold)).foregroundStyle(DS.text)
            .lineLimit(size == .hero ? 2 : 1).multilineTextAlignment(centered ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

/// El destacado (Inicio y Para ti › Listas, `FeatureTile` en la TV): arte a sangre con velo, un rótulo («Seguir viendo»,
/// «N.º 2 en Netflix»), el logo del título, una línea de datos en SF Mono, las acciones y el avance. Todo encima va como en
/// la sala oscura (también en modo claro).
struct HeroCard<Actions: View>: View {
    let title: String
    let background: String?
    var logo: String?
    var eyebrow: Text?
    var accentEyebrow = false
    var data: [String] = []
    var progress: Double?
    /// Abrir la ficha: la tarjeta lo hace con su toque y VoiceOver con la acción «Ver ficha» sobre el nombre.
    var open: (() -> Void)?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        BleedArt(url: background, title: title, minHeight: DS.Poster.heroHeight) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    if let eyebrow { Eyebrow(text: eyebrow, accent: accentEyebrow, onArt: true) }
                    TitleLogo(url: logo, title: title, size: .hero)
                    if !data.isEmpty { DataLine(parts: data, color: DS.onArtSecondary) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text("Ver ficha")) { open?() }
                actions().padding(.top, DS.Space.s1)
                if let progress { DSProgress(fraction: progress) }
            }
        }
    }
}

/// Un renglón de lista (`RowTile` en la TV): miniatura ancha, nombre y dato. 
struct RowTile: View {
    let title: String
    let thumb: String?
    let detail: String
    var progress: Double?

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            ZStack(alignment: .bottom) {
                PosterView(url: thumb, title: title, aspect: DS.Poster.stillAspect)
                if let progress { DSProgress(fraction: progress) }
            }
            .frame(width: DS.Poster.episodeThumbWidth)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text).lineLimit(2)
                if !detail.isEmpty { Text(detail).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// Botones: los nativos de iOS 26 (Liquid Glass). Principal: `.dsPrimaryButton()` (vidrio con letra oscura); secundario: `.buttonStyle(.glass)`;
// sobre fondos lisos, `.borderedProminent` / `.bordered`. No hay estilos de botón propios (`DesignTests` lo vigila).

extension View {
    /// El botón principal: vidrio nativo con el tinte de Orbital (papel) y la letra oscura encima. Sin esto, iOS pone letra
    /// blanca sobre el tinte claro y no se lee.
    func dsPrimaryButton() -> some View { buttonStyle(.glassProminent).foregroundStyle(DS.onPrimary) }

    /// El botón principal de un título con arte (Ver, Continuar): toma el color claro del arte, con texto oscuro, como
    /// `--color-primary-art` en la TV. Sin colores, el neutro casi papel de la TV.
    func dsArtButton(_ colors: ArtColors?) -> some View { modifier(ArtButton(colors: colors)) }

    /// El botón principal de la ficha: sólido, a todo lo ancho, negro en claro y blanco en oscuro (`DS.solidPrimary`), con
    /// esquinas de tarjeta. El nativo `.borderedProminent` con otro tinte: sin estilo propio.
    func dsSolidPrimaryButton() -> some View {
        buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: DS.Radius.lg))
            .tint(DS.solidPrimary).foregroundStyle(DS.onSolidPrimary)
    }
}

/// Botones sólidos (sin vidrio) en lo que se gira en 3D: el carrusel de Inicio en coverflow deformaba el vidrio.
private struct SolidButtonsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var solidButtons: Bool {
        get { self[SolidButtonsKey.self] }
        set { self[SolidButtonsKey.self] = newValue }
    }
}

private struct ArtButton: ViewModifier {
    let colors: ArtColors?
    func body(content: Content) -> some View {
        // Sólido siempre: el vidrio dejaba pasar el arte y el botón se veía deslavado (texto oscuro sobre un tono pálido y
        // translúcido). Lleno, el color del arte con el texto oscuro guarda el contraste mínimo.
        content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint((colors ?? .neutral).accent).foregroundStyle(DS.backdropDeep)
    }
}

/// El botón de ícono secundario: de vidrio; sólido donde el vidrio no se lleva bien (`solidButtons`).
private struct IconButtonLook: ViewModifier {
    @Environment(\.solidButtons) private var solid
    func body(content: Content) -> some View {
        if solid { content.buttonStyle(.bordered).tint(DS.paper) } else { content.buttonStyle(.glass) }
    }
}

extension View {
    func dsIconButtonLook() -> some View { modifier(IconButtonLook()) }
}

/// «Más»: el mismo menú en toda la app, un círculo con «…» (vidrio; sólido donde el vidrio no se lleva bien). Antes había cuatro
/// (con texto, borde, otro ícono…).
struct DSMoreMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu { content() } label: { Image(systemName: "ellipsis") }
            .dsIconButtonLook().buttonBorderShape(.circle).controlSize(.large)
            .accessibilityLabel(Text("Más"))
    }
}

/// Un botón redondo con un ícono (más, descargar, cerrar): el botón nativo con vidrio de iOS 26, ya con su tamaño táctil de 44 pt.
struct DSIconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var prominent = false
    let action: () -> Void

    var body: some View {
        Group {
            if prominent { Button(action: action) { Image(systemName: symbol) }.dsPrimaryButton() }
            else { Button(action: action) { Image(systemName: symbol) }.dsIconButtonLook() }
        }
        .buttonBorderShape(.circle).controlSize(.large)
        .accessibilityLabel(Text(label))
    }
}

/// Un botón de ícono que pide confirmación: el primer toque lo abre en una cápsula que dice qué hará («¿Ver en la TV?»),
/// el segundo lo hace; si no lo tocas otra vez, se cierra solo.
struct ConfirmIconButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let symbol: String
    let prompt: LocalizedStringKey
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var asking = false

    var body: some View {
        Button {
            if asking { asking = false; action() } else { withAnimation(DS.Motion.base(reduceMotion)) { asking = true } }
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: symbol)
                if asking { Text(prompt).lineLimit(1).fixedSize().transition(.opacity.combined(with: .move(edge: .leading))) }
            }
        }
        .dsIconButtonLook()
        .buttonBorderShape(asking ? .capsule : .circle).controlSize(.large)
        .accessibilityLabel(Text(label))
        .accessibilityHint(asking ? Text("Toca otra vez para confirmar") : Text(prompt))
        .sensoryFeedback(.selection, trigger: asking)
        .task(id: asking) {
            guard asking else { return }
            try? await Task.sleep(nanoseconds: DS.Timing.confirm)
            withAnimation(DS.Motion.base(reduceMotion)) { asking = false }
        }
    }
}

/// Un aviso corto con su color (sin conexión, error).
struct DSNotice: View {
    enum Tone { case info, success, warn, error }
    let text: Text
    var tone: Tone = .info

    init(text: LocalizedStringKey, tone: Tone = .info) { self.text = Text(text); self.tone = tone }
    /// Un texto ya en el idioma de la app (un error o aviso traducido con `Strings.message`): tal cual, sin buscarlo otra vez.
    init(verbatim: String, tone: Tone = .info) { self.text = Text(verbatim: verbatim); self.tone = tone }

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: symbol)
            text.font(DS.TextRecipe.footnote.font).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var symbol: String {
        switch tone { case .info: "info.circle"; case .success: "checkmark.circle.fill"; case .warn: "exclamationmark.triangle"; case .error: "exclamationmark.triangle.fill" }
    }

    private var color: Color {
        switch tone { case .info: DS.textMuted; case .success: DS.good; case .warn: DS.warning; case .error: DS.danger }
    }
}

/// Selector segmentado: el control nativo de iOS (`Picker` con `.segmented`), que en iOS 26 ya es de vidrio.
struct DSSegmented<Value: Hashable>: View {
    let options: [(Value, LocalizedStringKey)]
    @Binding var selection: Value
    /// El valor actual como dato de la vista: con un `Binding(get:set:)` SwiftUI no ve el cambio y no la vuelve a pintar.
    private let current: Value

    init(options: [(Value, LocalizedStringKey)], selection: Binding<Value>) {
        self.options = options; _selection = selection; current = selection.wrappedValue
    }

    var body: some View {
        Picker(selection: $selection) {
            ForEach(options.indices, id: \.self) { Text(options[$0].1).tag(options[$0].0) }
        } label: { EmptyView() }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: current)
    }
}

/// Cuando un área entera no tiene nada (Descargas vacía, sin resultados, nada con estos filtros): siempre esto, el vacío nativo
/// de iOS con un ícono, qué pasa y, si lo hay, qué hacer. Regla de la app: un área vacía → `DSEmptyState`; un renglón vacío
/// dentro de una sección → texto chico; un error o sin conexión → `DSNotice`.
struct DSEmptyState<Actions: View>: View {
    let symbol: String
    let title: Text
    var message: Text?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ContentUnavailableView {
            Label { title } icon: { Image(systemName: symbol) }
        } description: {
            if let message { message }
        } actions: {
            actions().buttonStyle(.glass).controlSize(.large)
        }
    }
}

extension DSEmptyState where Actions == EmptyView {
    init(symbol: String, title: Text, message: Text? = nil) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// Los íconos de los tipos, los mismos en toda la app (menús, la cápsula de lo elegido, los chips de filtros, el mosaico):
/// Todo, Películas y Series. «tv» no: ese es «Ver en la TV».
enum KindGlyph {
    static let all = "square.grid.2x2", movie = "film", series = "play.rectangle.on.rectangle"
    /// "" o nil es todo, «movie» o «series».
    static func symbol(_ kind: String?) -> String {
        switch kind { case "movie": movie; case "series": series; default: all }
    }
}

/// El filtro de tipo de toda la app: Todo · Películas · Series (o solo Películas · Series), siempre el mismo control y en
/// ese orden (antes había cinco: cápsulas, un menú, pestañas grandes, un segmentado y un botón en la barra).
/// `kind`: "" es todo, «movie» o «series». `counts`: cuántas hay de cada uno (Buscar).
struct DSKindFilter: View {
    @Binding var kind: String
    var includeAll = true
    var counts: (movies: Int, series: Int)?
    /// Chico, a la derecha del título de su sección: el switch en cápsula (dos opciones, como el Top 10).
    var compact = false
    /// Una lista que se despliega (tres opciones no caben junto al título): la cápsula con lo elegido y ⌄, como «Ver todo».
    var menu = false

    var body: some View {
        Group {
            if menu {
                Menu {
                    Picker(selection: $kind) { ForEach(options, id: \.0) { Label($0.1, systemImage: KindGlyph.symbol($0.0)).tag($0.0) } } label: { EmptyView() }
                } label: {
                    DSCapsuleLabel(title: Text(options.first { $0.0 == kind }?.1 ?? "Todo"), symbol: KindGlyph.symbol(kind), trailing: "chevron.down")
                }
                .fixedSize()
                .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
                .sensoryFeedback(.selection, trigger: kind)
            } else if compact {
                // El switch chico del Top 10 (cápsula con lo elegido resaltado), a la derecha del título de su sección.
                DSSegmented(options: options, selection: $kind).fixedSize()
                    .frame(minHeight: DS.Size.touchTarget)   // el mismo renglón que las cápsulas («Ver todo», «Todo ⌄»)
                    .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
            } else {
                DSSegmented(options: options, selection: $kind)
            }
        }
        .accessibilityLabel(Text("Series o películas"))
        .accessibilityIdentifier("kind-filter")
    }

    private var options: [(String, LocalizedStringKey)] {
        let movies: LocalizedStringKey = counts.map { "Películas \($0.movies)" } ?? "Películas"
        let series: LocalizedStringKey = counts.map { "Series \($0.series)" } ?? "Series"
        return (includeAll ? [("", "Todo")] : []) + [("movie", movies), ("series", series)]
    }
}

/// Filtros deslizables (Todo · Trakt · Netflix…): botones nativos en cápsula; el elegido va resaltado.
struct DSChipRow<Item: Hashable & Identifiable, Label: View>: View {
    let items: [Item]
    let label: (Item) -> Label
    @Binding var selection: Item
    /// El valor actual como dato de la vista (ver `DSSegmented`).
    private let current: Item
    /// Hasta dónde está deslizada la tira: el elegido queda a la vista (la temporada 7 de 9 no se esconde a la derecha).
    @State private var scrolled: Item.ID?

    init(items: [Item], @ViewBuilder label: @escaping (Item) -> Label, selection: Binding<Item>) {
        self.items = items; self.label = label; _selection = selection; current = selection.wrappedValue
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(items) { item in
                    Group {
                        if current == item { Button { selection = item } label: { label(item).lineLimit(1) }.buttonStyle(.borderedProminent).foregroundStyle(DS.onPrimary) }
                        else { Button { selection = item } label: { label(item).lineLimit(1) }.buttonStyle(.bordered) }
                    }
                    .buttonBorderShape(.capsule).controlSize(.small)
                    .accessibilityAddTraits(current == item ? .isSelected : [])
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, DS.Space.gutter)
        }
        .scrollPosition(id: $scrolled, anchor: .center)
        .onChange(of: current.id, initial: true) { _, id in scrolled = id }
        .sensoryFeedback(.selection, trigger: current)
    }
}

/// El indicador de brillo o volumen sobre el video, como en Infuse: un ícono y una barra fina que sube o baja
/// con el valor, sobre vidrio nativo. Una sola pieza para los dos gestos (cambia el ícono y el valor).
struct DSGestureIndicator: View {
    let symbol: String
    let value: Double   // 0…1
    /// El largo de la barra: más corta cuando el video es bajito (en vertical va dentro de la imagen).
    var barHeight: CGFloat = DS.Gesture.indicatorBarHeight

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            Image(systemName: symbol).font(DS.TextRecipe.secondary.font).foregroundStyle(DS.text)
            ZStack(alignment: .bottom) {
                Capsule().fill(DS.track)
                Capsule().fill(DS.primary).frame(height: barHeight * min(1, max(0, value)))
            }
            .frame(width: DS.Gesture.indicatorBarWidth, height: barHeight)
            Text("\(Int((value * 100).rounded())) %").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).monospacedDigit()
        }
        .padding(.vertical, DS.Space.s4).padding(.horizontal, DS.Space.s3)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
        .accessibilityHidden(true)
    }
}

/// La burbuja de «buscar arrastrando»: el tiempo destino grande y la diferencia pequeña («+1:20»).
struct DSSeekBubble: View {
    let time: String
    let delta: String

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            Text(time).font(DS.TextRecipe.section.font.weight(.bold)).foregroundStyle(DS.text).monospacedDigit()
            Text(delta).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).monospacedDigit()
        }
        .padding(.horizontal, DS.Space.s5).padding(.vertical, DS.Space.s3)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityHidden(true)
    }
}

/// La píldora «2×» mientras mantienes el dedo (como YouTube/Infuse): sobre vidrio, abajo al centro.
struct DSSpeedPill: View {
    /// Se quedó fijo en ×2 (deslizaste hacia abajo hasta que vibró): dice cómo quitarlo.
    var locked = false
    /// Mientras mantienes: el anillo se llena al deslizar hacia abajo (0…1).
    var progress: Double = 0
    /// El dedo sigue puesto: dice qué hace deslizar.
    var holding = false
    /// Ya iba fijo al apoyar el dedo: deslizar hacia arriba lo quita.
    var unlocks = false
    var body: some View {
        HStack(spacing: DS.Space.s2) {
            if locked && !holding {
                Image(systemName: "lock.fill").font(DS.TextRecipe.footnote.font.weight(.bold)).transition(.scale.combined(with: .opacity))
            } else {
                ZStack {
                    Circle().stroke(DS.track, lineWidth: DS.PlayerPanel.ringWidth)
                    Circle().trim(from: 0, to: progress).stroke(DS.text, style: StrokeStyle(lineWidth: DS.PlayerPanel.ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: DS.PlayerPanel.ring * 0.75, height: DS.PlayerPanel.ring * 0.75)
            }
            Text(verbatim: "2×").font(DS.TextRecipe.secondary.font.weight(.bold))
            if holding {
                (Text(Image(systemName: unlocks ? "arrow.up" : "arrow.down")) + Text(" ")
                    + (unlocks ? Text("Desliza para quitar") : Text("Desliza para fijar")))
                    .font(DS.TextRecipe.footnote.font)
            } else if locked {
                Text("Toca para quitar").font(DS.TextRecipe.footnote.font)
            }
        }
        .foregroundStyle(DS.text)
        .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s2)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(locked ? "speed-pill-locked" : "speed-pill")
    }
}

/// Un aviso breve en una cápsula de vidrio (p. ej. el modo de zoom del reproductor al cambiarlo).
/// `detail`: un segundo renglón más tenue (p. ej. por qué está ahí esa versión de subtítulos).
struct DSToastPill: View {
    let text: LocalizedStringKey
    var detail: Text? = nil
    var body: some View {
        VStack(spacing: 0) {
            Text(text).font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text).contentTransition(.numericText())
            if let detail { detail.recipe(.caption).lineLimit(1) }
        }
            .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s2)
            .glassEffect(.regular, in: Capsule())
    }
}

/// Los dos colores de lo que está al frente (`ArtPalette`, la misma cuenta que la TV): el oscuro tiñe el fondo y el claro es el
/// botón principal y los acentos (`--art-tint` / `--art-accent`).
struct ArtColors: Equatable {
    var tint: Color
    var accent: Color

    init(_ palette: (tint: ArtPalette.RGB, accent: ArtPalette.RGB)) {
        func color(_ c: ArtPalette.RGB) -> Color { Color(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255) }  // ds-exception: el color sale del arte (ArtPalette), no es un valor de diseño
        tint = color(palette.tint); accent = color(palette.accent)
    }

    /// Sin arte: los neutros de la TV (grafito y casi papel).
    static let neutral = ArtColors(ArtPalette.palette(for: nil))
}

/// Fondo de pantalla de Proyección: el color del arte que está al frente ilumina la pantalla desde arriba y se funde con el
/// fondo a media altura. En oscuro, el tono oscuro de la TV (`--art-tint`); en claro, el tono claro (`--art-accent`) como un velo
/// suave sobre el papel. Sin arte, el fondo liso del modo.
struct Backdrop: View {
    var tint: ArtColors?
    /// La ficha: toda la pantalla del color del arte (no solo un velo arriba), en los dos modos.
    var immersive = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DS.bg
            if immersive, let tint {
                LinearGradient(colors: [tint.tint, tint.tint.mix(with: DS.backdropDeep, by: DS.Backdrop.immersiveDeep)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [tint.accent.opacity(DS.Backdrop.immersiveGlow), .clear], center: DS.Backdrop.lowGlowCenter, startRadius: 0, endRadius: DS.Backdrop.immersiveGlowRadius)
            } else if let tone = Self.tone(tint, scheme: scheme) {
                LinearGradient(stops: [.init(color: tone, location: 0), .init(color: DS.bg, location: DS.Backdrop.fadeTo)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [tone.opacity(DS.Backdrop.lowGlow), .clear], center: DS.Backdrop.lowGlowCenter, startRadius: 0, endRadius: DS.Backdrop.lowGlowRadius)
            }
        }
        .ignoresSafeArea()
        .animation(DS.Motion.tint(reduceMotion), value: tint)
        .accessibilityHidden(true)
    }

    /// El color de arriba del fondo (detrás del arte): el tono del arte en oscuro, ese tono muy claro sobre el papel en claro;
    /// nil sin arte. El arte de la ficha se recoge hacia él (`BleedArt(collapse:)`).
    static func tone(_ tint: ArtColors?, scheme: ColorScheme) -> Color? {
        guard let tint else { return nil }
        return scheme == .dark ? tint.tint : tint.accent.mix(with: DS.paper, by: DS.Backdrop.lightMix)
    }
}

/// Lo que va encima del arte (logos, datos, botones sobre el velo): siempre como en la sala oscura, en los dos modos.
extension View {
    func onArt() -> some View { environment(\.colorScheme, .dark) }
}

/// Los colores del arte de lo que está al frente (`ArtPalette`, como la TV): se calculan de una miniatura y se recuerdan.
@MainActor
@Observable
final class ArtTint {
    /// nil: no hay arte (el fondo es el liso del modo y el botón principal, el de siempre).
    private(set) var colors: ArtColors?
    private static var cache: [String: ArtColors] = [:]
    private static let cacheLimit = 64

    /// Lo último que se pidió: gana siempre (un arte anterior que llega tarde no pinta encima del de ahora).
    @ObservationIgnored private var requested: String?

    init() {}
    /// Con el color ya sabido de ese arte (si se calculó antes, en esta sesión o en otra): la pantalla aparece ya pintada,
    /// sin esperar ni fundirse.
    init(cachedFor url: String?) { colors = url.flatMap(Self.known) }

    /// El color de un arte si ya se sabe: de memoria o del que se guardó en el teléfono (los últimos).
    static func known(_ url: String) -> ArtColors? {
        if let hit = cache[url] { return hit }
        guard let saved = UserDefaults.standard.dictionary(forKey: diskKey)?[url] as? [Int], saved.count == 6 else { return nil }
        let found = ArtColors(((saved[0], saved[1], saved[2]), (saved[3], saved[4], saved[5])))
        cache[url] = found
        return found
    }

    private static let diskKey = "art-tint-colors"

    /// Se guarda en el teléfono (unos cuantos): la próxima vez que abras la app, la pantalla ya sale con su color.
    private static func save(_ url: String, _ palette: (tint: ArtPalette.RGB, accent: ArtPalette.RGB)) {
        var saved = UserDefaults.standard.dictionary(forKey: diskKey) ?? [:]
        if saved.count >= cacheLimit { saved.removeAll() }
        saved[url] = [palette.tint.r, palette.tint.g, palette.tint.b, palette.accent.r, palette.accent.g, palette.accent.b]
        UserDefaults.standard.set(saved, forKey: diskKey)
    }

    func load(_ url: String?) async {
        requested = url
        guard let url, let u = URL(string: url) else { colors = nil; return }
        if let hit = Self.known(url) { colors = hit; return }
        // Basta una miniatura para sacar el tono dominante: nunca se decodifica el fondo completo.
        let palette: (tint: ArtPalette.RGB, accent: ArtPalette.RGB)?
        if let thumb = await ImagePipeline.shared.image(u, maxPixel: DS.Image.tintPixels) {
            palette = await Task.detached(priority: .utility, operation: { thumb.rgbaPixels.map { ArtPalette.palette(for: ArtPalette.dominantHue(rgba: $0)) } }).value
        } else { palette = nil }
        guard requested == url, !Task.isCancelled else { return }
        guard let palette else { colors = nil; return }   // sin arte: fondo liso, no el color del título anterior
        let found = ArtColors(palette)
        if Self.cache.count >= Self.cacheLimit { Self.cache.removeAll() }
        Self.cache[url] = found
        Self.save(url, palette)
        colors = found
    }
}

/// ¿Es oscuro un logo? Su color medio pesado por la opacidad (los logos son PNG con fondo transparente), de una miniatura.
/// Se recuerda por URL.
@MainActor
/// Los logos sin su margen transparente, recortados una vez (fuera del hilo principal) y recordados.
enum LogoTrim {
    @MainActor private static var cache: [URL: UIImage] = [:]

    @MainActor static func cached(_ url: URL) -> UIImage? { cache[url] }

    @MainActor static func load(_ url: URL) async -> UIImage? {
        guard let image = await ImagePipeline.shared.image(url, maxPixel: DS.Image.logo * ImagePipeline.screenScale) else { return nil }
        let result = await Task.detached(priority: .userInitiated) { image.trimmingTransparentEdges() ?? image }.value
        cache[url] = result
        return result
    }
}

enum LogoTone {
    // En el hilo principal, como `LogoTrim`: varios logos a la vez (el carrusel de Inicio enseña tres) escribían el diccionario
    // desde hilos distintos y la app se cerraba.
    @MainActor private static var cache: [URL: Bool] = [:]

    @MainActor static func isDark(_ url: URL) async -> Bool {
        if let hit = cache[url] { return hit }
        guard let thumb = await ImagePipeline.shared.image(url, maxPixel: DS.Image.tintPixels),
              let tone = await Task.detached(priority: .utility, operation: { thumb.opaqueTone }).value else { return false }
        // Oscuro y sin color (un logo negro): se pinta claro. Con color (el anillo de Dune) se respeta tal cual.
        let dark = tone.luminance < DesignTokens.Opacity.darkLogoLuminance && tone.colorful < DesignTokens.Opacity.colorfulLogoShare
        cache[url] = dark
        return dark
    }
}

extension UIImage {
    /// La imagen sin las orillas totalmente transparentes (nil si no hay nada que recortar o no se puede leer).
    func trimmingTransparentEdges() -> UIImage? {
        guard let cg = cgImage, let pixels = rgbaPixels else { return nil }
        let w = cg.width, h = cg.height
        var top = h, bottom = -1, left = w, right = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where pixels[row + x * 4 + 3] > 8 {
                if y < top { top = y }; if y > bottom { bottom = y }
                if x < left { left = x }; if x > right { right = x }
            }
        }
        guard bottom >= top, right >= left, (top > 0 || left > 0 || bottom < h - 1 || right < w - 1),
              let cropped = cg.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }

    /// Los píxeles en RGBA de 8 bits (para `ArtPalette`).
    var rgbaPixels: [UInt8]? {
        guard let cg = cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }

    /// La luminancia media de los píxeles visibles (0…1, sin contar los transparentes) y qué parte de ellos tiene color;
    /// nil si no hay nada visible.
    var opaqueTone: (luminance: Double, colorful: Double)? {
        guard let cg = cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0, weight = 0.0, colorful = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3]) / 255
            guard a > 0.1 else { continue }
            let r = Double(pixels[i]) / 255 / a, g = Double(pixels[i + 1]) / 255 / a, b = Double(pixels[i + 2]) / 255 / a
            sum += (0.2126 * r + 0.7152 * g + 0.0722 * b) * a; weight += a
            if max(r, g, b) - min(r, g, b) > 0.25 { colorful += a }
        }
        return weight > 0 ? (sum / weight, colorful / weight) : nil
    }


    /// El color promedio, con un filtro de Core Image (1 píxel).
    var averageColor: UIColor? {
        guard let input = CIImage(image: self) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)  // ds-exception: el color sale de los píxeles del póster, no es un valor de diseño
    }
}

/// Un tamaño de archivo con un solo formato en toda la app: GB y TB con un decimal, MB y KB sin decimales
/// («2,4 GB», «350 MB»). Así la leyenda del espacio y las secciones de Descargas dicen lo mismo.
enum ByteSize {
    static func text(_ n: Int64, locale: Locale) -> String {
        let units: [(Double, String)] = [(1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB")]
        let value = Double(max(0, n))
        guard let (size, unit) = units.first(where: { value >= $0.0 }) else { return "0 KB" }
        let digits = size >= 1e9 ? 1 : 0
        return "\((value / size).formatted(.number.precision(.fractionLength(digits)).locale(locale))) \(unit)"
    }
}

/// El espacio del iPhone como en Ajustes › Almacenamiento: una barra con lo de Orbital (series y películas, en su color),
/// lo demás del teléfono en gris y lo libre vacío; abajo, la leyenda. Con poco espacio libre, el dato se pone en ámbar.
struct StorageBar: View {
    struct Part: Identifiable { let id: String; let label: Text; let bytes: Int64; let color: Color }
    let parts: [Part]
    let free: Int64
    let total: Int64
    let format: (Int64) -> String

    var body: some View {
        let others = max(0, total - free - parts.reduce(0) { $0 + $1.bytes })
        let low = total > 0 && Double(free) / Double(total) < DS.Storage.lowFraction
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Espacio").recipe(.cardTitle).fontWeight(.semibold)
                Spacer()
                Text("\(format(free)) libres de \(format(total))").recipe(.footnote, color: low ? DS.warning : DS.textMuted)
            }
            GeometryReader { geo in
                HStack(spacing: DS.Storage.gap) {
                    ForEach(parts) { part in segment(part.bytes, width: geo.size.width, color: part.color) }
                    segment(others, width: geo.size.width, color: DS.textFaint)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.fill)
                .clipShape(Capsule())
            }
            .frame(height: DS.Storage.height)
            // En renglón; si no cabe (letra grande, iPhone chico), uno debajo del otro: sin «Series…».
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s3) { legends }
                VStack(alignment: .leading, spacing: DS.Space.s1) { legends }
            }
        }
        .padding(.vertical, DS.Space.s1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var legends: some View {
        ForEach(parts) { part in legend(part.label + Text(verbatim: " \(format(part.bytes))"), color: part.color) }
        legend(Text("Otras apps"), color: DS.textFaint)
    }

    private func segment(_ bytes: Int64, width: CGFloat, color: Color) -> some View {
        let fraction = total > 0 ? CGFloat(bytes) / CGFloat(total) : 0
        return Rectangle().fill(color).frame(width: bytes > 0 ? max(DS.Storage.minSegment, width * fraction) : 0)
    }

    private func legend(_ text: Text, color: Color) -> some View {
        HStack(spacing: DS.Space.s1) {
            Circle().fill(color).frame(width: DS.Storage.dot, height: DS.Storage.dot)
            text.recipe(.caption, color: DS.textMuted).lineLimit(1)
        }
    }
}

extension VerticalAlignment {
    /// El centro del título de una sección: ahí se alinea lo de la derecha (aunque arriba haya una línea ámbar).
    private enum SectionTitle: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] } }
    static let sectionTitle = VerticalAlignment(SectionTitle.self)
}

/// «Ver todo ›»: en una cápsula tenue, a la altura del título (la misma en toda la app).
struct SeeAllLabel: View {
    var body: some View { DSCapsuleLabel(title: Text("Ver todo"), symbol: "chevron.forward", symbolFirst: false) }
}

/// La cápsula tenue de lo que va a la derecha de un título de sección («Ver todo ›», «📅 Octubre», «Todo ⌄»).
struct DSCapsuleLabel: View {
    let title: Text
    let symbol: String
    var symbolFirst = true
    /// Elegido (un filtro puesto): en papel, como las opciones en cápsula.
    var selected = false
    /// Todo el ancho que le den (varias en rejilla, todas parejas); si no, lo de su texto.
    var stretch = false
    /// Un glifo a la derecha además del de la izquierda (el ⌄ de un menú en una cápsula con ícono).
    var trailing: String?

    var body: some View {
        HStack(spacing: DS.HeaderControl.iconGap) {
            if symbolFirst { icon(symbol) }
            title.font(DS.TextRecipe.secondary.font.weight(.semibold)).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            if !symbolFirst { icon(symbol) }
            if let trailing { icon(trailing) }
        }
        .foregroundStyle(selected ? DS.onPrimary : DS.text)
        .padding(.horizontal, DS.HeaderControl.padding)
        .frame(maxWidth: stretch ? .infinity : nil)
        .frame(height: DS.HeaderControl.height)
        .background(selected ? DS.primary : DS.fillStrong, in: Capsule())
        .frame(minHeight: DS.Size.touchTarget)   // se ve de 32 pt; se toca en 44
        .contentShape(Rectangle())
        .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
    }

    private func icon(_ name: String) -> some View { Image(systemName: name).font(DS.TextRecipe.footnote.font.weight(.bold)).imageScale(.small) }
}

extension Text {
    /// La bandera de un idioma antes de su nombre («🇲🇽 Latino»), con su espacio; VoiceOver no la lee (dice solo el nombre).
    /// Sin bandera conocida (el árabe, un código raro), nada. Varios idiomas, varias banderas («🇺🇸🇲🇽 Inglés + latino»).
    static func flag(_ codes: [String]) -> Text {
        let flagged = LanguageFlags.flagged("", codes)
        return flagged.isEmpty ? Text(verbatim: "") : Text(verbatim: flagged + " ").accessibilityLabel(Text(verbatim: ""))
    }
    static func flag(_ code: String?) -> Text { flag(code.map { [$0] } ?? []) }

    /// Un texto que ya trae sus banderas al principio («🇲🇽 Latino · 1080p»): igual a la vista, pero VoiceOver no las lee.
    static func flagged(_ string: String) -> Text {
        let rest = LanguageFlags.withoutFlags(string)
        guard rest.count < string.count, string.hasSuffix(rest) else { return Text(verbatim: string) }
        return Text(verbatim: String(string.dropLast(rest.count))).accessibilityLabel(Text(verbatim: "")) + Text(verbatim: rest)
    }
}

/// Una tira horizontal que no cabe (las temporadas de «Episodios»): en vez de cortarse en seco, se desvanece en la orilla
/// donde hay más. A la izquierda solo cuando ya la recorriste; a la derecha mientras quede algo por ver.
private struct HorizontalEdgeFade: ViewModifier {
    @State private var more = EdgeMore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct EdgeMore: Equatable { var leading = false, trailing = false }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: EdgeMore.self) { g in
                EdgeMore(leading: g.visibleRect.minX > 1, trailing: g.visibleRect.maxX < g.contentSize.width - 1)
            } action: { _, now in
                withAnimation(DS.Motion.base(reduceMotion)) { more = now }
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [more.leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing).frame(width: DS.Size.edgeFade)
                    Color.black
                    LinearGradient(colors: [.black, more.trailing ? .clear : .black], startPoint: .leading, endPoint: .trailing).frame(width: DS.Size.edgeFade)
                }
            }
    }
}

extension View {
    /// Desvanece las orillas de un `ScrollView` horizontal que no cabe (ver `HorizontalEdgeFade`).
    func edgeFade() -> some View { modifier(HorizontalEdgeFade()) }
}

