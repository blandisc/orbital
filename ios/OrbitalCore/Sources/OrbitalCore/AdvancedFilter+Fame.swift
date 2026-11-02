import Foundation

extension AdvancedFilter.Fame {
    /// ¿Un título con esta calificación y estos votos de TMDB es de este «Qué tan conocida»? Los mismos rangos que el filtro
    /// avanzado le pide a TMDB (`AdvancedFilter.params`, sin el descuento de los países chicos): así «Joyas ocultas» quiere
    /// decir lo mismo en Decide por mí, que lo resuelve sobre tus listas.
    public func matches(average: Double, votes: Int, series: Bool) -> Bool {
        func floor(_ movie: Int, _ tv: Int) -> Int { series ? tv : movie }
        switch self {
        case .any: return true
        case .gems: return average >= 7.2 && votes >= floor(300, 200) && votes <= 3000
        case .classics: return average >= 7.5 && votes >= floor(3000, 800)
        case .niche: return average >= 6.5 && votes >= floor(50, 30) && votes <= 500
        case .blockbusters: return votes >= floor(3000, 1000)
        }
    }
}
