import SwiftUI
import OrbitalCore
import OrbitalModels

/// El motor del mosaico: la geometría viva de las columnas (desplazamiento, inercia, ambiente, relleno y poda), sin vistas.

/// El motor del mosaico: guarda las columnas y qué está enfocado, y llama a `OrbitalModels.MosaicGeometry`
/// para acomodar, llenar y podar. Una instancia por pantalla (vive en el `@State` de `Mosaic`).
/// El desplazamiento de una columna, solo eso: lo observa únicamente la vista de esa columna, así el ambiente y el
/// arrastre mueven un `offset` sin volver a evaluar el mosaico entero (CEN-49).
@MainActor
@Observable
final class MosaicColumnScroll {
    fileprivate(set) var offset: Double = 0
}

@MainActor
@Observable
final class MosaicRuntime {
    /// Las columnas NO se observan: cambian en cada fotograma del arrastre (su `offset`), y solo debe
    /// reevaluarse el mosaico cuando cambia su estructura (piezas, marcos, foco) —ver `commit` y `structure`—.
    @ObservationIgnored private(set) var columns: [MosaicColumn] = []
    /// Un objeto de desplazamiento por columna y qué piezas de cada una se pintan (a la vista más un colchón).
    @ObservationIgnored private(set) var scrolls: [MosaicColumnScroll] = []
    @ObservationIgnored private(set) var rendered: [Range<Int>] = []
    @ObservationIgnored private var signature: [Int] = []
    /// Sube cada vez que `commit` decide que cambió la estructura: el mosaico la lee para volver a evaluarse entonces.
    private(set) var structure = 0
    private(set) var focus: MosaicFocus?
    private(set) var mode: MosaicMode = .focus
    var aliveTileID: String?

    @ObservationIgnored private var geometry = MosaicGeometry(columnCount: 1, gap: 0, ring: 0, growRatio: 1)
    @ObservationIgnored private var pool = MosaicPool(items: [])
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var size: (width: Double, height: Double) = (0, 0)
    @ObservationIgnored private var columnCount = 1
    /// Lo que le falta subir a cada columna para el escalón del ambiente (se consume con la deriva).
    @ObservationIgnored private var pendingLift: [Double] = []

    var isEmpty: Bool { pool.items.isEmpty }
    var current: Suggestion? {
        guard mode == .focus, let focus, columns.indices.contains(focus.col), columns[focus.col].tiles.indices.contains(focus.row) else { return nil }
        return columns[focus.col].tiles[focus.row].item
    }

    /// Pasa el estado del modelo a la vista: copia los `offset` a sus objetos (solo lo que cambió), recalcula qué piezas
    /// se pintan y avisa al mosaico solo si cambió la estructura (`force`, o las piezas pintadas).
    private func commit(force: Bool = false) {
        while scrolls.count < columns.count { scrolls.append(MosaicColumnScroll()) }
        if scrolls.count > columns.count { scrolls.removeLast(scrolls.count - columns.count) }
        let margin = size.height * DesignTokens.Mosaic.cullMargin
        var ranges: [Range<Int>] = []
        var sig: [Int] = []
        for c in columns.indices {
            if scrolls[c].offset != columns[c].offset { scrolls[c].offset = columns[c].offset }
            let tiles = columns[c].tiles, offset = columns[c].offset
            let lo = offset - margin, hi = offset + size.height + margin
            let first = tiles.firstIndex { $0.top + $0.height >= lo } ?? tiles.count
            let last = tiles.lastIndex { $0.top <= hi }.map { $0 + 1 } ?? first
            ranges.append(first..<max(first, last))
            sig.append(tiles.count); sig.append(ranges[c].lowerBound); sig.append(ranges[c].upperBound)
        }
        let changed = sig != signature || ranges != rendered
        rendered = ranges; signature = sig
        if force || changed { structure &+= 1 }
    }

