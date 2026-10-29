import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// El tono del arte tiñe la pantalla: `ArtColors`, `Backdrop`, `ArtTint` (lee los píxeles) y el recorte del logo.
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
