import SwiftUI
import UIKit
import CoreImage
import OrbitalCore

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
        label.font(DS.font(.xs)).lineLimit(1).fixedSize()
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
        Text(text).font(DS.font(.xs, weight: .semibold)).lineLimit(1).foregroundStyle(DS.text)
            .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
            .background(DS.badgeBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }
}

/// El puesto en un Top 10 (chart de Netflix, JustWatch…): una sola pieza, número grande sobre una placa oscura,
/// con el mismo radio que la portada que acompaña (esquina superior izquierda).
struct DSRankBadge: View {
    let rank: Int
    var body: some View {
        Text(verbatim: "\(rank)").font(DS.font(.xl, weight: .bold)).foregroundStyle(DS.text).lineLimit(1)
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
                AsyncImage(url: u) { phase in
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
                Rectangle().fill(DS.primary).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: DS.Space.s1).clipShape(Capsule())
        .accessibilityLabel(Text("Avance")).accessibilityValue(Text("\(Int(fraction * 100)) %"))
    }
}

/// Título de una zona con su dato a la derecha.
struct DSSectionHead: View {
    let title: LocalizedStringKey
    var trailing: LocalizedStringKey?
    /// El logo de la plataforma (Netflix, Disney+…), si la lista es de una: siempre a la misma altura que en los chips.
    var logo: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let logo { DSPlatformLogo(url: logo) }
            Text(title).font(DS.font(.lg, weight: .semibold)).foregroundStyle(DS.text)
            Spacer()
            if let trailing {
                if let action { Button(action: action) { Text(trailing) }.font(DS.font(.sm)).foregroundStyle(DS.textMuted) }
                else { Text(trailing).font(DS.font(.sm)).foregroundStyle(DS.textMuted) }
            }
        }
        .accessibilityAddTraits(.isHeader)
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

    var body: some View {
        if bleed { art.clipped().accessibilityLabel(Text(title)) }
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
                    AsyncImage(url: u) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: placeholder
                        }
                    }
                } else { placeholder }
            }
    }

    /// El fondo marca el tamaño: con proporción, la del póster; sin ella, todo lo que le den.
    @ViewBuilder private var frame: some View {
        let fill = LinearGradient(colors: [DS.surfaceRaised, DS.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
        if let aspect { fill.aspectRatio(aspect, contentMode: .fit) } else { fill }
    }

    private var placeholder: some View {
        Text(title).font(DS.font(.sm, weight: .semibold)).foregroundStyle(DS.textMuted).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(DS.Space.s2)
    }
}

/// Portada con sus etiquetas y su barra de avance.
struct PosterCard: View {
    let title: String
    let poster: String?
    var badge: LocalizedStringKey?
    /// El puesto en un Top 10: sustituye a `badge` en la esquina (una sola pieza, no dos encimadas).
    var rank: Int?
    var progress: Double?
    var width: CGFloat = DS.Poster.railWidth

    var body: some View {
        ZStack(alignment: .topLeading) {
            PosterView(url: poster, title: title)
            if let rank { DSRankBadge(rank: rank).padding(DS.Space.s2) }
            else if let badge { DSBadge(text: badge).padding(DS.Space.s2) }
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
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterView(url: url, title: title, aspect: aspect, bleed: true)
                .overlay(LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: UnitPoint(x: 0.5, y: DS.Backdrop.artFadeStart / 2), endPoint: .bottom))
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: (1 - DS.Backdrop.artFadeStart) / 2),
                                             .init(color: .black, location: DS.Backdrop.artFadeStart),
                                             .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            content().padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s3)
        }
        .frame(minHeight: minHeight)      // con letra grande crece en vez de encimar el texto
        .accessibilityElement(children: .contain)
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

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit().brightness(dark ? 1 : 0)
                    case .failure: name
                    default: name.hidden()     // mientras carga guarda el sitio del nombre: no brinca si el logo llega
                    }
                }
                .frame(maxWidth: DS.Size.cardMax, maxHeight: height, alignment: .leading)
                .shadow(color: DS.scrim, radius: DS.Space.s1)
            } else { name }
        }
        .accessibilityLabel(Text(title))
    }

    private var height: CGFloat { size == .hero ? DS.Size.logoHero : DS.Size.logo }

    private var name: some View {
        // En una pieza, una sola línea (con puntos suspensivos si no cabe): en una columna angosta dos líneas se encimaban con el dato.
        Text(title).font(DS.font(size == .hero ? .xl : .lg, weight: .bold)).foregroundStyle(DS.text)
            .lineLimit(size == .hero ? 2 : 1).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// El destacado de Inicio (`FeatureTile` en la TV): arte a sangre con velo inferior, el logo del título, el dato en el mismo
/// vocabulario que la consola («T2 · E5 · quedan 20 min») y las acciones.
struct HeroCard<Actions: View>: View {
    let title: String
    let detail: String
    let background: String?
    var logo: String?
    var badge: LocalizedStringKey?
    var progress: Double?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        BleedArt(url: background, title: title, minHeight: DS.Poster.heroHeight) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let badge { DSBadge(text: badge) }
                TitleLogo(url: logo, title: title, size: .hero)
                if !detail.isEmpty { Text(detail).font(DS.font(.sm)).foregroundStyle(DS.textMuted).lineLimit(1) }
                actions().padding(.top, DS.Space.s1)
                if let progress { DSProgress(fraction: progress) }
            }
        }
    }
}

