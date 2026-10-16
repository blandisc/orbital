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
/// para acomodar, llenar y podar. Una instancia por pantalla (vive en el `@StateObject` de `Mosaic`).
/// El desplazamiento de una columna, solo eso: lo observa únicamente la vista de esa columna, así el ambiente y el
/// arrastre mueven un `offset` sin volver a evaluar el mosaico entero (CEN-49).
@MainActor
final class MosaicColumnScroll: ObservableObject {
    @Published fileprivate(set) var offset: Double = 0
}

@MainActor
final class MosaicRuntime: ObservableObject {
    /// Las columnas NO son `@Published`: cambian en cada fotograma del arrastre (su `offset`), y solo debe
    /// reevaluarse el mosaico cuando cambia su estructura (piezas, marcos, foco) —ver `commit`—.
    private(set) var columns: [MosaicColumn] = []
    /// Un objeto de desplazamiento por columna y qué piezas de cada una se pintan (a la vista más un colchón).
    private(set) var scrolls: [MosaicColumnScroll] = []
    private(set) var rendered: [Range<Int>] = []
    private var signature: [Int] = []
    @Published private(set) var focus: MosaicFocus?
    @Published private(set) var mode: MosaicMode = .focus
    @Published var aliveTileID: String?

    private var geometry = MosaicGeometry(columnCount: 1, gap: 0, ring: 0, growRatio: 1)
    private var pool = MosaicPool(items: [])
    private var serial = 0
    private var size: (width: Double, height: Double) = (0, 0)
    private var columnCount = 1

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
        if force || changed { objectWillChange.send() }
    }

    /// Lo nuevo del servidor (o la primera carga): se vuelve a armar desde cero.
    func configure(items: [Suggestion], columnCount: Int, gap: Double, ring: Double, growRatio: Double, focusedRowRatio: Double) {
        self.columnCount = max(1, columnCount)
        geometry = MosaicGeometry(columnCount: self.columnCount, gap: gap, ring: ring, growRatio: growRatio, focusedRowRatio: focusedRowRatio)
        pool = MosaicPool(items: items)
        serial = 0
        // Cada columna empieza un poco más abajo según su turno: una entrada escalonada, como en la TV.
        columns = (0..<self.columnCount).map { c in MosaicColumn(offset: c % 2 == 1 ? gap * 5 : 0) }
        focus = MosaicFocus(col: min(focus?.col ?? 0, self.columnCount - 1), row: 0)
        mode = .focus
        aliveTileID = nil
        relayoutAndFill()
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
        geometry = MosaicGeometry(columnCount: count, gap: geometry.gap, ring: geometry.ring, growRatio: geometry.growRatio, focusedRowRatio: geometry.focusedRowRatio)
        let existing = columns.flatMap(\.tiles)
        columns = (0..<count).map { _ in MosaicColumn() }
        for (i, tile) in existing.enumerated() { columns[i % count].tiles.append(tile) }
        focus = MosaicFocus(col: min(focus?.col ?? 0, count - 1), row: 0)
        relayoutAndFill()
    }

    private func visibleKeys() -> Set<String> { Set(columns.flatMap { $0.tiles.map(\.item.imdb) }) }

    private func layoutAll() { geometry.layout(&columns, totalWidth: size.width, focus: focus.map { (col: $0.col, row: $0.row) }) }

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

    private func relayoutAndFill() {
        guard size.width > 0 else { return }
        layoutAll(); fillAll(); layoutAll()
        if mode == .focus { reveal() }
        pruneAll()
        commit(force: true)
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
        relayoutAndFill()
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
        relayoutAndFill()
        return true
    }

    func goAmbient() {
        guard mode == .focus, !isEmpty else { return }
        mode = .ambient
        aliveTileID = nil
    }

    /// Ambiente: cada columna sube sola, cada una a su ritmo (como `DRIFT` en la TV).
    func driftTick(_ dt: Double, speeds: [Double]) {
        guard mode == .ambient else { return }
        for c in columns.indices {
            columns[c].offset += (speeds.indices.contains(c) ? speeds[c] : geometry.gap) * dt
            geometry.prune(&columns[c], viewportHeight: size.height)
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

    func endScroll() { pruneAll(); commit() }

    /// «No me interesa»: ya no vuelve a salir; otra toma su lugar.
    func dismiss(_ imdb: String) {
        pool.remove(imdb: imdb)
        for c in columns.indices { columns[c].tiles.removeAll { $0.item.imdb == imdb } }
        if let focus, let count = columns[safe: focus.col]?.tiles.count, focus.row >= count {
            self.focus = MosaicFocus(col: focus.col, row: max(0, count - 1))
        }
        relayoutAndFill()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// El mosaico de «Para ti»: pieza del catálogo (`Design/Mosaic.swift`), equivalente a `foryou-mosaic` en la TV.
/// Tocar una pieza la enfoca; volver a tocar la abre; mantener pulsado, «No me interesa».
struct Mosaic: View {
    let items: [Suggestion]
    var watchlistKeys: Set<String> = []
    var demoFocus: String?
    let onDismiss: (Suggestion) -> Void
    /// La pieza enfocada (nil en el ambiente): la pantalla tiñe su fondo con su arte (`Backdrop`).
    var onFocusChange: ((Suggestion?) -> Void)?

    @StateObject private var runtime = MosaicRuntime()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var lastDragTranslation: Double = 0
    @State private var activity = 0
    /// Lo que ya colocó `runtime`: si lo nuevo es solo un subconjunto (una «no me interesa» que el
    /// propio `runtime.dismiss` ya quitó), no se vuelve a armar todo —eso perdería el foco y el lugar.
    @State private var configuredIDs: Set<String> = []

    var body: some View {
        #if DEBUG
        let _ = MosaicBench.tick("Mosaic")
        #endif
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
            .gesture(
                DragGesture()
                    .onChanged { value in
                        touch()
                        let delta = value.translation.height - lastDragTranslation
                        lastDragTranslation = value.translation.height
                        runtime.scrollBy(-delta)
                    }
                    .onEnded { _ in lastDragTranslation = 0; runtime.endScroll(); touch() }
            )
            .onAppear {
                configure(items: items, columnCount: columnCount)
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
                let wasEmpty = configuredIDs.isEmpty
                configure(items: newItems, columnCount: columnCount)
                // La primera vez que llega la lista de verdad (al abrir estaba vacía): aplica el foco del modo demostración.
                if wasEmpty, let demoFocus { runtime.focusTile(imdb: demoFocus) }
            }
        }
        .overlay { if runtime.isEmpty { ProgressView() } }
        #if DEBUG
        .task { await MosaicBench.runIfRequested(runtime) { c, r in withAnimation(DS.Motion.spring(reduceMotion)) { runtime.focusTile(col: c, row: r) } } }
        #endif
        .onChange(of: runtime.current?.imdb, initial: true) { _, _ in onFocusChange?(runtime.current) }
        .task(id: idleToken) {
            guard runtime.mode == .focus, !reduceMotion else { return }
            try? await Task.sleep(nanoseconds: DS.Timing.mosaicIdle)
            if !Task.isCancelled { withAnimation(DS.Motion.enter(reduceMotion)) { runtime.goAmbient() } }
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
            focusRow: runtime.focus?.col == c ? runtime.focus?.row : nil, focusMode: runtime.mode == .focus,
            aliveID: runtime.aliveTileID, watchlist: watchlistKeys, reduceMotion: reduceMotion,
            onFocus: { col, row in touch(); withAnimation(DS.Motion.spring(reduceMotion)) { runtime.focusTile(col: col, row: row) } },
            onDismiss: { dismiss($0) })
    }

    private func touch() { activity += 1; withAnimation(DS.Motion.base(reduceMotion)) { runtime.wake() } }

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
    private var driftSpeeds: [Double] { (0..<max(1, runtime.columns.count)).map { c in Double(DS.Mosaic.driftPerSecond) * (1 + Double(c % 3) * 0.1) } }

    private static func columnCount(width: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?) -> Int {
        let landscape = width > DS.Poster.heroHeight * 2 || horizontalSizeClass == .regular
        return landscape ? DS.Mosaic.columnsLandscape : DS.Mosaic.columnsPortrait
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
    @ObservedObject var scroll: MosaicColumnScroll
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
                    onFocus: { onFocus(column, row) }
                )
                .frame(width: CGFloat(frame.width), height: CGFloat(tile.height))
                .offset(x: CGFloat(frame.x), y: CGFloat(tile.top))
                .contextMenu { Button("No me interesa", systemImage: "hand.thumbsdown") { onDismiss(tile.item) } }
            }
        }
    }
}

