import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// V4: «Versión» vacía dice la causa con la tabla de «Ver», en su orden, y con su salida.
@MainActor
final class SourcesEmptyCauseTests: XCTestCase {
    func cause(thrown: Error? = nil, online: Bool = true, account: UnavailableCause.Account = .ok, hasToken: Bool = true,
               addonsOff: Bool = false, notices: [StreamNotice] = [], canRequest: Bool = false) -> UnavailableCause {
        SourcesModel.emptyCause(thrown: thrown, online: online, account: account, hasToken: hasToken, addonsOff: addonsOff,
                                notices: notices, canRequest: canRequest, language: "es-419")
    }

    func testAnAddonThatDidNotAnswerSaysItDoesNotKnowAndOffersRetry() {
        let c = cause(thrown: StreamFinderError.incomplete(["Torrentio"]))
        XCTAssertEqual(c, .cannotSearch(reason: StreamFinderError.incomplete(["Torrentio"]).description))
        XCTAssertTrue(c.detail()?.contains("no sé si hay versiones") ?? false, "nunca «no hay»")
        XCTAssertEqual(c.action, .retry)
    }

    func testNobodyAnsweringIsTheAddonsWithInternetAndYourConnectionWithout() {
        XCTAssertEqual(cause(thrown: StreamFinderError.unreachable), .addonsOffline)
        XCTAssertEqual(cause(thrown: StreamFinderError.unreachable, online: false).action, .retry)
    }

    func testYourAccountGoesFirstEvenIfTheSearchFailed() {
        XCTAssertEqual(cause(thrown: StreamFinderError.incomplete([]), account: .expired), .debridExpired)
        XCTAssertEqual(cause(account: .expired).action, .renew)
        XCTAssertEqual(cause(account: .free), .noPremium)
        XCTAssertEqual(cause(hasToken: false), .reconnectDebrid)
        XCTAssertEqual(cause(addonsOff: true).action, .settings)
    }

    func testWhatTorrentioSaidThenTheCloudThenNobody() {
        XCTAssertEqual(cause(notices: [.infringing]), .debridRefused)
        XCTAssertEqual(cause(canRequest: true), .notInDebrid(language: "es-419"))
        XCTAssertEqual(cause(), .nobodyHasIt)
    }
}
