import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// El arte como luz: arte a sangre, logo del título, el destacado (`HeroCard`) y el renglón con miniatura (`RowTile`).
/// Arte a sangre (de borde a borde, sin esquinas) que se funde con el fondo por abajo con una máscara de gradiente: el
/// destacado de Inicio y el encabezado de la ficha (`.title__backdrop` y el arte del `FeatureTile` en la TV). Lo que va encima
/// (`content`) queda abajo, sobre el velo, y no se desvanece.
struct BleedArt<Content: View>: View {
    let url: String?
    let title: String
    /// Sin proporción llena el espacio que le den (con un mínimo, como el destacado); con ella, esa relación (la de la ficha).
    var aspect: CGFloat?
    var minHeight: CGFloat = 0
    /// Dentro de un `ScrollView` (la ficha): al desplazar, el arte se difumina y se desvanece hacia el fondo que de verdad
    /// tiene detrás; nunca enseña su orilla ni lleva un color pintado encima (AR1, 13 nov 2026). Ver `DS.TitleHero` y
    /// `OrbitalModels.HeroCollapse`. false: arte quieto (el destacado de Inicio).
    var collapses = false
    /// «Ver» hace crecer el video desde aquí: el origen del zoom es un marco quieto detrás del arte, no el arte (su recorte
    /// cortaba lo que se movía al desplazar).
    var zoom: PlayerZoomID? = nil
    /// Si el arte no carga, esta otra (`PosterView.fallback`).
    var fallback: String? = nil
    /// El título: si el marco es alto y tiene póster sin texto, va ese en vez de `url` (`TallArtPicker`).
    var tall: TallArtKey? = nil
    /// El arte se desvanece arriba (el destacado de Inicio). La ficha no: llega sólida hasta arriba, detrás del reloj y de los
    /// botones, con un velo suave para que se lean (como el Mosaico; Fernando, 31 oct 2026).
    var fadesTop = true
    /// Cuánto se subió el arte por encima de su lugar (la ficha lo sube detrás de la barra): en reposo no cuenta como
    /// desplazado (si no, al abrir ya se veía corrido hacia abajo y con el logo desvanecido).
    var raised: CGFloat = 0
    /// El arte respira: si te quedas, se acerca un poco muy despacio y se queda (un solo tramo, como la TV). Quieto con
    /// «Reducir movimiento» y en modo de bajo consumo.
    var breathes = true
    /// Una tarjeta con esquinas también en oscuro y sin margen propio: la portada del tablero de Inicio (MI2), que va junto al
    /// panel de lo tuyo y no de orilla a orilla.
    var tile = false
    /// Un fondo ancho en un marco alto va completo arriba, sin recortarse hacia una orilla (`ArtFit.wholeTop`): el panel de la
    /// ficha en la Mac.
    var keepsWide = false
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Desde cuándo respira (nil: quieto). Ver `Breathing`.
    @State private var breathFrom: Date?
    /// De qué arte es la respiración en curso: volver a la pantalla no la empieza otra vez (22 nov 2026: al volver a Inicio
    /// se reiniciaba y eran 16 s de pasos que hacían lento el cambio de pestaña).
    @State private var breathedURL: String?

    /// «Reducir movimiento» o «Reducir transparencia»: al recogerse, solo se desvanece (sin desenfoque ni estirarse).
    private var quiet: Bool { reduceMotion || reduceTransparency }

    private var isCard: Bool { tile || scheme != .dark }

