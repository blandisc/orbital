import UIKit
import Vision
import CoreML
import os

/// Dónde está lo importante de una imagen (0…1, desde arriba a la izquierda): las caras, y si no hay, lo que llama la atención
/// (Vision, en el teléfono, sin red). Así un recorte grande (un fondo 16:9 en un marco alto) se acomoda al sujeto en vez de al
/// centro: el astronauta de Interstellar, a la izquierda, ya no queda fuera. Se recuerda por imagen, también entre aperturas de
/// la app (un archivo en Caches), y Vision mira una miniatura, no la imagen entera (V7, 10 nov 2026).
enum FocalPoint {
    private struct Memory { var points: [String: CGPoint] = [:]; var loaded = false; var saveScheduled = false }
    nonisolated private static let memory = OSAllocatedUnfairLock(initialState: Memory())
    /// Cuántos puntos se recuerdan (cada uno pesa unas decenas de bytes en el archivo).
    nonisolated static let maxEntries = 2000
    /// El lado mayor de la miniatura que mira Vision: para hallar caras grandes y lo que destaca sobra.
    nonisolated static let thumbPixels = 256
    nonisolated static let writeDelay: Duration = .seconds(3)
    nonisolated private static var file: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Orbital-SWR/focal-points.json")
    }

    nonisolated static func cached(_ key: String) -> CGPoint? {
        memory.withLock { m in
            if !m.loaded {   // la primera vez, lo de aperturas anteriores (un archivo chico)
                m.loaded = true
                m.points = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: CGPoint].self, from: $0) } ?? [:]
            }
            return m.points[key]
        }
    }

    nonisolated private static func remember(_ point: CGPoint, for key: String) {
        _ = cached(key)   // que lo de antes ya esté cargado
        let schedule = memory.withLock { m in
            m.points[key] = point
            if m.points.count > maxEntries { for old in Array(m.points.keys.prefix(maxEntries / 4)) where old != key { m.points[old] = nil } }
            guard !m.saveScheduled else { return false }
            m.saveScheduled = true
            return true
        }
        guard schedule else { return }
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: writeDelay)
            let data = memory.withLock { m in m.saveScheduled = false; return try? JSONEncoder().encode(m.points) }
            guard let data else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    /// El centro si no encuentra nada (así no se vuelve a buscar). Si Vision falla, el centro sin recordarlo.
    static func find(_ image: UIImage, key: String) async -> CGPoint {
        if let hit = cached(key) { return hit }
        let center = CGPoint(x: 0.5, y: 0.5)
        guard let source = image.cgImage else { return center }
        guard let found = await Task.detached(priority: .userInitiated, operation: { locate(thumbnail(source)) }).value else { return center }
        let point = found ?? center
        remember(point, for: key)
        return point
    }

    /// La imagen reducida a `thumbPixels` de lado mayor (la misma proporción: el punto se mide de 0 a 1). Si ya es chica, tal cual.
    private nonisolated static func thumbnail(_ image: CGImage) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > thumbPixels else { return image }
        let scale = CGFloat(thumbPixels) / CGFloat(longest)
        let width = max(1, Int(CGFloat(image.width) * scale)), height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// nil: Vision falló; `.some(nil)`: no hay nada que destaque.
    private nonisolated static func locate(_ image: CGImage) -> CGPoint?? {
        let faces = VNDetectFaceRectanglesRequest(), attention = VNGenerateAttentionBasedSaliencyImageRequest()
        let objects = VNGenerateObjectnessBasedSaliencyImageRequest()
        #if targetEnvironment(simulator)
        // El simulador no tiene el motor neuronal: sin esto, la atención falla y todo quedaba al centro.
        // (`usesCPUOnly` está obsoleto desde iOS 17: se elige el procesador en cada etapa.)
        for request in [faces, attention, objects] as [VNImageBasedRequest] {
            for (stage, devices) in (try? request.supportedComputeStageDevices) ?? [:] {
                request.setComputeDevice(devices.first { if case .cpu = $0 { true } else { false } }, for: stage)
            }
        }
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
