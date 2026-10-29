import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// Imágenes de la red reducidas al tamaño en que se ven (`ImagePipeline`): reemplaza a `AsyncImage` en toda la app.
/// Una imagen remota (pósters, fondos, logos): la baja `ImagePipeline` reducida al tamaño en que se ve, con caché en
/// memoria y disco compartido por toda la app, y la decodifica fuera del hilo principal. Si ya estaba en memoria
/// aparece en el primer fotograma (sin parpadeo al reciclar la pieza). Mismo contrato que `AsyncImage`.
enum RemoteImagePhase { case loading, success(Image), failure }

struct RemoteImage<Content: View>: View {
    let url: URL
    let maxPoints: CGFloat
    /// La fase y, ya cargada, la forma de la imagen (para decidir si se recorta o va completa, `ArtFit`).
    let content: (RemoteImagePhase, CGSize?) -> Content
    @State private var loaded: UIImage?
    @State private var didFail = false
    @Environment(\.perfTag) private var perfTag

    init(url: URL, maxPoints: CGFloat, @ViewBuilder content: @escaping (RemoteImagePhase) -> Content) {
        self.url = url; self.maxPoints = maxPoints; self.content = { phase, _ in content(phase) }
    }

    init(url: URL, maxPoints: CGFloat, @ViewBuilder sized: @escaping (RemoteImagePhase, CGSize?) -> Content) {
        self.url = url; self.maxPoints = maxPoints; self.content = sized
    }

    var body: some View {
        content(phase, shown?.size).task(id: url) { await load() }
    }

    private var shown: UIImage? {
        loaded ?? ImagePipeline.shared.cached(url, maxPixel: maxPoints * ImagePipeline.screenScale)
    }

    /// La caché se consulta al pintar, no al crear la vista: SwiftUI crea la vista cada vez que se pinta su padre (cada
    /// póster de cada estante), pero solo la vuelve a pintar si cambió algo suyo.
    private var phase: RemoteImagePhase {
        if let shown { return .success(Image(uiImage: shown)) }
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
