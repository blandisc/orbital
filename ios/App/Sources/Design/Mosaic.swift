import SwiftUI
import OrbitalCore
import OrbitalModels

// El mosaico de «Para ti» (equivalente a `orbital/web/js/components/foryou-mosaic.js` en la TV, con la misma
// geometría de `OrbitalModels.MosaicGeometry`, probada en `MosaicLayoutTests`): columnas calculadas en puntos
// (ninguna pieza partida por el borde), la enfocada crece con resorte y enseña etiqueta + logo + un dato,
// cascada al desplazar, ambiente a los 30 s y «cobra vida» a los 2,2 s quieto sobre una pieza. Con «Reducir
// movimiento»: sin ambiente, sin acercamiento y sin resorte (el cambio de foco es inmediato).

/// Qué pieza está enfocada: su columna y su fila dentro de ella.
struct MosaicFocus: Equatable, Hashable { var col: Int; var row: Int }

enum MosaicMode: Equatable { case focus, ambient }

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

/// El mosaico de «Para ti»: pieza del catálogo (`Design/Mosaic.swift`), equivalente a `foryou-mosaic` en la TV.
/// Tocar una pieza la enfoca; volver a tocar la abre; arrastrar sube y baja (con inercia). «No me interesa» va en «Más», bajo el mosaico.
struct Mosaic: View {
    let items: [Suggestion]
    var watchlistKeys: Set<String> = []
    var demoFocus: String?
    let onDismiss: (Suggestion) -> Void
    /// La pieza enfocada (nil en el ambiente): la pantalla tiñe su fondo con su arte (`Backdrop`).
    var onFocusChange: ((Suggestion?) -> Void)?
    /// Un segundo toque en la enfocada: abre su ficha (lo hace la pantalla).
    var onOpen: ((Suggestion) -> Void)?
    /// Todavía cargando: la ruedita. Ya terminó y no hay nada: lo dice y deja reintentar (antes giraba para siempre).
    var loading = true
    var retry: (() -> Void)?

    @State private var runtime = MosaicRuntime()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var lastDragTranslation: Double = 0
    @State private var dragging = false
    /// La inercia en curso (al soltar): se detiene en cuanto el dedo vuelve a tocar.
    /// La inercia al soltar, cuadro a cuadro al ritmo de la pantalla (hasta 120 Hz).
    @State private var inertia = FrameTicker()
    @State private var activity = 0
    /// Lo que ya colocó `runtime`: si lo nuevo es solo un subconjunto (una «no me interesa» que el
    /// propio `runtime.dismiss` ya quitó), no se vuelve a armar todo —eso perdería el foco y el lugar.
    @State private var configuredIDs: Set<String> = []