    /// Lo nuevo del servidor (o la primera carga): se vuelve a armar desde cero.
    func configure(items: [Suggestion], columnCount: Int, gap: Double, ring: Double, growRatio: Double, focusedRowRatio: Double) {
        self.columnCount = max(1, columnCount)
        geometry = MosaicGeometry(columnCount: self.columnCount, gap: gap, ring: ring, growRatio: growRatio, focusedRowRatio: focusedRowRatio, uniform: DS.Mosaic.uniform)
        pool = MosaicPool(items: items)
        serial = 0
        // Todas las columnas empiezan alineadas: el escalón llega con el ambiente (`goAmbient`).
        columns = (0..<self.columnCount).map { _ in MosaicColumn() }
        focus = nil   // empieza sin nada elegido: se recorre libre y se elige tocando
        mode = .focus
        aliveTileID = nil
        relayoutAndFill()
    }

    /// Más sugerencias de las mismas (completar el mosaico con lo de los estantes): entran a la fila sin rearmar nada,
    /// así no se pierde el lugar ni la pieza elegida.
    func extend(items: [Suggestion]) {
        pool = MosaicPool(items: items)
        fillAll(); layoutAll(); commit(force: true)
    }

    /// Cambió el tamaño de pantalla (rotación, iPad, letra grande): se reacomoda en su lugar.
    func updateSize(width: Double, height: Double) {
        guard width > 0, height > 0, width != size.width || height != size.height || columns.isEmpty else { return }
        size = (width, height)
        relayoutAndFill()
    }

    func updateColumnCount(_ count: Int) {
        guard count != columnCount, count > 0 else { return }
        columnCount = count
        geometry = MosaicGeometry(columnCount: count, gap: geometry.gap, ring: geometry.ring, growRatio: geometry.growRatio, focusedRowRatio: geometry.focusedRowRatio, uniform: geometry.uniform)
        let existing = columns.flatMap(\.tiles)
        columns = (0..<count).map { _ in MosaicColumn() }
        for (i, tile) in existing.enumerated() { columns[i % count].tiles.append(tile) }
        focus = nil
        relayoutAndFill()
    }

    private func visibleKeys() -> Set<String> { Set(columns.flatMap { $0.tiles.map(\.item.imdb) }) }

    /// En ambiente no hay foco: las columnas se igualan y cada pieza vuelve a su forma (como `goAmbient` en la TV).
    private func layoutAll() { geometry.layout(&columns, totalWidth: size.width, focus: mode == .ambient ? nil : focus.map { (col: $0.col, row: $0.row) }) }

    private func fillAll() {
        // Casi siempre las columnas ya están llenas: no se arma el conjunto de llaves si no hace falta.
        guard columns.indices.contains(where: { c in (columns[c].tiles.last.map { $0.top + $0.height } ?? 0) - columns[c].offset < size.height + DesignTokens.Mosaic.bufferHeight }) else { return }
        let visible = visibleKeys()
        for c in columns.indices {
            geometry.fill(&columns[c], viewportHeight: size.height, buffer: DesignTokens.Mosaic.bufferHeight,
                          isFocusedColumn: c == focus?.col, focusedRow: c == focus?.col ? focus?.row : nil,
                          pool: &pool, visible: visible, onScreen: visible, serial: &serial)
        }
    }

    private func pruneAll() {
        for c in columns.indices {
            let removed = geometry.prune(&columns[c], viewportHeight: size.height)
            if removed > 0, c == focus?.col, var f = focus { f.row = max(0, f.row - removed); focus = f }
        }
    }

    /// `reveal`: lleva la pieza enfocada a la vista. Solo cuando la eliges (o al armar): si se hiciera siempre, cada
    /// cambio de tamaño o cada despertar regresaba esa columna a donde estaba la pieza, aunque ya hubieras bajado.
    private func relayoutAndFill(reveal shouldReveal: Bool = false) {
        guard size.width > 0 else { return }
        layoutAll(); fillAll(); layoutAll()
        if mode == .focus, shouldReveal { reveal() }
        pruneAll()
        commit(force: true)
    }

    /// Si la enfocada ya no se ve (bajaste, o el ambiente la subió), el foco pasa a la del centro de su columna.
    private func refocusIfOffscreen() {
        guard let f = focus, columns.indices.contains(f.col) else { return }
        let column = columns[f.col]
        let visible = column.tiles.indices.contains(f.row) && {
            let t = column.tiles[f.row]
            return t.top + t.height > column.offset && t.top < column.offset + size.height
        }()
        // Se fue de la vista: queda sin elegir (no se elige sola otra mientras recorres).
        if !visible { focus = nil; aliveTileID = nil; relayoutAndFill() }
    }

