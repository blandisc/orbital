import SwiftUI

/// Arriba de Inicio: el logotipo de la app como en la TV y la computadora (el planeta, «orbital» y su luna), en lugar del
/// saludo. Al abrir, el anillo se dibuja y la luna cae en su lugar.
struct AppMark: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let compact = WindowMetrics.size.width < DS.Size.compactWidth
        let ui = env.ui
        OrbitalWordmark(size: compact ? DS.Size.headerWordmarkCompact : DS.Size.headerWordmark, animated: true, showsMark: !compact)
            .foregroundStyle(DS.text).fixedSize()
            // La entrada de la app termina justo aquí (sin el planeta, en un iPhone angosto, ya no calza: ahí se desvanece).
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if !compact { ui.homeLogoFrame = $0 } }
            .onDisappear { ui.homeLogoFrame = nil }
            .opacity(ui.splashing ? 0 : 1)
    }
}

/// El logo de un estudio al frente de su tarjeta, sobre una cápsula clara (muchos logos son oscuros); sin logo, su nombre.
struct StudioEmblem: View {
    let name: String
    var logo: String?

    var body: some View {
        Group {
            if let url = logo.flatMap(URL.init(string:)) {
                RemoteImage(url: url, maxPoints: DS.Collections.studioLogoWidth) { phase in
                    switch phase {
                    // El logo en blanco (como la TV: brightness(0) invert(1)), sin cápsula.
                    case .success(let image): image.resizable().scaledToFit().brightness(-1).colorInvert()
                    default: nameText.padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2).background(DS.paper, in: Capsule())
                    }
                }
                .frame(width: DS.Collections.studioLogoWidth, height: DS.Collections.studioLogoHeight)
            } else {
                // Sin logo, el nombre en cápsula.
                nameText.padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2).background(DS.paper, in: Capsule())
            }
        }
        .shadow(DS.Elevation.high.drop(0))
        .padding(.horizontal, DS.Space.s2)
        .accessibilityHidden(true)
    }

    private var nameText: some View {
        Text(verbatim: name).recipe(.cardTitle, color: DS.backdropDeep).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
    }
}

/// El emblema de una temporada o un género al pie de su tarjeta: su ícono blanco (Grok Imagine, en `Assets.xcassets/Collections`)
/// y su nombre debajo, con el mismo trato que el logo de un estudio. Al abrir la lista, solo el ícono en grande con el halo de su color.
struct CollectionIconEmblem: View {
    let slug: String
    let name: String
    var size: CGFloat = DS.Collections.iconEmblem
    var glow: Color?

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            // A color (estilo de Grok Imagine): se leen en claro y en oscuro.
            Image("Collections/" + slug).resizable().scaledToFit()
                .frame(width: size, height: size)
                // Un resplandor del color del fondo detrás: se lee aunque caiga sobre los pósters.
                .background { Circle().fill(DS.bg).opacity(DS.Collections.iconBackdrop).blur(radius: DS.Collections.glow).scaleEffect(DS.Collections.iconBackdropScale) }
                .shadow(color: glow ?? .clear, radius: DS.Collections.glow)
            if glow == nil {
                Text(verbatim: name).recipe(.caption, color: DS.text).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            }
        }
        .shadow(DS.Elevation.high.drop(0))
        .padding(.horizontal, DS.Space.s2)
        .accessibilityHidden(true)
    }
}

