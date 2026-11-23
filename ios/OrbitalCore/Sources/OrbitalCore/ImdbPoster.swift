import Foundation

/// El último respaldo del póster antes del nombre sobre color (`PosterStandIn`): la imagen que IMDb enseña en su buscador.
///
/// Medido el 23 nov 2026 con diez búsquedas de verdad («matrix», «the office», «coco»…): Cinemeta arma una URL de metahub para
/// cada resultado, aunque metahub no tenga nada. 49 de 367 daban 404 (13 %), y para esos 48 títulos tampoco había otro tamaño
/// de metahub, ni fondo, ni logo, ni ficha en Cinemeta, ni nada en TMDB (0 de 48). El buscador de IMDb sí tenía imagen para
/// 38 de 48 (79 %). Son los títulos poco conocidos («las cosas raras» de Fernando): especiales, cortos, series de YouTube.
///
/// Lo encontrado se recuerda (también «no la tiene») mientras la app sigue abierta; las respuestas de IMDb y las imágenes
/// quedan además en el caché de disco de la red.
public final class ImdbPoster: @unchecked Sendable {
    /// El buscador público de IMDb, sin clave: por id devuelve el título y su imagen.
    static let suggestion = "https://v3.sg.media-imdb.com/suggestion/x/%@.json"
    private static let idPattern = #"^tt[0-9]{1,12}$"#

    private let lock = NSLock()
    private var known: [String: String] = [:]   // "" = IMDb no la tiene
    private var inflight: [String: Task<String?, Never>] = [:]
    private let lookup: @Sendable (String) async -> String??   // nil: no se pudo preguntar; .some(nil): no la tiene

    public init(lookup: @escaping @Sendable (String) async -> String??) { self.lookup = lookup }

    /// Con un cliente de red (la app: el de caché público).
    public convenience init(http: HTTPClient) {
        self.init { imdb in
            guard let url = Self.lookupURL(imdb) else { return .some(nil) }
            guard let response = try? await http.send(HTTPRequest(url: url, timeout: 10)) else { return nil }
            guard response.status == 200 else { return response.status == 404 ? .some(nil) : nil }
            return .some(Self.parse(response.data, imdb: imdb))
        }
    }

    public static func lookupURL(_ imdb: String) -> URL? {
        guard imdb.range(of: idPattern, options: .regularExpression) != nil else { return nil }
        return URL(string: String(format: suggestion, imdb))
    }

    /// La imagen del título con ese id en la respuesta del buscador (no la de otro parecido que venga en la lista).
    public static func parse(_ data: Data, imdb: String) -> String? {
        guard let rows = JSON.parse(data)?["d"]?.array else { return nil }
        let hit = rows.first { $0["id"]?.string == imdb }
        guard let image = hit?["i"]?["imageUrl"]?.string, image.hasPrefix("https://") else { return nil }
        return image
    }

    /// La misma imagen de Amazon al ancho pedido («…_V1_.jpg» → «…_V1_QL75_UX500_.jpg»): la original pesa ~100 KB y más,
    /// la de 500 px unos 14 KB. Si la URL no tiene esa forma, va tal cual.
    public static func sized(_ url: String, width: Int) -> String {
        guard url.hasSuffix("._V1_.jpg") else { return url }
        return String(url.dropLast("._V1_.jpg".count)) + "._V1_QL75_UX\(max(1, width))_.jpg"
    }

    /// El ancho del póster de metahub que se reemplaza (small 300, medium 500, large 780).
    static func width(metahub size: String) -> Int { ["small": 300, "large": 780][size, default: 500] }

    /// Lo ya encontrado, sin preguntar: la próxima vez ese póster va directo a IMDb (sin volver a esperar el 404 de metahub).
    public func remembered(_ metahubURL: String) -> URL? {
        guard let (imdb, size) = PosterSource.metahub(metahubURL), let image = lock.withLock({ known[imdb] }), !image.isEmpty else { return nil }
        return URL(string: Self.sized(image, width: Self.width(metahub: size)))
    }

    /// La imagen de IMDb para un póster de metahub que no cargó. nil: no es de metahub, o IMDb tampoco la tiene.
    public func resolve(_ metahubURL: String) async -> URL? {
        guard let (imdb, size) = PosterSource.metahub(metahubURL) else { return nil }
        let task: Task<String?, Never>? = lock.withLock {
            if known[imdb] != nil { return nil }
            if let running = inflight[imdb] { return running }
            let task = Task<String?, Never> { [self] in
                let answer = await lookup(imdb)
                lock.withLock {
                    inflight[imdb] = nil
                    if let answer { known[imdb] = answer ?? "" }   // «no se pudo preguntar» no se recuerda
                }
                return answer ?? nil
            }
            inflight[imdb] = task
            return task
        }
        let image = await task?.value ?? lock.withLock { known[imdb] }
        guard let image, !image.isEmpty else { return nil }
        return URL(string: Self.sized(image, width: Self.width(metahub: size)))
    }
}