    var body: some View {
        // En oscuro el arte se funde con el fondo de borde a borde; en claro es una tarjeta con esquinas (la sala oscura no se
        // funde con el papel: el texto claro de encima dejaría de leerse).
        ZStack(alignment: .bottomLeading) {
            Group {
                if !isCard {
                    art.mask(LinearGradient(stops: [.init(color: fadesTop ? .clear : .black, location: 0), .init(color: .black, location: (1 - DS.Backdrop.artFadeStart) / 2),
                                                    .init(color: .black, location: DS.Backdrop.artFadeStart),
                                                    .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                } else {
                    art.clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
                }
            }
            // Al recogerse se va con el contenido, se difumina al final y se desvanece: deja ver el fondo de detrás, el mismo
            // color a los dos lados (en claro, la tarjeta sube nítida). Todo con `visualEffect` (en el render, sin volver a
            // medir ni a dibujar la imagen); al jalar hacia abajo se estira desde abajo.
            .visualEffect { [on = collapses, still = quiet, card = isCard, raised] view, proxy in
                let s = BleedCollapse.state(proxy, on: on, still: still, card: card, raised: raised)
                return view.scaleEffect(s.scale, anchor: .bottom).blur(radius: s.blur).opacity(s.artOpacity)
            }
            .background { if let zoom { Color.clear.playerZoomSource(zoom) } }   // ds-exception: el marco quieto del zoom, no se ve
            // El logo y la frase se van con el contenido y antes que el arte: no se quedan detrás de los datos.
            content().onArt().padding(.horizontal, DS.Space.gutter).padding(.bottom, isCard ? DS.Space.s6 : DS.Space.s2)
                .visualEffect { [on = collapses, still = quiet, card = isCard, raised] view, proxy in
                    let s = BleedCollapse.state(proxy, on: on, still: still, card: card, raised: raised)
                    return view.scaleEffect(s.contentScale, anchor: .bottom).opacity(s.contentOpacity)
                }
        }
        .coordinateSpace(.named(BleedCollapse.space))
        .frame(minHeight: minHeight)      // con letra grande crece en vez de encimar el texto
        .padding(.horizontal, isCard && !tile ? DS.Space.gutter : 0)
        .accessibilityElement(children: .contain)
    }

    private var art: some View {
        // El velo sube hasta donde empieza el texto: rótulo, logo y datos se leen aunque el arte sea claro.
        breathing(aspect: aspect)
            .overlay(ArtVeil(at: DS.Backdrop.scrimStart))
            .overlay(alignment: .top) {
                if !fadesTop { ArtVeil(kind: .top, at: 1).frame(height: DS.TitleHero.topVeil).allowsHitTesting(false).accessibilityHidden(true) }
            }
    }

    private func breathing(aspect: CGFloat?) -> some View {
        TallArtPicker(key: tall, wide: url, tallBox: aspect.map { Double($0) < ArtFit.tallBelow } ?? false) { art, wide in
            // Respira a pasos (`Breathing`), no con `withAnimation` ni con un `TimelineView`: animado, SwiftUI volvía a calcular
            // la pantalla en cada cuadro (165 por segundo en el monitor de la Mac) durante 16 s cada vez que volvías a Inicio, y
            // con un `TimelineView` su reloj seguía corriendo después de terminar (~40 % de CPU con Inicio quieto; Fernando,
            // 17 nov 2026: «muchos problemas de performance en la Mac»).
            Breathing(from: breathFrom) {
                PosterView(url: art, title: title, aspect: aspect, bleed: true, maxPoints: DS.Image.bleed, fallback: wide ?? fallback,
                           waiting: art == nil && url != nil, keepsWide: keepsWide)   // decidiendo póster alto o fondo: el marco quieto
            }
        }
            .task(id: url) {
                if breathFrom != nil, breathedURL == url { return }
                breathFrom = nil; breathedURL = url
                guard breathes, !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
                #if DEBUG
                if Demo.noIdle || MacSelfCheck.off.contains("breath") { return }   // las pruebas de interfaz esperan a que la app esté quieta
                #endif
                try? await Task.sleep(for: .seconds(DS.TitleHero.breatheDelay))   // primero que se asiente lo que acaba de abrir
                guard !Task.isCancelled else { return }
                breathFrom = .now
            }
    }
}

/// El arte que respira: se acerca a `DS.TitleHero.breatheScale` en `breatheDuration`, parejo, a pasos de `breatheFrame` (4 por
/// segundo; cada paso mueve menos de un cuarto de punto: no se nota que va a saltos) y se queda. Solo esta vista se vuelve a pintar, y
/// al terminar ya no hay nada corriendo. Sin `from`, quieto. El acercamiento va en el render (`visualEffect`), no en el acomodo.
struct Breathing<Content: View>: View {
    let from: Date?
    @ViewBuilder let content: () -> Content
    @State private var scale: CGFloat = 1

    var body: some View {
        content()
            .visualEffect { [scale] view, _ in view.scaleEffect(scale) }
            .task(id: from) {
                scale = 1
                guard let from else { return }
                while !Task.isCancelled {
                    let t = min(1, max(0, Date().timeIntervalSince(from) / DS.TitleHero.breatheDuration))
                    scale = 1 + (DS.TitleHero.breatheScale - 1) * CGFloat(t)
                    if t >= 1 { break }
                    try? await Task.sleep(for: .seconds(DS.TitleHero.breatheFrame))
                }
            }
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
    /// Cuánto crece con el escenario de la ficha ancha (`WideStage.grow`): en una pantalla grande un logo apaisado (Dune)
    /// quedaba diminuto.
    var grow: CGFloat = 1
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
                .frame(maxWidth: maxWidth, maxHeight: fittedHeight, alignment: centered ? .bottom : .bottomLeading)
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

    private var height: CGFloat { (size == .hero ? DS.Size.logoHero : DS.Size.logo) * grow }

    /// El alto que de verdad ocupa el logo recortado a lo ancho de siempre (sin pasar del tope).
    private var fittedHeight: CGFloat {
        guard let trimmed, trimmed.size.width > 0, trimmed.size.height > 0 else { return height }
        return min(height, maxWidth * trimmed.size.height / trimmed.size.width)
    }

    /// Lo más ancho del logo; en la portada de la Mac crece como su alto (17 nov 2026: un logo apaisado, como el de «The Odyssey»,
    /// topaba con el ancho y se quedaba chico).
    private var maxWidth: CGFloat { DS.Size.cardMax * (size == .hero && ThisDevice.isMac ? DS.Mac.heroScale : 1) * grow }

    private var name: some View {
        // En una pieza, una sola línea (con puntos suspensivos si no cabe): en una columna angosta dos líneas se encimaban con el dato.
        Text(title).font((size == .hero ? DS.TextRecipe.section : DS.TextRecipe.cardTitle).font).foregroundStyle(DS.text)
            .lineLimit(size == .hero ? 2 : 1).multilineTextAlignment(centered ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

/// La cuenta del recogido de `BleedArt`, fuera de la vista genérica: los cierres de `visualEffect` corren fuera del actor
/// principal y, dentro de la vista, capturaban su tipo (aviso de Swift 6 sobre `Content.Type`).
private enum BleedCollapse {
    nonisolated static var space: String { "bleed-art" }

    /// Cuánto se ha recogido el arte entero (no la capa que pregunta): su lugar en el desplazamiento y su alto salen del
    /// espacio con nombre del arte, así el logo y el arte usan la misma cuenta.
    nonisolated static func state(_ proxy: GeometryProxy, on: Bool, still: Bool, card: Bool, raised: CGFloat = 0) -> HeroCollapse {
        let tuning = HeroCollapse.Tuning(blur: DS.TitleHero.blur, blurFrom: DS.TitleHero.blurFrom, fadeFrom: DS.TitleHero.fadeFrom,
                                         contentFadeEnd: DS.TitleHero.contentFadeEnd, contentShrink: DS.TitleHero.contentShrink)
        guard on, let hero = proxy.bounds(of: .named(space)) else { return HeroCollapse.at(minY: 0, height: 1, reduceMotion: true, tuning: tuning) }
        // `bounds(of:)` es el arte entero visto desde esta capa: su origen es lo que esta capa está corrida dentro del arte.
        let top = proxy.frame(in: .scrollView).minY + hero.minY + raised
        return HeroCollapse.at(minY: top, height: hero.height, reduceMotion: still, card: card, tuning: tuning)
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
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
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

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        HStack(alignment: .center, spacing: DS.Space.s2) {
            ZStack(alignment: .bottom) {
                PosterView(url: thumb, title: title, aspect: DS.Poster.stillAspect)
                if let progress { DSProgress(fraction: progress) }
            }
            .frame(width: DS.Poster.episodeThumbWidth)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).font(DS.TextRecipe.labelLarge.font).foregroundStyle(DS.text).lineLimit(2)
                if !detail.isEmpty { Text(detail).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// Botones: los nativos de iOS 26 (Liquid Glass). Principal: `.dsPrimaryButton()` (vidrio con letra oscura); secundario: `.dsGlassButton()`;
// sobre fondos lisos, `.borderedProminent` / `.bordered`. No hay estilos de botón propios (`DesignTests` lo vigila).


/// A los lados del escenario de la ficha ancha (`WideStage`, el ultrawide): el mismo arte, difuminado y oscurecido, de orilla a
/// orilla. El escenario se funde en él (`StageEdges`): no hay un cuadro al centro ni un hueco negro a la izquierda.
struct StageSides: View {
    let url: String?

    var body: some View {
        Color.clear
            .overlay {
                if let url, let u = URL(string: url) {
                    RemoteImage(url: u, maxPoints: DS.Image.card) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                    }
                }
            }
            .blur(radius: DS.TitleAction.stageSideBlur, opaque: true)
            .overlay(DS.backdropDeep.opacity(DS.TitleAction.stageSideDim))   // el negro del velo, más ligero que `DS.scrim`
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: DS.Backdrop.artFadeStart),
                                         .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Las orillas del escenario se desvanecen hacia sus lados difuminados (`StageSides`); sin lados, el arte va completo.
struct StageEdges: View {
    let on: Bool

    var body: some View {
        if on {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: DS.TitleAction.stageEdgeFade),
                                   .init(color: .black, location: 1 - DS.TitleAction.stageEdgeFade), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        } else { Color.black }
    }
}
