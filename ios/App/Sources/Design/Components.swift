import SwiftUI
import UIKit
import CoreImage
import OrbitalCore

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Button, Sheet.

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
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
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

    var body: some View {
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
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.hairline))
            .accessibilityLabel(Text(title))
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
    var progress: Double?
    var width: CGFloat = DS.Poster.railWidth

    var body: some View {
        ZStack(alignment: .topLeading) {
            PosterView(url: poster, title: title)
            if let badge { DSBadge(text: badge).padding(DS.Space.s2) }
            if let progress { VStack { Spacer(); DSProgress(fraction: progress) } }
        }
        .frame(width: width)
        .accessibilityElement(children: .combine)
    }
}

/// El destacado de Inicio y la ficha: arte a sangre con el título y sus botones.
struct HeroCard<Actions: View>: View {
    let title: String
    let detail: String
    let background: String?
    var badge: LocalizedStringKey?
    var progress: Double?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterView(url: background, title: title, aspect: nil)
            LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let badge { DSBadge(text: badge) }
                Text(title).font(DS.font(.xl, weight: .bold)).foregroundStyle(DS.text).lineLimit(2)
                Text(detail).font(DS.font(.sm)).foregroundStyle(DS.textMuted).lineLimit(1)
                actions().padding(.top, DS.Space.s1)
                if let progress { DSProgress(fraction: progress) }
            }
            .padding(DS.Space.s4)
        }
        .frame(height: DS.Poster.heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl))
        .accessibilityElement(children: .contain)
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
struct DSChipRow<Item: Hashable & Identifiable>: View {
    let items: [Item]
    let label: (Item) -> Text
    @Binding var selection: Item
    /// El valor actual como dato de la vista (ver `DSSegmented`).
    private let current: Item
    /// Hasta dónde está deslizada la tira: el elegido queda a la vista (la temporada 7 de 9 no se esconde a la derecha).
    @State private var scrolled: Item.ID?

    init(items: [Item], label: @escaping (Item) -> Text, selection: Binding<Item>) {
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

/// Fondo de pantalla: el tono del título que ves, muy oscurecido (como `--art-tint` en la TV).
struct TintedBackground: View {
    var tint: Color = DS.bg
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LinearGradient(colors: [tint, DS.bg], startPoint: .top, endPoint: .center)
            .background(DS.bg)
            .ignoresSafeArea()
            .animation(DS.Motion.tint(reduceMotion), value: tint)
    }
}

/// Tono medio de una imagen (para el fondo): se calcula una vez y se recuerda.
@MainActor
final class ArtTint: ObservableObject {
    @Published private(set) var color: Color = DS.bg
    private static var cache: [String: Color] = [:]
    private static let cacheLimit = 64

    func load(_ url: String?) async {
        guard let url, let u = URL(string: url) else { return }
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

private extension UIImage {
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
