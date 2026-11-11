import Foundation

/// F2 · Las reglas de tamaño de `design/streams-rules.json` (las mismas que lee la TV en `orbital/library/streams.py`).
/// La app no puede leer el repo al correr: aquí van los mismos valores y `StreamsRulesTests` falla si uno cambia en el
/// archivo y no aquí (como `DesignTokens` con `design/tokens.json`). Las banderas, las palabras, los códigos y los sitios
/// (`flagLanguages`, `wordLanguages` + `moreWordLanguages`, `codeLanguages`, `siteLanguages`) se comparan igual.
extension Streams {
    /// `size` de las reglas, en GB.
    enum SizeRule {
        /// Más que esto resta 150 (por resolución, ya con 1440p como 1080p).
        static let tooBig: [String: Double] = ["4K": 60, "1080p": 25]
        /// Sin resolución que esté en `tooBig` (720p, 480p, sin calidad).
        static let tooBigDefault = 15.0
        /// En series, el tope se multiplica por esto (un episodio pesa menos).
        static let seriesFactor = 0.3
        /// Menos que esto resta 120: sospechosamente pequeño.
        static let tooSmallMovie = 0.7
        static let tooSmallSeries = 0.12
    }

    /// 1440p cuenta como 1080p en todo (la `res_class` de la TV).
    static func resolutionClass(_ resolution: String) -> String { resolution == "1440p" ? "1080p" : resolution }

    /// El tope de tamaño de una versión: una 1440p de 20 GB ya no se castiga (antes le tocaba el de «sin calidad», 15 GB, y en
    /// la TV no; `unify` › `size.too_big_gb.1440p`).
    static func tooBigGB(_ resolution: String, kind: String) -> Double {
        let cap = SizeRule.tooBig[resolutionClass(resolution)] ?? SizeRule.tooBigDefault
        return kind == "movie" ? cap : cap * SizeRule.seriesFactor
    }
}