    /// La enfocada, entera a la vista (como `reveal()` en la TV).
    private func reveal() {
        guard let focus, columns.indices.contains(focus.col), columns[focus.col].tiles.indices.contains(focus.row) else { return }
        let tile = columns[focus.col].tiles[focus.row]
        let pad = size.height * 0.08
        if focus.row == 0 { columns[focus.col].offset = max(0, tile.top - geometry.ring) }
        else if tile.top - columns[focus.col].offset < pad { columns[focus.col].offset = max(0, tile.top - pad) }
        else if tile.top + tile.height - columns[focus.col].offset > size.height - pad { columns[focus.col].offset = tile.top + tile.height - size.height + pad }
    }

    func focusTile(col: Int, row: Int) {
        guard columns.indices.contains(col), columns[col].tiles.indices.contains(row) else { return }
        mode = .focus
        focus = MosaicFocus(col: col, row: row)
        aliveTileID = nil
        relayoutAndFill(reveal: true)
    }

    /// Para el modo demostración: enfoca la sugerencia con ese `imdb` si ya está colocada.
    func focusTile(imdb: String) {
        for (c, column) in columns.enumerated() {
            if let r = column.tiles.firstIndex(where: { $0.item.imdb == imdb }) { focusTile(col: c, row: r); return }
        }
    }

    /// Cualquier toque: si estaba en ambiente, despierta y enfoca lo que quedó al centro (como `wake()` en la TV).
    @discardableResult
    func wake() -> Bool {
        guard mode == .ambient else { return false }
        mode = .focus
        aliveTileID = nil
        // Al despertar no se elige nada solo (la de antes el ambiente ya la subió): se recorre libre y se elige tocando.
        focus = nil
        relayoutAndFill()
        return true
    }

    func goAmbient() {
        guard mode == .focus, !isEmpty else { return }
        mode = .ambient
        aliveTileID = nil
        // Si siguen parejas (la primera vez, o tras recorrerlas con el dedo), las de turno impar suben un poco antes de
        // que empiece la deriva; quien llama lo anima.
        // El escalón no brinca: se suma a la deriva, a su misma velocidad, hasta completarse.
        if let first = columns.first?.offset, columns.allSatisfy({ $0.offset == first }) {
            pendingLift = columns.indices.map { $0 % 2 == 1 ? geometry.gap * DesignTokens.Mosaic.ambientLiftGaps : 0 }
        }
        relayoutAndFill()
    }

    /// Ambiente: cada columna sube sola, cada una a su ritmo (como `DRIFT` en la TV).
    func driftTick(_ dt: Double, speeds: [Double]) {
        guard mode == .ambient else { return }
        for c in columns.indices {
            let lift = pendingLift.indices.contains(c) ? min(pendingLift[c], DesignTokens.Mosaic.driftPerSecond * dt) : 0
            if lift > 0 { pendingLift[c] -= lift }
            columns[c].offset += (speeds.indices.contains(c) ? speeds[c] : geometry.gap) * dt + lift
            let removed = geometry.prune(&columns[c], viewportHeight: size.height)
            if removed > 0, c == focus?.col, var f = focus { f.row = max(0, f.row - removed); focus = f }   // la misma pieza sigue enfocada
        }
        fillAll()
        commit()
    }

    /// Con el dedo: todo el mosaico sube o baja con el arrastre; abajo llegan piezas nuevas.
    func scrollBy(_ delta: Double) {
        guard mode == .focus else { return }
        for c in columns.indices {
            let minOffset = (columns[c].tiles.first?.top ?? 0) - geometry.ring
            columns[c].offset = max(minOffset, columns[c].offset + delta)
        }
        fillAll()
        commit()
    }

    func endScroll() { pruneAll(); refocusIfOffscreen(); commit() }

    /// «No me interesa»: ya no vuelve a salir; otra toma su lugar.
    func dismiss(_ imdb: String) {
        pool.remove(imdb: imdb)
        for c in columns.indices { columns[c].tiles.removeAll { $0.item.imdb == imdb } }
        if let focus, let count = columns[safe: focus.col]?.tiles.count, focus.row >= count {
            self.focus = nil
        }
        relayoutAndFill()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
