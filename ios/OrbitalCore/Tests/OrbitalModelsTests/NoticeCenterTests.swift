import XCTest
@testable import OrbitalModels

/// La cola de avisos de la app (antes vivía dentro de `AppEnvironment`, sin pruebas).
@MainActor
final class NoticeCenterTests: XCTestCase {
    func testShowsTheLatestWhenTheCurrentHasNoAction() {
        let center = NoticeCenter(queueLimit: 3)
        center.show(Notice(text: "Uno", tone: .info))
        center.show(Notice(text: "Dos", tone: .success))
        XCTAssertEqual(center.current?.text, "Dos")
        XCTAssertEqual(center.waiting, 0)
        XCTAssertNotEqual(center.current?.serial, 0, "cada aviso lleva su número")
    }

    func testAnUndoIsNotOverwrittenAndTheNextWaitsBehind() {
        let center = NoticeCenter(queueLimit: 3)
        var undone = false
        let n = center.register { undone = true }
        center.show(Notice(text: "Quitada de Mi lista", tone: .info, action: .perform(n), actionTitle: "Deshacer"))
        center.show(Notice(text: "Bajando la recomendada", tone: .success, action: .downloads))
        XCTAssertEqual(center.current?.text, "Quitada de Mi lista", "el «Deshacer» sigue a la vista")
        XCTAssertEqual(center.waiting, 1)

        center.perform(n)
        XCTAssertTrue(undone)

        let serial = center.current?.serial ?? 0
        center.dismiss(serial)
        XCTAssertEqual(center.current?.text, "Bajando la recomendada", "al irse, sale el que esperaba")
        XCTAssertEqual(center.waiting, 0)
    }

    func testDismissIgnoresAStaleSerial() {
        let center = NoticeCenter(queueLimit: 3)
        center.show(Notice(text: "Uno", tone: .info))
        center.dismiss(999)
        XCTAssertEqual(center.current?.text, "Uno")
    }

    func testTheQueueKeepsOnlyTheLastOnesAndForgetsTheirActions() {
        let center = NoticeCenter(queueLimit: 2)
        let undo = center.register {}
        center.show(Notice(text: "Con salida", tone: .info, action: .perform(undo)))
        var ran: [Int] = []
        for i in 1...3 {
            let n = center.register { ran.append(i) }
            center.show(Notice(text: "Espera \(i)", tone: .info, action: .perform(n)))
        }
        XCTAssertEqual(center.waiting, 2, "la cola no crece sin límite")
        center.dismiss(center.current!.serial)
        XCTAssertEqual(center.current?.text, "Espera 2", "el más viejo se descartó")
        // El descartado ya no corre nada; los que siguen, sí.
        if case .perform(let n)? = center.current?.action { center.perform(n) }
        XCTAssertEqual(ran, [2])
    }

    func testARepeatedTextWhileWaitingReplacesItsOlderCopy() {
        let center = NoticeCenter(queueLimit: 3)
        let undo = center.register {}
        center.show(Notice(text: "Con salida", tone: .info, action: .perform(undo)))
        center.show(Notice(text: "Igual", tone: .info))
        center.show(Notice(text: "Otro", tone: .info))
        center.show(Notice(text: "Igual", tone: .warn))
        XCTAssertEqual(center.waiting, 2)
        center.dismiss(center.current!.serial)
        XCTAssertEqual(center.current?.text, "Otro")
        center.dismiss(center.current!.serial)
        XCTAssertEqual(center.current?.tone, .warn, "queda la copia más nueva")
    }

    func testObserversHearEachChange() {
        let center = NoticeCenter(queueLimit: 3)
        var changes = 0
        let sub = center.onChange { changes += 1 }
        center.show(Notice(text: "Uno", tone: .info))
        center.dismiss(center.current!.serial)
        XCTAssertEqual(changes, 2)
        sub.cancel()
    }
}
