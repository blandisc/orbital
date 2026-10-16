import Foundation
import OrbitalCore

/// Geometría pura del mosaico de «Para ti» (como `orbital/web/js/components/foryou-mosaic.js` en la TV, aquí
/// sin SwiftUI para poder probarse con `swift test`): anchos de columna, alto de cada pieza y qué se poda o
/// se agrega al desplazar. Nunca una pieza queda fuera del ancho de su columna; podar nunca desfasa lo que
/// queda (sigue contiguo); solo la columna enfocada se ensancha.
public enum MosaicShape: Equatable, Sendable { case poster, wide }

/// Número estable a partir de una llave (el mismo algoritmo que `hashOf` en la TV: FNV-1a de 32 bits), para
/// que cada pieza tenga siempre la misma forma en el mosaico.
public func mosaicHash(_ text: String) -> UInt32 {
    var h: UInt32 = 2_166_136_261
    for scalar in text.unicodeScalars {
        let x = UInt64(h ^ scalar.value)
        h = UInt32(truncatingIfNeeded: x &* 16_777_619)
    }
    return h
}

/// Portada alta o arte ancho: dos de cada cinco piezas, anchas (como `shapeOf` en la TV). Un arte débil
/// (`heroWeak`, sin un fondo ancho de verdad) va siempre en vertical.
public func mosaicShape(key: String, heroWeak: Bool) -> MosaicShape {
    if heroWeak { return .poster }
    return mosaicHash(key) % 5 < 2 ? .wide : .poster
}

/// Dónde empieza y cuánto mide una columna.
public struct MosaicColumnFrame: Equatable, Sendable {
    public var x: Double
    public var width: Double
    public init(x: Double = 0, width: Double = 0) { self.x = x; self.width = width }
}

/// Una pieza ya colocada: su sugerencia, su forma y su lugar dentro de la columna.
public struct MosaicTile: Identifiable, Equatable, Sendable {
    public let id: String
    public let item: Suggestion
    public let shape: MosaicShape
    public var top: Double
    public var height: Double

    public init(id: String, item: Suggestion, shape: MosaicShape, top: Double = 0, height: Double = 0) {
        self.id = id; self.item = item; self.shape = shape; self.top = top; self.height = height
    }
}

/// Una columna del mosaico: su marco, sus piezas (de arriba hacia abajo) y cuánto se ha desplazado.
public struct MosaicColumn: Equatable, Sendable {
    public var frame: MosaicColumnFrame
    public var tiles: [MosaicTile]
    public var offset: Double

    public init(frame: MosaicColumnFrame = .init(), tiles: [MosaicTile] = [], offset: Double = 0) {
        self.frame = frame; self.tiles = tiles; self.offset = offset
    }
}

/// Las sugerencias que surten al mosaico: la siguiente que no se vea ya en pantalla (como `nextUnseen` en la
/// TV), para que la misma portada no salga dos veces en la misma pantalla si hay pocas sugerencias.
public struct MosaicPool: Sendable {
    public private(set) var items: [Suggestion]
    private var cursor = 0

    public init(items: [Suggestion]) { self.items = items }

    /// Por debajo de esto el mosaico se ve repetido (una pantalla de iPhone enseña ~16 piezas).
    public static let minimumVariety = 24

    /// Agrega a `base` lo de `extra` (alternando listas, sin repetir títulos) hasta `minimumVariety` o más.
    public static func toppedUp(_ base: [Suggestion], with extra: [[Suggestion]], limit: Int = ForYou.mosaicSize) -> [Suggestion] {
        var seen = Set(base.map(\.imdb))
        var out = base
        let longest = extra.map(\.count).max() ?? 0
        for i in 0..<longest {
            for list in extra where i < list.count && out.count < limit {
                // El puesto es de su lista: fuera de ella («3» junto a otro «3» de otra lista) confunde.
                if seen.insert(list[i].imdb).inserted { var item = list[i]; item.rank = nil; out.append(item) }
            }
        }
        return out
    }

    /// «No me interesa»: ya no vuelve a salir.
    public mutating func remove(imdb: String) { items.removeAll { $0.imdb == imdb } }

    public mutating func next(excluding visible: Set<String>, onScreen: Set<String> = []) -> Suggestion? {
        guard !items.isEmpty else { return nil }
        for i in 0..<items.count {
            let item = items[(cursor + i) % items.count]
            if !visible.contains(item.imdb) { cursor += i + 1; return item }
        }
        for i in 0..<items.count {
            let item = items[(cursor + i) % items.count]
            if !onScreen.contains(item.imdb) { cursor += i + 1; return item }
        }
        let item = items[cursor % items.count]
        cursor += 1
        return item
    }
}

/// Calcula y mantiene la geometría del mosaico: cuántas columnas, cuánto crece la enfocada, el aire entre
/// piezas y el anillo de foco. Una instancia por pantalla (su ancho cambia con la rotación o el iPad).
public struct MosaicGeometry: Sendable {
    public let columnCount: Int
    public let gap: Double
    public let ring: Double
    public let growRatio: Double
    /// Cuánto de alto (× el ancho de su columna) se lleva la fila enfocada: en la TV, con columnas anchas
    /// de verdad, 0,64 sobra; en el iPhone, con columnas angostas, hace falta más para que quepan la
    /// etiqueta, el logo y el dato sin encimarse (el valor lo da `DesignTokens.Mosaic.focusedRowRatio`).
    public let focusedRowRatio: Double

