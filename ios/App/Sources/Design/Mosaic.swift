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

    nonisolated static func == (a: Self, b: Self) -> Bool {
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