    var body: some View {
        #if DEBUG
        let _ = MosaicBench.tick("Mosaic")
        #endif
        let _ = runtime.structure   // se vuelve a evaluar cuando cambia la estructura (no en cada fotograma del arrastre)
        GeometryReader { geo in
            let columnCount = Self.columnCount(width: geo.size.width, horizontalSizeClass: horizontalSizeClass)
            ZStack(alignment: .topLeading) {
                ForEach(Array(0..<min(runtime.columns.count, runtime.scrolls.count)), id: \.self) { c in
                    MosaicColumnView(scroll: runtime.scrolls[c], layer: layer(c))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .mask(LinearGradient(stops: Self.maskStops, startPoint: .top, endPoint: .bottom))
            .contentShape(Rectangle())
            // A la par de los toques de las piezas (no detrás de ellos): en un iPhone de verdad casi todo arrastre empieza
            // sobre una pieza, y con `.gesture` el botón se quedaba con él y el mosaico no bajaba.
            .simultaneousGesture(
                DragGesture(minimumDistance: DS.Gesture.axisThreshold)
                    .onChanged { value in
                        // Una sola vez al empezar (no en cada cuadro: eso reevaluaba todo el mosaico a 120 Hz).
                        if !dragging { dragging = true; inertia.stop(); touch() }
                        let delta = value.translation.height - lastDragTranslation
                        lastDragTranslation = value.translation.height
                        runtime.scrollBy(-delta)
                    }
                    .onEnded { value in
                        dragging = false
                        lastDragTranslation = 0
                        touch()
                        fling(velocity: -Double(value.velocity.height))
                    }
            )
            .onAppear {
                // Al volver de una ficha o de otra pestaña, el mosaico sigue donde estaba (mismo lugar, misma pieza enfocada).
                if configuredIDs.isEmpty || Set(items.map(\.imdb)) != configuredIDs { configure(items: items, columnCount: columnCount) }
                else { runtime.updateColumnCount(columnCount) }
                runtime.updateSize(width: Double(geo.size.width), height: Double(geo.size.height))
                if let demoFocus { runtime.focusTile(imdb: demoFocus) }
            }
            .onChange(of: geo.size) { _, size in
                runtime.updateColumnCount(Self.columnCount(width: size.width, horizontalSizeClass: horizontalSizeClass))
                runtime.updateSize(width: Double(size.width), height: Double(size.height))
            }
            .onChange(of: items) { _, newItems in
                let newIDs = Set(newItems.map(\.imdb))
                guard !newIDs.isSubset(of: configuredIDs) else { return }   // una «no me interesa»: `runtime.dismiss` ya la quitó
                // Llegaron más de las mismas (se completó con los estantes): se suman sin volver al principio.
                if !configuredIDs.isEmpty, configuredIDs.isSubset(of: newIDs) {
                    configuredIDs = newIDs
                    runtime.extend(items: newItems)
                    return
                }
                let wasEmpty = configuredIDs.isEmpty
                configure(items: newItems, columnCount: columnCount)
                // La primera vez que llega la lista de verdad (al abrir estaba vacía): aplica el foco del modo demostración.
                if wasEmpty, let demoFocus { runtime.focusTile(imdb: demoFocus) }
            }
        }
        .overlay {
            if runtime.isEmpty {
                if loading { ProgressView() }
                else {
                    DSEmptyState(symbol: "square.grid.3x3", title: Text("No pude armar tu mosaico"), message: Text("Revisa tu conexión e intenta de nuevo.")) {
                        if let retry { Button("Intentar de nuevo", action: retry) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("mosaic")   // para las pruebas de interfaz
        #if DEBUG
        .task { await MosaicBench.runIfRequested(runtime) { c, r in withAnimation(DS.Motion.spring(reduceMotion)) { runtime.focusTile(col: c, row: r) } } }
        #endif
        .onChange(of: runtime.current?.imdb, initial: true) { _, _ in onFocusChange?(runtime.current) }
        .task(id: idleToken) {
            guard runtime.mode == .focus, !reduceMotion else { return }
            #if DEBUG
            if Demo.noIdle { return }
            #endif
            try? await Task.sleep(nanoseconds: DS.Timing.mosaicIdle)
            // Mientras sigue la inercia o el dedo está encima, no es «quieto».
            if !Task.isCancelled, !inertia.isRunning, !dragging { withAnimation(DS.Motion.enter(reduceMotion)) { runtime.goAmbient() } }
        }
        .task(id: aliveToken) {
            guard runtime.mode == .focus, !reduceMotion, let id = runtime.focus else { return }
            try? await Task.sleep(nanoseconds: DS.Timing.mosaicAlive)
            if !Task.isCancelled, runtime.mode == .focus, runtime.focus == id { runtime.aliveTileID = runtime.current.map { "\($0.imdb)" } }
        }
        .task(id: runtime.mode) {
            // El ambiente es lo único que se mueve solo: en foco no hay temporizador (ni se invalida nada cada segundo).
            guard runtime.mode == .ambient, !reduceMotion else { return }
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: DS.Timing.mosaicDrift)
                let now = Date(); let dt = now.timeIntervalSince(last); last = now
                withAnimation(.linear(duration: DS.Mosaic.driftTick)) { runtime.driftTick(dt, speeds: driftSpeeds) }
            }
        }
    }

    /// Lo que pinta una columna: solo las piezas a la vista (más un colchón), con lo mínimo para compararla.
    private func layer(_ c: Int) -> MosaicColumnLayer {
        let column = runtime.columns[c]
        var range = runtime.rendered.indices.contains(c) ? runtime.rendered[c] : 0..<0
        range = min(range.lowerBound, column.tiles.count)..<min(range.upperBound, column.tiles.count)
        return MosaicColumnLayer(
            column: c, frame: column.frame, first: range.lowerBound, tiles: Array(column.tiles[range]),
            focusRow: runtime.focus?.col == c ? runtime.focus?.row : nil, focusMode: runtime.mode == .focus && runtime.focus != nil,   // sin nada elegido, nada se oscurece
            aliveID: runtime.aliveTileID, watchlist: watchlistKeys, reduceMotion: reduceMotion,
            onFocus: { col, row in touch(); withAnimation(DS.Motion.spring(reduceMotion)) { runtime.focusTile(col: col, row: row) } },
            onOpen: { onOpen?($0) },
            onDismiss: { dismiss($0) })
    }

    /// Inercia como una lista de iOS: la velocidad del dedo se va apagando cuadro por cuadro (llegan piezas por el camino,
    /// sin huecos) y un toque nuevo la detiene. Con «Reducir movimiento», se queda donde soltaste.
    private func fling(velocity start: Double) {
        inertia.stop()
        guard !reduceMotion, abs(start) > DesignTokens.Mosaic.flingStopSpeed else { runtime.endScroll(); return }
        var velocity = start
        inertia.start { dt in
            runtime.scrollBy(velocity * dt)
            velocity *= pow(DesignTokens.Mosaic.flingDecayPerSecond, dt)
            guard abs(velocity) > DesignTokens.Mosaic.flingStopSpeed else { runtime.endScroll(); touch(); return false }
            return true
        }
    }

    private func touch() { activity += 1; withAnimation(DS.Motion.base(reduceMotion)) { _ = runtime.wake() } }

    private func configure(items: [Suggestion], columnCount: Int) {
        configuredIDs = Set(items.map(\.imdb))
        runtime.configure(items: items, columnCount: columnCount, gap: Double(DS.Space.s3), ring: Double(DS.Space.s2), growRatio: Double(DS.Mosaic.growRatio), focusedRowRatio: Double(DS.Mosaic.focusedRowRatio))
    }

    private func dismiss(_ item: Suggestion) {
        configuredIDs.remove(item.imdb)
        onDismiss(item)
        runtime.dismiss(item.imdb)
    }

    private var idleToken: String { "\(runtime.mode)-\(runtime.focus?.col ?? -1)-\(runtime.focus?.row ?? -1)-\(activity)" }
    private var aliveToken: String { "\(runtime.mode)-\(runtime.focus?.col ?? -1)-\(runtime.focus?.row ?? -1)" }
    private var driftSpeeds: [Double] { (0..<max(1, runtime.columns.count)).map { c in DesignTokens.Mosaic.driftPattern[c % DesignTokens.Mosaic.driftPattern.count] } }

    private static func columnCount(width: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?) -> Int {
        let landscape = width > DS.Poster.heroHeight * 2 || horizontalSizeClass == .regular
        if landscape { return DS.Mosaic.columnsLandscape }
        return width < DS.Mosaic.compactWidth ? DS.Mosaic.columnsCompact : DS.Mosaic.columnsPortrait
    }

    /// Arriba y abajo se desvanece (como la máscara de `foryou-mosaic` en la TV).
    private static var maskStops: [Gradient.Stop] {
        [.init(color: .clear, location: 0), .init(color: .black, location: DesignTokens.Opacity.hairline * 0.7),
         .init(color: .black, location: 1 - DesignTokens.Opacity.hairline), .init(color: .clear, location: 1)]
    }
}

/// Una columna: solo mueve su `offset` cuando cambia el desplazamiento (`MosaicColumnScroll`); sus piezas
/// (`MosaicColumnLayer`) no se reevalúan mientras no cambien.
private struct MosaicColumnView: View {
    let scroll: MosaicColumnScroll
    let layer: MosaicColumnLayer

    var body: some View {
        layer.equatable().offset(y: -CGFloat(scroll.offset))
    }
}

/// Las piezas pintadas de una columna, en coordenadas de la columna (arriba = 0). Es `Equatable`: si no cambió nada
/// de lo que ve (piezas, marco, foco), SwiftUI no vuelve a evaluarla aunque el mosaico sí.
private struct MosaicColumnLayer: View, Equatable {
    let column: Int
    let frame: MosaicColumnFrame
    /// Fila de la primera pieza de `tiles` dentro de su columna.
    let first: Int
    let tiles: [MosaicTile]
    let focusRow: Int?
    let focusMode: Bool
    let aliveID: String?
    let watchlist: Set<String>
    let reduceMotion: Bool
    let onFocus: (Int, Int) -> Void
    let onOpen: (Suggestion) -> Void
    let onDismiss: (Suggestion) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.column == b.column && a.frame == b.frame && a.first == b.first && a.focusRow == b.focusRow && a.focusMode == b.focusMode
            && a.aliveID == b.aliveID && a.reduceMotion == b.reduceMotion && a.tiles == b.tiles && a.watchlist == b.watchlist
    }

    var body: some View {
        #if DEBUG
        let _ = MosaicBench.tick("Layer")
        #endif
        ZStack(alignment: .topLeading) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { i, tile in
                let row = first + i
                let focused = focusMode && focusRow == row
                MosaicTileCell(
                    tile: tile, focused: focused, dimmed: focusMode && !focused,
                    alive: !reduceMotion && aliveID == tile.id,
                    inWatchlist: watchlist.contains(tile.item.imdb),
                    onFocus: { onFocus(column, row) },
                    onOpen: { onOpen(tile.item) }
                )
                .frame(width: CGFloat(frame.width), height: CGFloat(tile.height))
                .offset(x: CGFloat(frame.x), y: CGFloat(tile.top))
            }
        }
    }
}

/// Una pieza del mosaico: su arte (portada o ancho), el ícono de su esquina, y si está enfocada, su
/// etiqueta, el logo del título (o su nombre si no carga) y un dato de una línea.
private struct MosaicTileCell: View {
    @Environment(\.locale) private var locale
    private var language: String { locale.language.languageCode?.identifier ?? "es" }
    let tile: MosaicTile
    let focused: Bool
    let dimmed: Bool
    let alive: Bool
    let inWatchlist: Bool
    let onFocus: () -> Void
    let onOpen: () -> Void

    var body: some View {
        #if DEBUG
        let _ = MosaicBench.tick("Tile")
        #endif
        // Un toque de verdad, no un botón: la pieza se mueve con el dedo al arrastrar, así que al soltar el dedo sigue
        // «encima» y un botón lo contaba como toque (abría la ficha o saltaba a otra pieza: el mosaico «se quedaba pegado»).
        // Un `TapGesture` se cancela en cuanto el dedo se mueve.
        content
            .contentShape(Rectangle())
            .onTapGesture { if focused { onOpen() } else { onFocus() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if focused { onOpen() } else { onFocus() } }
            .accessibilityHint(focused ? Text("Abre la ficha") : Text("Elegir"))
            .accessibilityLabel(Text(tile.item.title))
        .accessibilityIdentifier("mosaic-tile")
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // las piezas son arte: con letra de accesibilidad el texto de la pieza no crece más
    }

    private var content: some View {
        Group {
            if DS.Mosaic.uniform { poster } else { framed }
        }
        // Como la TV: la enfocada crece un poco y las demás se apagan (más tenues y menos saturadas).
        .opacity(dimmed ? DesignTokens.Mosaic.dimmedOpacity : 1)
        .saturation(dimmed ? DesignTokens.Mosaic.dimmedSaturation : 1)
        .scaleEffect(DS.Mosaic.uniform && focused ? DesignTokens.Mosaic.focusScale : 1)
        .scaleEffect(alive ? 1 + DesignTokens.Opacity.hairline : 1)
        .animation(alive ? .linear(duration: DesignTokens.Mosaic.aliveZoomSeconds) : .default, value: alive)   // se acerca despacio, no de golpe
    }

    /// iPhone: todas las piezas son su póster, del mismo tamaño; la enfocada solo lleva su anillo (su información va bajo
    /// el mosaico, en `MosaicCaption`).
    private var poster: some View {
        PosterView(url: tile.item.poster, title: tile.item.title, aspect: nil, bleed: true, maxPoints: DS.Image.mosaic)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(focused ? DS.text : DS.hairline, lineWidth: focused ? DS.Size.focusRing : DS.Size.hairline)
            }
    }

    /// La TV (y el iPad si se vuelve a pedir): la enfocada crece y lleva su etiqueta, logo y dato encima.
    private var framed: some View {
        ZStack(alignment: .bottomLeading) {
            // Elegir no cambia de imagen: bajarla y decodificarla en ese momento trababa el mosaico.
            PosterView(url: tile.shape == .wide ? tile.item.wide : tile.item.poster, title: tile.item.title, aspect: nil, maxPoints: DS.Image.mosaic)
            if focused { LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .center, endPoint: .bottom) }
            // Como en la TV: el ícono de serie / película solo en la pieza enfocada (en todas tapaba los logos de las portadas)
            // y sin puesto (el puesto es de su lista, en Listas).
            if focused { VStack { HStack { kindIcon; Spacer() }; Spacer() }.padding(DS.Space.s3) }
            if focused {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if !inWatchlist, let platform = tile.item.platformName { PlatformBadge(name: platform) } else { DSBadge(text: inWatchlist ? "En tu watchlist" : badgeKey(tile.item.reason)) }
                    TitleLogo(url: tile.item.logo, title: tile.item.title)
                    ViewThatFits(in: .horizontal) {   // si no cabe, se quitan partes del medio antes de cortar
                        ForEach(Array(factVariants(tile.item, language: language).enumerated()), id: \.offset) { _, text in text.lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                    }
                    .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
                }
                .padding(DS.Space.s5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay { if focused { RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.hairline) } }
        .onArt()   // la pieza es arte: su texto, como en la sala oscura, en los dos modos
    }

    private var kindIcon: some View {
        Image(systemName: KindGlyph.symbol(tile.item.kind)).font(DS.TextRecipe.caption.font.weight(.semibold))
            .foregroundStyle(focused ? DS.onPrimary : DS.text)
            .padding(DS.Space.s1)
            // Sin enfoque, solo el glifo con una sombra suave (con 20 piezas a la vista una caja en cada una domina).
            .background { if focused { Circle().fill(DS.primary) } }
            .shadow(DS.Elevation.low.color(focused ? .clear : DS.scrim))
    }
}

/// Llama a una función en cada cuadro de la pantalla (`CADisplayLink`, hasta 120 Hz) con el tiempo desde el anterior,
/// hasta que la función devuelve `false` o se detiene. Una pausa fija (`Task.sleep`) no cae con los cuadros y se veía trabado.
@MainActor
final class FrameTicker {
    private var link: CADisplayLink?
    private var onFrame: ((Double) -> Bool)?
    private var last: CFTimeInterval = 0
    private lazy var target = Target(self)

    var isRunning: Bool { link != nil }

    func start(_ frame: @escaping (Double) -> Bool) {
        stop()
        onFrame = frame
        last = 0
        let link = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() { link?.invalidate(); link = nil; onFrame = nil }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = last == 0 ? link.duration : link.targetTimestamp - last
        last = link.targetTimestamp
        if onFrame?(dt) == false { stop() }
    }

    /// `CADisplayLink` retiene a su destino: un objeto aparte (con referencia débil) para no retener al reloj.
    private final class Target: NSObject {
        weak var owner: FrameTicker?
        init(_ owner: FrameTicker) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { MainActor.assumeIsolated { owner?.tick(link) } }
    }
}