    public init(columnCount: Int, gap: Double, ring: Double, growRatio: Double, focusedRowRatio: Double = 0.64) {
        self.columnCount = columnCount; self.gap = gap; self.ring = ring; self.growRatio = growRatio; self.focusedRowRatio = focusedRowRatio
    }

    /// Ancho y lugar de cada columna: todas iguales, salvo la enfocada (`growRatio` veces más ancha).
    public func columnFrames(totalWidth: Double, focusedColumn: Int?) -> [MosaicColumnFrame] {
        guard columnCount > 0 else { return [] }
        let weights = (0..<columnCount).map { $0 == focusedColumn ? growRatio : 1 }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0, totalWidth > 0 else { return (0..<columnCount).map { _ in MosaicColumnFrame() } }
        let unit = (totalWidth - 2 * ring - gap * Double(columnCount - 1)) / totalWeight
        var frames: [MosaicColumnFrame] = []
        var x = ring
        for w in weights {
            let width = max(0, unit * w)
            frames.append(MosaicColumnFrame(x: x, width: width))
            x += width + gap
        }
        return frames
    }

    /// Alto de una pieza: cada una conserva su proporción según la forma (ancha o póster), también en la
    /// columna enfocada (que solo se ensancha); la fila enfocada, además, se alarga para que quepan etiqueta,
    /// logo y dato.
    public func tileHeight(columnWidth: Double, shape: MosaicShape, isFocusedColumn: Bool, isFocusedRow: Bool) -> Double {
        if isFocusedColumn, isFocusedRow { return (columnWidth * focusedRowRatio).rounded() }
        return (columnWidth * (shape == .wide ? 0.58 : 1.5)).rounded()
    }

    /// Acomoda cada pieza de la columna una tras otra, desde donde ya estaba la primera que sigue viva (así
    /// podar lo de arriba no mueve lo de abajo).
    public func place(_ tiles: inout [MosaicTile], columnWidth: Double, isFocusedColumn: Bool, focusedRow: Int?) {
        var y = tiles.first?.top ?? 0
        for i in tiles.indices {
            let h = tileHeight(columnWidth: columnWidth, shape: tiles[i].shape, isFocusedColumn: isFocusedColumn, isFocusedRow: focusedRow == i)
            tiles[i].top = y
            tiles[i].height = h
            y += h + gap
        }
    }

    /// Recalcula el ancho de cada columna y el lugar de cada pieza (como `layout()` en la TV).
    public func layout(_ columns: inout [MosaicColumn], totalWidth: Double, focus: (col: Int, row: Int)?) {
        let frames = columnFrames(totalWidth: totalWidth, focusedColumn: focus?.col)
        for c in columns.indices where c < frames.count {
            columns[c].frame = frames[c]
            place(&columns[c].tiles, columnWidth: frames[c].width, isFocusedColumn: c == focus?.col, focusedRow: c == focus?.col ? focus?.row : nil)
        }
    }

    /// Quita lo que quedó una pantalla arriba del desplazamiento (si no, el mosaico crece sin fin). Siempre
    /// deja al menos una pieza, y lo que sigue nunca se desfasa: `place` ya las vuelve a acomodar desde la
    /// primera que sobrevive.
    @discardableResult
    public func prune(_ column: inout MosaicColumn, viewportHeight: Double) -> Int {
        var removed = 0
        while column.tiles.count > 1, let first = column.tiles.first, first.top + first.height < column.offset - viewportHeight {
            column.tiles.removeFirst()
            removed += 1
        }
        return removed
    }

    /// Agrega piezas al final de la columna mientras no llenen lo visible más el colchón de sobra.
    public func fill(
        _ column: inout MosaicColumn, viewportHeight: Double, buffer: Double, isFocusedColumn: Bool, focusedRow: Int?,
        pool: inout MosaicPool, visible: Set<String>, onScreen: Set<String>, serial: inout Int
    ) {
        func bottom() -> Double { column.tiles.last.map { $0.top + $0.height } ?? 0 }
        var guardCount = 0
        while bottom() - column.offset < viewportHeight + buffer, guardCount < 400 {
            guard let item = pool.next(excluding: visible, onScreen: onScreen) else { return }
            serial += 1
            let shape = mosaicShape(key: item.imdb, heroWeak: item.wide.isEmpty)
            var tile = MosaicTile(id: "\(item.imdb)-\(serial)", item: item, shape: shape)
            let prev = column.tiles.last
            tile.top = prev.map { $0.top + $0.height + gap } ?? 0
            tile.height = tileHeight(columnWidth: column.frame.width, shape: tile.shape, isFocusedColumn: isFocusedColumn, isFocusedRow: isFocusedColumn && focusedRow == column.tiles.count)
            column.tiles.append(tile)
            guardCount += 1
        }
    }
}
