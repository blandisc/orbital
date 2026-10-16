import UIKit
import ImageIO

/// Todas las imágenes remotas de la app (pósters, fondos y logos de metahub): se bajan con `URLSession`, se reducen
/// con ImageIO al tamaño en que se van a ver (`maxPixel`, el lado más largo) y se guardan reducidas en memoria
/// (`NSCache`) y en disco (`URLCache`, compartido por toda la app). Nada de esto toca el hilo principal salvo
/// `cached`, que solo consulta la memoria (para que una imagen ya cargada aparezca sin parpadeo).
///
/// Antes, `AsyncImage` bajaba y decodificaba cada imagen a tamaño completo (un fondo de metahub son varios
/// megapíxeles) y sin caché propio: con ~96 piezas del mosaico eso bloqueaba la interfaz (CEN-49).
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    /// Lo que cabe en memoria ya reducido y en disco tal como llegó de la red.
    private static let memoryBytes = 96 * 1024 * 1024, diskBytes = 256 * 1024 * 1024, urlMemoryBytes = 8 * 1024 * 1024
    /// Descargas y decodificaciones a la vez: más que esto solo compite por CPU y red con el desplazamiento.
    private static let maxConcurrent = 4
    /// Los tamaños se redondean hacia arriba a este paso de píxeles: dos piezas casi iguales comparten imagen.
    private static let pixelStep = 64

    /// Píxeles por punto de la pantalla (se lee una vez, en el hilo principal).
    @MainActor static let screenScale: CGFloat = {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.scale ?? 3
    }()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let cache: URLCache
    private let lock = NSLock()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var failed: [String: Date] = [:]
    private let limiter = Limiter(limit: ImagePipeline.maxConcurrent)
    private static let retryAfter: TimeInterval = 60

    init() {
        memory.totalCostLimit = Self.memoryBytes
        cache = URLCache(memoryCapacity: Self.urlMemoryBytes, diskCapacity: Self.diskBytes, directory: nil)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = Self.maxConcurrent
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [memory] _ in memory.removeAllObjects() }
    }

    private func key(_ url: URL, _ maxPixel: CGFloat) -> String { "\(url.absoluteString)#\(Self.bucket(maxPixel))" }

    private static func bucket(_ maxPixel: CGFloat) -> Int {
        let steps = Int((max(1, maxPixel) / CGFloat(pixelStep)).rounded(.up))
        return steps * pixelStep
    }

    /// La imagen si ya está reducida en memoria (síncrono, barato).
    func cached(_ url: URL, maxPixel: CGFloat) -> UIImage? { memory.object(forKey: key(url, maxPixel) as NSString) }

    /// ¿Falló hace poco? (no se vuelve a pedir en cada pieza que reaparece).
    func recentlyFailed(_ url: URL, maxPixel: CGFloat) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let date = failed[key(url, maxPixel)] else { return false }
        return Date().timeIntervalSince(date) < Self.retryAfter
    }

    /// La imagen reducida a `maxPixel`: de memoria, de disco o de la red. Varias peticiones de la misma imagen
    /// comparten una sola descarga; cancelar quien espera no cancela la descarga (la siguiente pieza la aprovecha).
    func image(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        let k = key(url, maxPixel)
        if let hit = memory.object(forKey: k as NSString) { return hit }
        let task: Task<UIImage?, Never>
        lock.lock()
        if let existing = inflight[k] { task = existing }
        else {
            let pixels = Self.bucket(maxPixel)
            task = Task.detached(priority: .userInitiated) { [self] in
                let result = await load(url, pixels: pixels)
                lock.lock(); inflight[k] = nil; if result == nil { failed[k] = Date() } else { failed[k] = nil }; lock.unlock()
                if let result { memory.setObject(result, forKey: k as NSString, cost: Self.cost(of: result)) }
                return result
            }
            inflight[k] = task
        }
        lock.unlock()
        return await task.value
    }

    private func load(_ url: URL, pixels: Int) async -> UIImage? {
        await limiter.acquire()
        defer { Task { await limiter.release() } }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        let data: Data
        if let stored = cache.cachedResponse(for: request) { data = stored.data }
        else {
            guard let (fresh, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
            // metahub no siempre manda cabeceras de caché: se guarda a la fuerza para no volver a bajarlo.
            cache.storeCachedResponse(CachedURLResponse(response: response, data: fresh, userInfo: nil, storagePolicy: .allowed), for: request)
            data = fresh
        }
        return Self.downsample(data, maxPixel: pixels)
    }

    /// Reduce con ImageIO sin decodificar la imagen completa, y deja los píxeles ya decodificados (el hilo
    /// principal no paga la decodificación al pintar).
    static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }

    /// Un semáforo asíncrono.
    private actor Limiter {
        private var available: Int
        private var waiters: [CheckedContinuation<Void, Never>] = []
        init(limit: Int) { available = limit }
        func acquire() async {
            if available > 0 { available -= 1; return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() {
            if waiters.isEmpty { available += 1 } else { waiters.removeFirst().resume() }
        }
    }
}
