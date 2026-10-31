import Foundation

/// El orden del muro de pósters de la portada de Para ti (la vista `MosaicCover` solo lo pinta). Los primeros pesan más
/// (los del mosaico). Con los mismos pósters (al volver del mosaico o de otra pestaña), el mismo muro. Si llegaron más
/// distintos, otro con todos (antes solo se cambiaban los repetidos de arriba y abajo quedaban franjas de los mismos:
/// auditoría del 31 oct 2026). Si son pocos, se repiten en tandas revueltas, sin dos iguales juntos al unir tandas.
public struct CoverWall: Equatable, Sendable {
    /// De qué pósters salió y en qué orden quedó.
    public var source: [String] = []
    public var order: [String] = []
    public init(source: [String] = [], order: [String] = []) { self.source = source; self.order = order }

    public func next(for posters: [String], size: Int, shuffle: ([String]) -> [String] = { $0.shuffled() }) -> CoverWall {
        let now = Set(posters)
        if !order.isEmpty, now.isSubset(of: Set(source)) || Set(order).count >= min(now.count, size) { return self }
        var seen = Set<String>()
        let distinct = Array(posters.filter { seen.insert($0).inserted }.prefix(size))
        var wall: [String] = []
        while !distinct.isEmpty, wall.count < size {
            var batch = shuffle(distinct)
            if let last = wall.last, batch.first == last, batch.count > 1 { batch.swapAt(0, batch.count - 1) }
            wall += batch
        }
        return CoverWall(source: posters, order: Array(wall.prefix(size)))
    }
}

/// El muro de la última vez: vive en `ParaTiModel` (antes era una variable global de la vista) y sobrevive a que la
/// pantalla se vuelva a armar.
@MainActor
public final class CoverWallMemory {
    public private(set) var last = CoverWall()
    public init() {}
    public func order(for posters: [String], size: Int) -> [String] {
        last = last.next(for: posters, size: size)
        return last.order
    }
}
