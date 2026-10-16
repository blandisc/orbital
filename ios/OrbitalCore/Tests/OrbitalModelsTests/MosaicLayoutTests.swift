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
}
