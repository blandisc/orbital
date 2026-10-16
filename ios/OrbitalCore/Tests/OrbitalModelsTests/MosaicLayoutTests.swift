import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// El mosaico de «Para ti» (CEN-36): columnas calculadas sin que ninguna pieza quede fuera del ancho, la
/// enfocada ensancha solo su columna, y podar lo de arriba nunca desfasa lo que sigue vivo.
final class MosaicLayoutTests: XCTestCase {
    private func item(_ id: String) -> Suggestion {
        Suggestion(kind: "movie", imdb: id, title: id, poster: "", wide: "https://example.test/\(id)", reason: .popular)
    }

    // MARK: anchos de columna

    func testColumnFramesNeverExceedTheTotalWidth() {
        let geo = MosaicGeometry(columnCount: 4, gap: 12, ring: 8, growRatio: 1.8)
        let frames = geo.columnFrames(totalWidth: 390, focusedColumn: 1)
        XCTAssertEqual(frames.count, 4)
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.x, 0)
            XCTAssertLessThanOrEqual(frame.x + frame.width, 390.0001, "ninguna columna sale del ancho de pantalla")
        }
    }

    func testOnlyTheFocusedColumnWidens() {
        let geo = MosaicGeometry(columnCount: 4, gap: 12, ring: 8, growRatio: 1.8)
        let resting = geo.columnFrames(totalWidth: 390, focusedColumn: nil)
        XCTAssertTrue(resting.dropFirst().allSatisfy { abs($0.width - resting[0].width) < 0.001 }, "sin foco, las columnas son iguales")

        let focused = geo.columnFrames(totalWidth: 390, focusedColumn: 2)
        for (c, frame) in focused.enumerated() where c != 2 {
            XCTAssertLessThan(frame.width, focused[2].width, "la columna 2 es la única que crece")
        }
        // Las que no son la enfocada siguen midiendo lo mismo entre ellas.
        let others = focused.enumerated().filter { $0.offset != 2 }.map(\.element.width)
        XCTAssertTrue(others.allSatisfy { abs($0 - others[0]) < 0.001 })
    }

    func testFocusedTileIsTallerThanTheRestOfItsColumn() {
        // Con la proporción real de la app (`DesignTokens.Mosaic.focusedRowRatio`): las vecinas conservan su forma
        // (póster 1,5 o ancha 0,58 del ancho) y la enfocada es la más alta de su columna.
        let geo = MosaicGeometry(columnCount: 4, gap: 12, ring: 8, growRatio: 1.8, focusedRowRatio: DesignTokens.Mosaic.focusedRowRatio)
        var columns = [MosaicColumn(tiles: [
            MosaicTile(id: "a", item: item("a"), shape: .poster),
            MosaicTile(id: "b", item: item("b"), shape: .wide),
            MosaicTile(id: "c", item: item("c"), shape: .poster),
        ])]
        geo.layout(&columns, totalWidth: 390, focus: (col: 0, row: 1))
        let tiles = columns[0].tiles
        XCTAssertGreaterThan(tiles[1].height, tiles[0].height, "la fila enfocada crece más que las vecinas de su misma columna")
        XCTAssertGreaterThan(tiles[1].height, tiles[2].height)
    }

    // MARK: poda sin desfase

    func testPruningKeepsTheRemainingTilesContiguous() {
        let geo = MosaicGeometry(columnCount: 1, gap: 10, ring: 0, growRatio: 1)
        var column = MosaicColumn(frame: MosaicColumnFrame(x: 0, width: 200), tiles: (0..<8).map {
            MosaicTile(id: "t\($0)", item: item("t\($0)"), shape: .poster)
        })
        var columns = [column]
        geo.layout(&columns, totalWidth: 200, focus: nil)
        column = columns[0]

        func assertContiguous(_ tiles: [MosaicTile], _ label: String) {
            for i in 1..<tiles.count {
                let expected = tiles[i - 1].top + tiles[i - 1].height + geo.gap
                XCTAssertEqual(tiles[i].top, expected, accuracy: 0.001, "\(label): la pieza \(i) se desfasó de la anterior")
            }
        }
        assertContiguous(column.tiles, "antes de podar")

        column.offset = column.tiles.last!.top + column.tiles.last!.height // bien abajo: todo salvo quizá la última es podable
        let removed = geo.prune(&column, viewportHeight: 50)
        XCTAssertGreaterThan(removed, 0, "debió podar algo para que la prueba tenga sentido")
        XCTAssertGreaterThanOrEqual(column.tiles.count, 1, "nunca deja la columna vacía")

        // Tras podar, un nuevo layout (como hace la TV) vuelve a acomodar desde la primera que sobrevive, sin huecos.
        geo.place(&column.tiles, columnWidth: column.frame.width, isFocusedColumn: false, focusedRow: nil)
        assertContiguous(column.tiles, "después de podar y reacomodar")
    }

    func testFillAppendsContiguousTilesWithoutRepeatingWhatIsVisible() {
        let geo = MosaicGeometry(columnCount: 1, gap: 10, ring: 0, growRatio: 1)
        var column = MosaicColumn(frame: MosaicColumnFrame(x: 0, width: 200))
        var pool = MosaicPool(items: (0..<5).map { item("p\($0)") })
        var serial = 0
        geo.fill(&column, viewportHeight: 300, buffer: 100, isFocusedColumn: false, focusedRow: nil, pool: &pool, visible: [], onScreen: [], serial: &serial)
        XCTAssertFalse(column.tiles.isEmpty)
        for i in 1..<column.tiles.count {
            let expected = column.tiles[i - 1].top + column.tiles[i - 1].height + geo.gap
            XCTAssertEqual(column.tiles[i].top, expected, accuracy: 0.001)
        }
        // Lo que ya se ve ("p0") no debe repetirse mientras haya otras sugerencias sin mostrar.
        var fresh = MosaicColumn(frame: MosaicColumnFrame(x: 0, width: 200))
        var freshPool = MosaicPool(items: (0..<3).map { item("q\($0)") })
        var freshSerial = 0
        geo.fill(&fresh, viewportHeight: 300, buffer: 100, isFocusedColumn: false, focusedRow: nil, pool: &freshPool, visible: ["q0"], onScreen: [], serial: &freshSerial)
        XCTAssertFalse(fresh.tiles.contains { $0.item.imdb == "q0" }, "no repite una sugerencia que ya está a la vista mientras haya otras")
    }

    // MARK: forma (vertical / ancha)

    func testShapeIsDeterministicForTheSameKey() {
        let a = mosaicShape(key: "tt0386676", heroWeak: false)
        let b = mosaicShape(key: "tt0386676", heroWeak: false)
        XCTAssertEqual(a, b)
    }

    func testWeakHeroArtIsAlwaysAPoster() {
        XCTAssertEqual(mosaicShape(key: "tt0386676", heroWeak: true), .poster)
    }

    // MARK: la fuente (pool)

    func testPoolSkipsOverWhatIsAlreadyVisibleBeforeRepeating() {
        var pool = MosaicPool(items: [item("a"), item("b"), item("c")])
        let first = pool.next(excluding: [])
        XCTAssertEqual(first?.imdb, "a")
        let second = pool.next(excluding: ["b"]) // "b" sigue; se salta a "c"
        XCTAssertEqual(second?.imdb, "c")
    }

    func testEmptyPoolReturnsNothing() {
        var pool = MosaicPool(items: [])
        XCTAssertNil(pool.next(excluding: []))
    }

    // MARK: relleno y poda convergen con el volumen real (CEN-49)

    /// 96 sugerencias de formas mezcladas (arte ancho y solo póster), un ancho de iPhone y un desplazamiento largo hacia
    /// abajo y hacia arriba: `fill` y `prune` terminan, ninguna columna queda vacía y las piezas vivas no crecen sin tope.
    func testFillAndPruneConvergeWithNinetySixMixedTiles() {
        let items = (0..<96).map { i in
            Suggestion(kind: i % 2 == 0 ? "movie" : "series", imdb: "tt\(i)", title: "t\(i)", poster: "https://example.test/p\(i)",
                       wide: i % 3 == 0 ? "" : "https://example.test/w\(i)", reason: .popular)
        }
        let geo = MosaicGeometry(columnCount: 4, gap: 12, ring: 8, growRatio: 1.8, focusedRowRatio: DesignTokens.Mosaic.focusedRowRatio)
        let viewport = 700.0
        var pool = MosaicPool(items: items)
        var serial = 0
        var columns = (0..<4).map { _ in MosaicColumn() }
        geo.layout(&columns, totalWidth: 390, focus: (col: 1, row: 0))
        var peak = 0
        func fillAll() {
            let visible = Set(columns.flatMap { $0.tiles.map(\.item.imdb) })
            for c in columns.indices {
                geo.fill(&columns[c], viewportHeight: viewport, buffer: DesignTokens.Mosaic.bufferHeight, isFocusedColumn: c == 1,
                         focusedRow: c == 1 ? 0 : nil, pool: &pool, visible: visible, onScreen: visible, serial: &serial)
            }
        }
        fillAll()
        for step in 0..<400 {
            let delta = step < 300 ? 40.0 : -40.0
            for c in columns.indices {
                columns[c].offset = max((columns[c].tiles.first?.top ?? 0) - geo.ring, columns[c].offset + delta)
                geo.prune(&columns[c], viewportHeight: viewport)
            }
            fillAll()
            geo.layout(&columns, totalWidth: 390, focus: (col: 1, row: 0))
            peak = max(peak, columns.reduce(0) { $0 + $1.tiles.count })
            XCTAssertTrue(columns.allSatisfy { !$0.tiles.isEmpty }, "ninguna columna queda vacía (paso \(step))")
            XCTAssertTrue(columns.allSatisfy { $0.tiles.allSatisfy { $0.height > 0 } })
        }
        XCTAssertLessThan(peak, 160, "las piezas vivas no crecen sin tope al desplazar")
    }
}
