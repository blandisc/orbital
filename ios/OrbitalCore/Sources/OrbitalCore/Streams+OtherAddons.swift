import Foundation

/// Lo que dicen de distinto los complementos que no son Torrentio (M1, M3): cada uno marca «al instante» a su manera, y
/// algunos enlaces piden datos extra al abrirse.
extension Streams {
    /// M1: «al instante» y «por Real-Debrid», como lo dice cada complemento. Torrentio «[RD+]» / «[RD download]», Comet
    /// «[RD⚡]» / «[RD⬇️]», MediaFusion «⚡️» / «⏳»; de respaldo, para los demás: «+]» o «⚡» en el primer renglón.
    static func instantMark(name: String, addon: String, transportURL: String) -> (cached: Bool, debrid: Bool) {
        let who = "\(addon) \(URL(string: transportURL)?.host ?? "")".lowercased()
        let head = name.components(separatedBy: .newlines).first ?? name
        // Por letra, no por carácter: «⚡️» lleva un selector de variante y no es igual a «⚡» como carácter.
        func has(_ scalar: Unicode.Scalar) -> Bool { head.unicodeScalars.contains(scalar) }
        let bolt = has("\u{26A1}"), waiting = has("\u{23F3}") || has("\u{2B07}")
        if who.contains("torrentio") { return (name.contains("[RD+]") || head.contains("+]"), matches(debridPattern, name)) }
        if who.contains("comet") { return (bolt || head.contains("+]"), matches(debridPattern, name) || bolt || waiting) }
        if who.contains("mediafusion") { return (bolt, bolt || waiting || matches(debridPattern, name)) }
        return (name.contains("[RD+]") || head.contains("+]") || bolt, matches(debridPattern, name) || bolt || waiting)
    }
}

/// M3: los datos extra que un enlace pide que mande el reproductor (`behaviorHints.proxyHeaders.request`), por enlace y solo
/// en memoria (pueden llevar una clave). La búsqueda los anota; el reproductor y las descargas los leen al abrir ese enlace.
public enum PlaybackHeaders {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var byURL: [String: [String: String]] = [:]

    public static func remember(_ headers: [String: String], for url: URL) {
        guard !headers.isEmpty else { return }
        lock.withLock {
            if byURL.count > 500 { byURL.removeAll() }
            byURL[url.absoluteString] = headers
        }
    }

    public static func headers(for url: URL) -> [String: String] { lock.withLock { byURL[url.absoluteString] ?? [:] } }
}