/// Una tira de tarjetas (Plataformas, Premios, Estudios, Por año) desde la orilla izquierda: las que van saliendo por los
/// lados se encogen y oscurecen un poco.
struct CenteredCarousel<Item, ID: Hashable, Card: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    let cardWidth: CGFloat
    /// Con el reflejo de cada tarjeta debajo: el carrusel se lo pide a sus tarjetas (`rowReflection`) y ajusta el aire con lo que
    /// sigue (`reflectionTail`). La pantalla no ajusta nada a mano.
    var reflected = false
    @ViewBuilder var card: (Item) -> Card

    var body: some View {
        if reflected { carousel.environment(\.railReflected, true).reflectionTail() } else { carousel }
    }

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                ForEach(items, id: id) { item in
                    card(item)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content.scaleEffect(1 - abs(phase.value) * DS.Collections.sideShrink)
                                .brightness(-abs(phase.value) * DS.Collections.sideFade)   // más oscuras, como en el carrusel de Inicio
                        }
                }
            }
            .scrollTargetLayout()
        }
        // Desde la orilla izquierda, como el resto de las tiras (sin espacio muerto antes de la primera).
        .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

/// `rowReflection`: el reflejo si la fila lo pide.
private struct RowReflection: ViewModifier {
    var weight: Color?
    @Environment(\.railReflected) private var on
    func body(content: Content) -> some View {
        if on { content.modifier(Reflection(weight: weight)) } else { content }
    }
}

/// El reflejo de una tarjeta sobre el piso (la tarjeta volteada, corta, un poco desenfocada y que se desvanece) y su peso:
/// una sombra de su color solo bajo la tarjeta (en el reflejo dibujaba esquinas que no existen).
struct Reflection: ViewModifier {
    var weight: Color?
    func body(content: Content) -> some View {
        content
            .shadow(color: (weight ?? .clear).opacity(DS.Collections.weightTint), radius: DS.Collections.weight, y: DS.Collections.weightY)
            // La copia volteada va encima del mismo tamaño que el original (un `overlay` le da su ancho y alto): antes se le daban
            // 44 pt de alto y un póster, que guarda su proporción, se encogía a lo ancho (el reflejo «estrecho»). Su borde de
            // arriba se pega al de abajo del original y solo se ve una franja que se desvanece.
            .overlay(alignment: .bottom) {
                content
                    .scaleEffect(x: 1, y: -1)
                    .blur(radius: DS.Collections.reflectionBlur)
                    .mask(alignment: .top) {
                        LinearGradient(colors: [DS.text.opacity(DS.Collections.reflectionOpacity), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: DS.Collections.reflection)
                    }
                    .alignmentGuide(.bottom) { d in d[.top] - DS.Collections.reflectionGap }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, DS.Collections.reflection + DS.Collections.reflectionGap)
    }
}

extension View {
    /// El reflejo de un póster (solo el arte, no la tarjeta con su texto, sus marcas ni su punto de zoom): una franja volteada
    /// que se desvanece, del ancho del póster.
    func posterReflection(_ url: String?, title: String, width: CGFloat) -> some View {
        overlay(alignment: .bottom) {
            PosterView(url: url, title: title).frame(width: width)
                .scaleEffect(x: 1, y: -1)
                .blur(radius: DS.Collections.reflectionBlur)
                .mask(alignment: .top) {
                    LinearGradient(colors: [DS.text.opacity(DS.Collections.reflectionOpacity), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: DS.Collections.reflection)
                }
                .alignmentGuide(.bottom) { d in d[.top] - DS.Collections.reflectionGap }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.bottom, DS.Collections.reflection + DS.Collections.reflectionGap)
    }

    /// Una fila que termina en reflejo (sin texto debajo): lo que sigue se monta sobre la parte desvanecida. Lo aplican solas
    /// las filas con `reflected: true` (`Rail`, `Shelf`, `CenteredCarousel`); una pantalla no lo pone a mano.
    func reflectionTail() -> some View { padding(.bottom, -DS.Collections.reflectionTail) }

    /// El reflejo de una tarjeta, solo si su fila lo pide (`reflected: true`): la fila decide, no cada tarjeta.
    func rowReflection(weight: Color? = nil) -> some View { modifier(RowReflection(weight: weight)) }

    /// Con su reflejo debajo y, si se da, el peso de su color (Colecciones).
    func reflected(weight: Color? = nil) -> some View { modifier(Reflection(weight: weight)) }
}