/// Una pieza del mosaico: su arte (portada o ancho), el ícono de su esquina, y si está enfocada, su
/// etiqueta, el logo del título (o su nombre si no carga) y un dato de una línea.
private struct MosaicTileCell: View {
    let tile: MosaicTile
    let focused: Bool
    let dimmed: Bool
    let alive: Bool
    let inWatchlist: Bool
    let onFocus: () -> Void

    var body: some View {
        #if DEBUG
        let _ = MosaicBench.tick("Tile")
        #endif
        Group {
            if focused { NavigationLink(value: tile.item.route) { content } }
            else { Button(action: onFocus) { content } }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(tile.item.title))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // las piezas son arte: con letra de accesibilidad el texto de la pieza no crece más
    }

    private var content: some View {
        ZStack(alignment: .bottomLeading) {
            PosterView(url: focused || tile.shape == .wide ? tile.item.wide : tile.item.poster, title: tile.item.title, aspect: nil, maxPoints: DS.Image.mosaic)
            if focused { LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .center, endPoint: .bottom) }
            // El puesto en un Top 10 manda sobre el ícono de serie / película (una sola pieza en la esquina, como en Listas).
            VStack { HStack(alignment: .top) { if let rank = tile.item.rank { DSRankBadge(rank: rank) }; Spacer(); if tile.item.rank == nil { kindIcon } }; Spacer() }.padding(DS.Space.s3)
            if focused {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    DSBadge(text: inWatchlist ? "En tu lista" : badgeKey(tile.item.reason))
                    TitleLogo(url: tile.item.logo, title: tile.item.title)
                    ViewThatFits(in: .horizontal) {   // si no cabe, se quitan partes del medio antes de cortar
                        ForEach(Array(factVariants(tile.item).enumerated()), id: \.offset) { _, text in text.lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                    }
                    .font(DS.font(.sm)).foregroundStyle(DS.textMuted)
                }
                .padding(DS.Space.s5)
            }
        }
        .opacity(dimmed ? DesignTokens.Opacity.shrink : 1)
        .scaleEffect(alive ? 1 + DesignTokens.Opacity.hairline : 1)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay { if focused { RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.hairline) } }
    }

    private var kindIcon: some View {
        Image(systemName: tile.item.kind == "movie" ? "film" : "tv").font(DS.font(.xs, weight: .semibold))
            .foregroundStyle(focused ? DS.onPrimary : DS.text)
            .padding(DS.Space.s1)
            // Sin enfoque, solo el glifo con una sombra suave (con 20 piezas a la vista una caja en cada una domina).
            .background { if focused { Circle().fill(DS.primary) } }
            .shadow(color: focused ? .clear : DS.scrim, radius: DS.Space.s1)
    }
}
