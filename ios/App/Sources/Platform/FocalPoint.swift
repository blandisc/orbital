import UIKit
import Vision

/// Dónde está lo importante de una imagen (0…1, desde arriba a la izquierda): las caras, y si no hay, lo que llama la atención
/// (Vision, en el teléfono, sin red). Así un recorte grande (un fondo 16:9 en un marco alto) se acomoda al sujeto en vez de al
/// centro: el astronauta de Interstellar, a la izquierda, ya no queda fuera. Se recuerda por imagen.
enum FocalPoint {
    private static let cache: NSCache<NSString, NSValue> = { let c = NSCache<NSString, NSValue>(); c.countLimit = 400; return c }()

    static func cached(_ key: String) -> CGPoint? { cache.object(forKey: key as NSString)?.cgPointValue }

    /// El centro si no encuentra nada (así no se vuelve a buscar). Si Vision falla, el centro sin recordarlo.
    static func find(_ image: UIImage, key: String) async -> CGPoint {
        if let hit = cached(key) { return hit }
        let center = CGPoint(x: 0.5, y: 0.5)
        guard let source = image.cgImage else { return center }
        guard let found = await Task.detached(priority: .userInitiated, operation: { locate(source) }).value else { return center }
        let point = found ?? center
        cache.setObject(NSValue(cgPoint: point), forKey: key as NSString)
        return point
    }

    /// nil: Vision falló; `.some(nil)`: no hay nada que destaque.
    private nonisolated static func locate(_ image: CGImage) -> CGPoint?? {
        let faces = VNDetectFaceRectanglesRequest(), attention = VNGenerateAttentionBasedSaliencyImageRequest()
        let objects = VNGenerateObjectnessBasedSaliencyImageRequest()
        #if targetEnvironment(simulator)
        // El simulador no tiene el motor neuronal: sin esto, la atención falla y todo quedaba al centro.
        for request in [faces, attention, objects] as [VNImageBasedRequest] { request.usesCPUOnly = true }
        #endif
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([faces, attention, objects]) } catch { return nil }
        // Las caras grandes (las de los protagonistas, no las del fondo); si no hay, lo que más llama la atención, y si tampoco,
        // el objeto más claro.
        var boxes = (faces.results ?? []).map(\.boundingBox)
        if let biggest = boxes.map({ $0.width * $0.height }).max() { boxes = boxes.filter { $0.width * $0.height >= biggest / 4 } }
        if boxes.isEmpty, let best = strongest(attention) ?? strongest(objects) { boxes = [best] }
        guard let first = boxes.first else { return .some(nil) }
        let area = boxes.dropFirst().reduce(first) { $0.union($1) }
        // Vision mide desde abajo a la izquierda.
        return .some(CGPoint(x: area.midX, y: 1 - area.midY))
    }

    private nonisolated static func strongest(_ request: VNImageBasedRequest) -> CGRect? {
        let objects = (request.results?.first as? VNSaliencyImageObservation)?.salientObjects ?? []
        return objects.max { $0.confidence < $1.confidence }?.boundingBox
    }
}