/// Un renglón de lista (`RowTile` en la TV): miniatura ancha, nombre y dato. «También tenías» en Inicio.
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
                Text(title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text).lineLimit(2)
                if !detail.isEmpty { Text(detail).font(DS.font(.sm)).foregroundStyle(DS.textMuted).lineLimit(2) }
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
            else { Button(action: action) { Image(systemName: symbol) }.buttonStyle(.glass) }
        }
        .buttonBorderShape(.circle).controlSize(.large)
        .accessibilityLabel(Text(label))
    }
}

/// Un aviso corto con su color (sin conexión, error).
struct DSNotice: View {
    enum Tone { case info, success, warn, error }
    let text: LocalizedStringKey
    var tone: Tone = .info

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: symbol)
            Text(text).font(DS.font(.sm)).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var symbol: String {
        switch tone { case .info: "info.circle"; case .success: "checkmark.circle.fill"; case .warn: "wifi.slash"; case .error: "exclamationmark.triangle.fill" }
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

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            Image(systemName: symbol).font(DS.font(.md)).foregroundStyle(DS.text)
            ZStack(alignment: .bottom) {
                Capsule().fill(DS.track)
                Capsule().fill(DS.primary).frame(height: DS.Gesture.indicatorBarHeight * min(1, max(0, value)))
            }
            .frame(width: DS.Gesture.indicatorBarWidth, height: DS.Gesture.indicatorBarHeight)
            Text("\(Int((value * 100).rounded())) %").font(DS.font(.xs)).foregroundStyle(DS.textMuted).monospacedDigit()
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
            Text(time).font(DS.font(.xl, weight: .bold)).foregroundStyle(DS.text).monospacedDigit()
            Text(delta).font(DS.font(.sm)).foregroundStyle(DS.textMuted).monospacedDigit()
        }
        .padding(.horizontal, DS.Space.s5).padding(.vertical, DS.Space.s3)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityHidden(true)
    }
}

/// La píldora «2×» mientras mantienes el dedo (como YouTube/Infuse): sobre vidrio, arriba al centro.
struct DSSpeedPill: View {
    var body: some View {
        Text(verbatim: "2×").font(DS.font(.md, weight: .bold)).foregroundStyle(DS.text)
            .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s2)
            .glassEffect(.regular, in: Capsule())
            .accessibilityHidden(true)
    }
}

/// Fondo de pantalla (`Backdrop` en la TV): el tono del arte enfocado o abierto tiñe TODA la pantalla (muy oscurecido, como
/// `--art-tint`), con un fundido suave. Sin arte (`tint` nil) y con `space`, el «espacio vivo» de Inicio y Para ti: estrellas muy tenues.
struct Backdrop: View {
    var tint: Color?
    var space = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tone = tint ?? DS.bg
        ZStack {
            DS.bg
            LinearGradient(colors: [tone, tone.mix(with: DS.bg, by: DS.Backdrop.tintFloor)], startPoint: .top, endPoint: .bottom)
            Stars().opacity(space && tint == nil ? 1 : 0)
        }
        .ignoresSafeArea()
        .animation(DS.Motion.tint(reduceMotion), value: tint)
        .accessibilityHidden(true)
    }
}

/// Las estrellas del espacio vivo: puntos fijos y muy tenues, siempre en los mismos lugares (sin movimiento).
private struct Stars: View {
    var body: some View {
        Canvas { context, size in
            var seed = DS.Backdrop.starSeed
            func next() -> Double { seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280); return seed / 233280 }
            for _ in 0..<DS.Backdrop.starCount {
                let x = next() * size.width, y = next() * size.height, grow = 0.5 + next()
                let r = DS.Backdrop.starRadius * grow
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(DS.text.opacity(DS.Backdrop.starOpacity * (0.4 + next() * 0.6))))
            }
        }
    }
}

/// Tono medio de una imagen (para el fondo): se calcula una vez y se recuerda.
@MainActor
final class ArtTint: ObservableObject {
    /// nil: no hay arte (el fondo es el de siempre, con su espacio vivo).
    @Published private(set) var color: Color?
    private static var cache: [String: Color] = [:]
    private static let cacheLimit = 64

    func load(_ url: String?) async {
        guard let url, let u = URL(string: url) else { color = nil; return }
        if let hit = Self.cache[url] { color = hit; return }
        guard let (data, _) = try? await URLSession.shared.data(from: u),
              let average = await Task.detached(priority: .utility, operation: { UIImage(data: data)?.averageColor }).value else { return }
        // Muy oscurecido: mezcla con el grafito más profundo.
        let mixed = Color(uiColor: average).mix(with: DS.backdropDeep, by: 0.55)
        if Self.cache.count >= Self.cacheLimit { Self.cache.removeAll() }
        Self.cache[url] = mixed
        color = mixed
    }
}

extension UIImage {
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
