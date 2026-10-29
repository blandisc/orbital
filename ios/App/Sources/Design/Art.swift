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
    /// Dentro de un `ScrollView` (la ficha): al desplazar, el arte se recoge hacia este color (el del fondo detrás del arte,
    /// `Backdrop.tone`). Ver `DS.TitleHero` y `OrbitalModels.HeroCollapse`. nil: arte quieto (el destacado de Inicio).
    var collapse: Color? = nil
    /// Si el arte no carga, esta otra (`PosterView.fallback`).
    var fallback: String? = nil
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
        PosterView(url: url, title: title, aspect: aspect, bleed: true, maxPoints: DS.Image.bleed, fallback: fallback)
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
