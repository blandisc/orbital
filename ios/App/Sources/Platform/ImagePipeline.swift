import UIKit
import ImageIO
import OrbitalCore

/// Todas las imágenes remotas de la app (pósters, fondos y logos de metahub): se bajan con `URLSession`, se reducen
/// con ImageIO al tamaño en que se van a ver (`maxPixel`, el lado más largo) y se guardan reducidas en memoria
/// (`NSCache`) y en disco (`URLCache`, compartido por toda la app). Nada de esto toca el hilo principal salvo
/// `cached`, que solo consulta la memoria (para que una imagen ya cargada aparezca sin parpadeo).
///
/// Antes, `AsyncImage` bajaba y decodificaba cada imagen a tamaño completo (un fondo de metahub son varios
/// megapíxeles) y sin caché propio: con ~96 piezas del mosaico eso bloqueaba la interfaz (CEN-49).
///
/// Qué hace rápido el primer arranque (medido en el simulador, caché vacío):
/// - La descarga se comparte por URL, no por tamaño: el tono del fondo (48 px) y el arte (1440 px) de la misma imagen
///   ya no la bajan dos veces a la vez.
/// - Lo que ya está en disco no hace fila detrás de las descargas.
/// - Hasta 12 descargas a la vez (metahub va por HTTP/2: una sola conexión) y 4 decodificaciones; la fila atiende primero
///   lo más reciente, que es lo que está en pantalla.
/// - Si todas las piezas que esperaban una imagen se fueron (el mosaico subió, el estante se deslizó), la descarga se cancela.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    /// Lo que cabe en memoria ya reducido y en disco tal como llegó de la red.
    private static let memoryBytes = 96 * 1024 * 1024, diskBytes = 384 * 1024 * 1024, urlMemoryBytes = 8 * 1024 * 1024
    /// Descargas a la vez (HTTP/2 las lleva por una sola conexión) y decodificaciones a la vez (más compite por CPU con el desplazamiento).
    private static let maxDownloads = 12, maxDecodes = 4
    /// Los tamaños se redondean hacia arriba a este paso de píxeles: dos piezas casi iguales comparten imagen.
    private static let pixelStep = 64

    /// Píxeles por punto de la pantalla (se lee una vez, en el hilo principal).
    @MainActor static let screenScale: CGFloat = {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.scale ?? 3
    }()

    private let memory = NSCache<NSString, UIImage>()
    /// Los bytes recién bajados, unos cuantos: `URLCache` los escribe a disco después (y en memoria no guarda nada de más de
    /// ~400 KB), así que otro tamaño de la misma imagen pedido justo después la volvía a bajar entera.
    private let recentBytes = NSCache<NSURL, NSData>()
    private static let recentBytesLimit = 24 * 1024 * 1024
    private let session: URLSession
    private let cache: URLCache
    private let lock = NSLock()
    /// Lo que está en camino: los bytes por URL y cada imagen reducida por URL + tamaño.
    private var downloads: [URL: Shared<Data?>] = [:]
    private var decodes: [String: Shared<UIImage?>] = [:]
    private var failed: [String: Date] = [:]
    private let network = Limiter(limit: ImagePipeline.maxDownloads)
    private let decoder = Limiter(limit: ImagePipeline.maxDecodes)
    private static let retryAfter: TimeInterval = 60

    init() {
        memory.totalCostLimit = Self.memoryBytes
        recentBytes.totalCostLimit = Self.recentBytesLimit
        // Carpeta propia: antes compartía el `Cache.db` de la app (y su límite) con las respuestas de Cinemeta y TMDB.
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("Imagenes", isDirectory: true)
        cache = URLCache(memoryCapacity: Self.urlMemoryBytes, diskCapacity: Self.diskBytes, directory: folder)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = Self.maxDownloads
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [memory] _ in memory.removeAllObjects() }
    }

    private func key(_ url: URL, _ maxPixel: CGFloat) -> String { "\(url.absoluteString)#\(Self.bucket(maxPixel))" }

    /// La misma imagen en la variante más ligera que alcanza para `maxPixel` (`Artwork.variant`).
    private static func resolve(_ url: URL, _ maxPixel: CGFloat) -> URL {
        URL(string: Artwork.variant(url.absoluteString, pixels: bucket(maxPixel))) ?? url
    }

    private static func bucket(_ maxPixel: CGFloat) -> Int {
        let steps = Int((max(1, maxPixel) / CGFloat(pixelStep)).rounded(.up))
        return steps * pixelStep
    }

    /// La imagen si ya está reducida en memoria (síncrono, barato).
    func cached(_ url: URL, maxPixel: CGFloat) -> UIImage? { memory.object(forKey: key(Self.resolve(url, maxPixel), maxPixel) as NSString) }

    /// ¿Falló hace poco? (no se vuelve a pedir en cada pieza que reaparece).
    func recentlyFailed(_ url: URL, maxPixel: CGFloat) -> Bool {
        let k = key(Self.resolve(url, maxPixel), maxPixel)
        return lock.withLock { failed[k].map { Date().timeIntervalSince($0) < Self.retryAfter } ?? false }
    }

    /// La imagen reducida a `maxPixel`: de memoria, de disco o de la red. Varias peticiones comparten el trabajo; si
    /// todas las que esperaban se cancelan, el trabajo también.
    /// Pide de antemano los pósters de una tira (un Top 10): cuando llegas a verlos ya están (antes salían de a poco).
    func prefetchPosters(_ urls: [String]) {
        Task { @MainActor in
            let pixels = DS.Image.card * Self.screenScale   // el tamaño con que los pinta `PosterView`
            for case let url? in urls.map(URL.init(string:)) { Task.detached(priority: .utility) { _ = await self.image(url, maxPixel: pixels) } }
        }
    }

    /// Abre la conexión con los servidores de imágenes desde el arranque (DNS, TLS y HTTP/2): la primera imagen ya no paga
    /// ese saludo (unos cientos de milisegundos en datos móviles).
    func preconnect() {
        for host in Self.imageHosts {
            guard let url = URL(string: host) else { continue }
            var request = URLRequest(url: url); request.httpMethod = "HEAD"; request.timeoutInterval = 10
            session.dataTask(with: request).resume()
        }
    }
    static let imageHosts = ["https://images.metahub.space/", "https://episodes.metahub.space/"]

    /// Como `prefetchPosters`, pero espera a que estén (para enseñar varios carteles juntos, ya con imagen).
    nonisolated func warmPosters(_ urls: [String]) async {
        let pixels = await MainActor.run { DS.Image.card * Self.screenScale }
        await withTaskGroup(of: Void.self) { group in
            for case let url? in urls.map(URL.init(string:)) { group.addTask { _ = await self.image(url, maxPixel: pixels) } }
        }
    }

    /// `urgent`: la versión ligera de una imagen (~20 KB) no hace fila detrás de las buenas: sale primero (antes, los pósters
    /// pedidos después le ganaban al fondo grande).
    func image(_ requested: URL, maxPixel: CGFloat, urgent: Bool = false) async -> UIImage? {
        let url = Self.resolve(requested, maxPixel)
        let k = key(url, maxPixel)
        if let hit = memory.object(forKey: k as NSString) { return hit }
        let pixels = Self.bucket(maxPixel)
        let job: Shared<UIImage?> = lock.withLock {
            if let existing = decodes[k] { existing.waiters += 1; return existing }
            let fresh = Shared<UIImage?>()
            fresh.task = Task.detached(priority: .userInitiated) { [self] in
                let image = await decode(url, pixels: pixels, urgent: urgent)
                lock.withLock {
                    if decodes[k] === fresh { decodes[k] = nil }   // solo si sigue siendo este trabajo (no su reemplazo)
                    if image == nil, !Task.isCancelled { markFailed(k) } else { failed[k] = nil }
                }
                if let image { memory.setObject(image, forKey: k as NSString, cost: Self.cost(of: image)) }
                return image
            }
            decodes[k] = fresh
            return fresh
        }
        return await wait(job) { [self] in if decodes[k] === job { decodes[k] = nil } }
    }

    /// Anota un fallo (y de paso olvida los que ya caducaron: la tabla no crece toda la sesión). Se llama con el candado puesto.
    private func markFailed(_ key: String) {
        let now = Date()
        if failed.count > 256 { failed = failed.filter { now.timeIntervalSince($0.value) < Self.retryAfter } }
        failed[key] = now
    }

    /// Los bytes (del disco o de la red) y luego la reducción, con su propio límite.
    private func decode(_ url: URL, pixels: Int, urgent: Bool) async -> UIImage? {
        guard let data = await data(url, urgent: urgent), !Task.isCancelled else { return nil }
        if urgent { return Self.downsample(data, maxPixel: pixels) }   // chica: se decodifica al momento
        guard await decoder.acquire() else { return nil }
        defer { Task { await decoder.release() } }
        return Self.downsample(data, maxPixel: pixels)
    }

    /// Tu Orbital (dirección y token): sus imágenes (logos de canales, arte de juegos) piden el token como el resto de su
    /// puerto público; las demás (metahub, TMDB) van sin nada.
    private var console: (host: String, port: Int?, token: String)?
    func setConsole(_ base: URL?, token: String?) {
        lock.withLock {
            if let base, let host = base.host, let token, !token.isEmpty { console = (host, base.port, token) } else { console = nil }
        }
    }

    /// Los bytes de una URL: del disco sin hacer fila; de la red con una sola descarga por URL.
    private func data(_ url: URL, urgent: Bool = false) async -> Data? {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        if let console = lock.withLock({ console }), url.host == console.host, url.port == console.port {
            request.setValue("Bearer \(console.token)", forHTTPHeaderField: "Authorization")
        }
        // Solo una respuesta buena con contenido: el caché también guarda las redirecciones (las miniaturas de episodio de
        // metahub mandan un 301 a TMDB) y ese 301 vacío no es la imagen.
        let start = Perf.now()
        if let recent = recentBytes.object(forKey: url as NSURL) {
            Perf.net(kind: "imgcache", url: url, start: start, end: Perf.now(), bytes: recent.length, status: 200)
            return recent as Data
        }
        if let stored = cache.cachedResponse(for: request), !stored.data.isEmpty,
           ((stored.response as? HTTPURLResponse)?.statusCode ?? 200) < 300 {
            Perf.net(kind: "imgcache", url: url, start: start, end: Perf.now(), bytes: stored.data.count,
                     status: (stored.response as? HTTPURLResponse)?.statusCode ?? 200)
            return stored.data
        }
        // Primero se apunta el trabajo bajo el candado; la tarea se arma afuera (Swift 6 no deja mandar un cierre creado
        // dentro de otro cierre que sigue usando lo mismo).
        let (job, isNew): (Shared<Data?>, Bool) = lock.withLock {
            if let existing = downloads[url] { existing.waiters += 1; return (existing, false) }
            let fresh = Shared<Data?>()
            downloads[url] = fresh
            return (fresh, true)
        }
        if isNew {
            let fresh = job
            fresh.task = Task.detached(priority: .userInitiated) { [self, fresh, request, url, urgent] in
                defer { lock.withLock { if downloads[url] === fresh { downloads[url] = nil } } }
                if !urgent { guard await network.acquire() else { return nil } }
                lock.withLock { fresh.started = true }
                defer { if !urgent { Task { await network.release() } } }
                let start = Perf.now()
                let result = try? await session.data(for: request)
                Perf.net(kind: "img", url: url, start: start, end: Perf.now(), bytes: result?.0.count ?? 0,
                         status: (result?.1 as? HTTPURLResponse)?.statusCode ?? -1)
                guard let (fresh, response) = result,
                      let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
                // `URLSession` ya guarda lo que trae cabeceras de caché (metahub manda 60 días); solo se fuerza si no las trae.
                if http.value(forHTTPHeaderField: "Cache-Control") == nil {
                    cache.storeCachedResponse(CachedURLResponse(response: response, data: fresh, userInfo: nil, storagePolicy: .allowed), for: request)
                }
                if !fresh.isEmpty { recentBytes.setObject(fresh as NSData, forKey: url as NSURL, cost: fresh.count) }
                return fresh
            
            }
        }
        return await wait(job) { [self] in if downloads[url] === job { downloads[url] = nil } }
    }

    /// Espera un trabajo compartido. Si quien espera se cancela y era el último, el trabajo se cancela y deja de estar
    /// en camino — salvo una descarga que ya empezó: esa termina y queda en caché (la pieza que reaparece al deslizar o al
    /// redibujarse se une a ella en vez de bajarla otra vez) (la próxima petición empieza de nuevo en vez de heredar uno cancelado). Contar y olvidar van bajo el mismo
    /// candado: nadie puede unirse a un trabajo justo cuando se está cancelando. `forget` corre con el candado puesto.
    private func wait<T>(_ job: Shared<T>, forget: @escaping @Sendable () -> Void) async -> T {
        await withTaskCancellationHandler {
            await job.task.value
        } onCancel: { [lock] in
            let last = lock.withLock { () -> Bool in
                job.waiters -= 1
                guard job.waiters == 0, !job.started else { return false }
                forget()
                return true
            }
            if last { job.task.cancel() }
        }
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

    /// Los bytes de una imagen para otro uso (el widget): mismo caché y misma fila que las pantallas.
    func bytes(_ url: URL) async -> Data? { await data(url) }

    private static func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }

    /// Un trabajo que varias vistas esperan a la vez.
    private final class Shared<T: Sendable>: @unchecked Sendable {
        var task: Task<T, Never>!
        var waiters = 1
        /// Una descarga que ya tiene lugar en la fila (bajo el candado).
        var started = false
    }

    /// Un semáforo asíncrono que atiende primero al último en llegar (lo que acaba de aparecer en pantalla) y suelta
    /// a quien se cancela mientras espera.
    private actor Limiter {
        private var available: Int
        private var waiters: [(id: UUID, resume: CheckedContinuation<Bool, Never>)] = []
        private var cancelled = Set<UUID>()
        init(limit: Int) { available = limit }

        /// `false` si la tarea se canceló antes de tener lugar.
        func acquire() async -> Bool {
            let id = UUID()
            return await withTaskCancellationHandler {
                await enqueue(id)
            } onCancel: {
                Task { await self.cancel(id) }
            }
        }

        private func enqueue(_ id: UUID) async -> Bool {
            if cancelled.remove(id) != nil || Task.isCancelled { return false }
            if available > 0 { available -= 1; return true }
            return await withCheckedContinuation { waiters.append((id, $0)) }
        }

        private func cancel(_ id: UUID) {
            if let i = waiters.firstIndex(where: { $0.id == id }) { waiters.remove(at: i).resume.resume(returning: false) }
            else {
                // Casi siempre llega después de que ya tuvo lugar (o se rindió): no se guarda para siempre. Perder una marca
                // vieja solo deja pasar un trabajo ya cancelado, que suelta su lugar enseguida.
                if cancelled.count > 256 { cancelled.removeAll() }
                cancelled.insert(id)
            }
        }

        func release() {
            if let next = waiters.popLast() { next.resume.resume(returning: true) } else { available += 1 }
        }
    }
}
