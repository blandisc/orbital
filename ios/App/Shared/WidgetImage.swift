import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UIKit
import WidgetKit

/// Las imágenes de los widgets, de los dos lados del App Group.
///
/// La app guarda cada imagen con más resolución de la que pide el lugar más grande donde sale (`save`); el widget la lee ya
/// recortada y reducida al tamaño exacto de su hueco en pixeles (`fill`, `fit`). Así se ve nítida en cualquier tamaño y nunca
/// pasa del límite de WidgetKit: una imagen más grande que su widget hace que iOS no la dibuje (bloques grises) y una enorme
/// llena la memoria corta de la extensión. Antes la app guardaba todo a 300 px y el widget lo estiraba: en el grande, la
/// imagen ancha se veía borrosa (Fernando, 2 nov 2026: «le llegan capturas de muy baja calidad»).
enum WidgetImage {
    /// Dónde se ancla el recorte de una imagen que llena su hueco: arriba (pósters y fondos, para no cortar cabezas) o al centro.
    enum Anchor { case top, center }

    // MARK: La app: reducir y guardar

    /// La imagen reducida a `maxPixels` en su lado largo (nunca la agranda), en JPEG o, para logos, en PNG (con transparencia).
    static func reduce(_ data: Data, maxPixels: Double, png: Bool = false, quality: Double) -> (data: Data, image: UIImage)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // Con tipos explícitos: el Xcode de la CI no junta solo el CGFloat del tamaño con el Double del tope.
        let size: CGSize? = pixelSize(source)
        let long: Double = size.map { Double(max($0.width, $0.height)) } ?? maxPixels
        let side: Int = Int(min(long, maxPixels).rounded())
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: side]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        guard let bytes = png ? image.pngData() : image.jpegData(compressionQuality: quality) else { return nil }
        return (bytes, image)
    }

    // MARK: El widget: leer al tamaño del hueco

    /// La imagen del archivo recortada para llenar `size` (puntos) y reducida a esos puntos × `scale`: ni un pixel de más.
    static func fill(_ url: URL, size: CGSize, scale: CGFloat, anchor: Anchor) -> UIImage? {
        guard size.width > 0, size.height > 0, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let original = pixelSize(source) else { return nil }
        let target = CGSize(width: (size.width * scale).rounded(.up), height: (size.height * scale).rounded(.up))
        // Lo que mide la imagen reducida para cubrir el hueco (sin agrandarla: si es más chica, se pinta tal cual y la estira SwiftUI).
        let factor = min(1, max(target.width / original.width, target.height / original.height))
        let long = (max(original.width, original.height) * factor).rounded(.up)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(1, Int(long))]
        guard let reduced = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // El recorte con la proporción del hueco, del tamaño que alcance la imagen.
        let w = CGFloat(reduced.width), h = CGFloat(reduced.height)
        let aspect = target.width / target.height
        let cropW = min(w, h * aspect), cropH = min(h, w / aspect)
        let x = ((w - cropW) / 2).rounded(.down)
        let y = anchor == .top ? 0 : ((h - cropH) / 2).rounded(.down)
        let cropped = reduced.cropping(to: CGRect(x: x, y: y, width: cropW.rounded(.down), height: cropH.rounded(.down))) ?? reduced
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }

    /// La imagen completa (un logo) reducida para caber en `box` (puntos) × `scale`.
    static func fit(_ url: URL, box: CGSize, scale: CGFloat) -> UIImage? {
        guard box.width > 0, box.height > 0, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let original = pixelSize(source) else { return nil }
        let factor = min(1, box.width * scale / original.width, box.height * scale / original.height)
        let long = (max(original.width, original.height) * factor).rounded(.up)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(1, Int(long))]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
    }

    private static func pixelSize(_ source: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double, let h = props[kCGImagePropertyPixelHeight] as? Double, w > 0, h > 0 else { return nil }
        // Con la orientación de la foto (EXIF 5…8 va girada).
        let rotated = ((props[kCGImagePropertyOrientation] as? Int) ?? 1) >= 5
        return rotated ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }
}

/// Una imagen del App Group que llena su hueco, ya recortada y reducida a su tamaño exacto (`WidgetImage.fill`). Sin archivo,
/// o si no se puede leer, enseña `placeholder`.
struct WidgetFillImage<Placeholder: View>: View {
    var url: URL?
    var anchor: WidgetImage.Anchor = .top
    @ViewBuilder var placeholder: () -> Placeholder
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { proxy in
            if let url, let image = WidgetImage.fill(url, size: proxy.size, scale: scale, anchor: anchor) {
                Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor)   // en la pantalla tintada, el arte sigue siendo foto
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                placeholder().frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

extension WidgetFillImage where Placeholder == Color {
    init(url: URL?, anchor: WidgetImage.Anchor = .top) { self.init(url: url, anchor: anchor) { Color.clear } }
}

/// Una imagen del App Group completa dentro de su hueco, sin recortar (`WidgetImage.fit`): lo que sobra queda en `bars` (las
/// franjas negras de una tele vieja). Sin archivo, enseña `placeholder`.
struct WidgetFitImage<Placeholder: View>: View {
    var url: URL?
    var bars: Color
    @ViewBuilder var placeholder: () -> Placeholder
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { proxy in
            if let url, let image = WidgetImage.fit(url, box: proxy.size, scale: scale) {
                ZStack {
                    bars
                    Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                placeholder().frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

/// El arte de un widget chico como fondo. En la pantalla de inicio normal va de fondo del widget; en la tintada o transparente
/// (iOS 26) iOS quita ese fondo y el widget se quedaba sin imagen: ahí va detrás del contenido, a todo el widget (Fernando,
/// 2 nov 2026).
private struct WidgetArtBackground<Art: View>: ViewModifier {
    @ViewBuilder var art: () -> Art
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.widgetContentMargins) private var margins

    func body(content: Content) -> some View {
        if mode == .fullColor {
            content.containerBackground(for: .widget) { art() }
        } else {
            content
                .background { art().padding(EdgeInsets(top: -margins.top, leading: -margins.leading, bottom: -margins.bottom, trailing: -margins.trailing)) }
                .containerBackground(for: .widget) { Color.clear }
        }
    }
}

extension View {
    /// El arte de fondo de un widget que también se ve en la pantalla tintada (`WidgetArtBackground`).
    func widgetArtBackground<Art: View>(@ViewBuilder _ art: @escaping () -> Art) -> some View { modifier(WidgetArtBackground(art: art)) }
}
