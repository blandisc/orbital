import Foundation
import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
@testable import OrbitalAddons

/// Los escenarios comunes con la TV (`tests/fixtures/rd-scenarios`, forma v2 acordada con la TV): cada uno por el código de
/// verdad del iPhone (la búsqueda, el orden, la ficha, «Versión», los pedidos y los títulos) contra lo que ahí dice
/// `expected`, y las reglas que valen en todos (las invariantes). Fernando, 3 nov: «análisis de fondo… para que no encuentre
/// yo más errores».
///
/// `RD_SCENARIOS_RECORD=<carpeta>` escribe ahí lo que decide la app (para revisar un escenario nuevo; no reemplaza
/// `expected`: eso se decide a mano).
@MainActor
final class RDScenarioTests: XCTestCase {
    func testEveryScenarioDecidesWhatItSays() async throws {
        let files = try RDScenarioRig.all()
        XCTAssertGreaterThanOrEqual(files.count, 32)
        let record = ProcessInfo.processInfo.environment["RD_SCENARIOS_RECORD"]
        for file in files {
            let rig = try await RDScenarioRig(file)
            let seen = await rig.observe()
            if let record {
                try? FileManager.default.createDirectory(atPath: record, withIntermediateDirectories: true)
                try seen.json.serialized().write(to: URL(fileURLWithPath: record).appendingPathComponent(file))
            }
            if record != nil, rig.scenario["expected"] == nil { continue }
            let expected = try XCTUnwrap(rig.scenario["expected"]?.object, "\(file): sin «expected»")
            XCTAssertFalse(expected.isEmpty, "\(file): «expected» vacío")
            for (key, want) in expected.sorted(by: { $0.key < $1.key }) where !key.hasPrefix("_") {
                let got = seen.json[key] ?? .null
                XCTAssertTrue(Self.matches(want, got), "\(file) › \(key)\n  esperado: \(Self.text(want))\n  la app:   \(Self.text(got))")
            }
        }
    }

    /// Lo esperado puede dejar fuera lo que no importa: en un objeto solo cuentan sus llaves; una lista, en orden y completa.
    static func matches(_ want: JSON, _ got: JSON) -> Bool {
        switch (want, got) {
        case (.object(let w), .object(let g)): return w.allSatisfy { matches($0.value, g[$0.key] ?? .null) }
        case (.array(let w), .array(let g)): return w.count == g.count && zip(w, g).allSatisfy { matches($0, $1) }
        default: return want == got
        }
    }

    static func text(_ json: JSON) -> String { String(data: json.serialized(), encoding: .utf8) ?? "?" }

    // MARK: las invariantes, en todos los escenarios
    func testInvariantsHoldInEveryScenario() async throws {
        for file in try RDScenarioRig.all() {
            let rig = try await RDScenarioRig(file)
            let seen = await rig.observe()
            let title = seen.title, list = seen.list
            let now = rig.now
            let found = list.ranked
            let prefs = list.prefs
            let cards = list.languageRows.flatMap(\.options) + list.moreLanguages.flatMap(\.options)
            let primary = title.primary(now: now)

            // 1 · La ficha y «Versión» no se contradicen: lo que la ficha ofrece existe en la lista con la misma etiqueta.
            if let offered = title.debridOffer?.instantSource {
                XCTAssertTrue(list.languageRows.flatMap(\.options).contains { $0.id == offered.index && $0.cached },
                              "\(file): «Verlo en … al instante» ofrece una que «Versión» no enseña como «Al instante»")
            }
            if primary == .watch, let playing = title.recommendedSource {
                let card = cards.first { $0.id == playing.index }
                XCTAssertNotNil(card, "\(file): «Ver» pone una versión que «Versión» no enseña (\(playing.release))")
                if let card { XCTAssertEqual(card.cached, playing.cached, "\(file): «Ver» y su tarjeta no dicen lo mismo de «Al instante»") }
                XCTAssertEqual(list.languageRows.flatMap(\.options).first { $0.recommended }?.id ?? cards.first { $0.recommended }?.id, playing.index,
                               "\(file): la recomendada de «Versión» no es la que pone «Ver»")
            }
            if let offer = title.debridOffer, let pending = found.first(where: { $0.torrent == offer.torrent }) {
                XCTAssertFalse(pending.instant, "\(file): «Pedirlo y avisarme» de algo que ya arranca al instante")
            }

            // 2 · Nada dice «al instante» si no arrancaría ya; nada dice «Real-Debrid no lo tiene» si hay una al instante en tu idioma.
            for card in cards where card.cached {
                let s = try XCTUnwrap(list.source(card.id))
                XCTAssertTrue(s.instant && s.playbackURL != nil, "\(file): «Al instante» de una que no arranca (\(s.release))")
            }
            let instantMine = found.contains { s in
                s.instant && s.debrid && !SourcesModel.hidden(s) && !s.otherTitle && !s.tags.contains(Streams.otherTitleTag)
                    && Streams.languageScore(s, prefs) >= Streams.languagePoints[.unknown]! - 250
            }
            if instantMine {
                XCTAssertNotEqual(primary, .request, "\(file): «Pedirlo y avisarme» con una al instante en tu idioma")
                XCTAssertNotEqual(title.unavailableCause.map(RDScenarioRig.name), "real_debrid_no_lo_tiene", "\(file)")
            }

            // 3 · Lo que pediste y ya está va primero y es lo que ponen «Ver» y «Ver ahora».
            if let ready = found.first(where: \.requested) {
                XCTAssertEqual(found.first?.index, ready.index, "\(file): la pedida no va primero")
                XCTAssertEqual(title.recommendedSource?.index, ready.index, "\(file): «Ver» no pone la que pediste")
                XCTAssertEqual(primary, .watch, "\(file): con la pedida lista el botón es «Ver»")
                XCTAssertEqual(SourcesModel.toPlay(found, resume: nil, family: nil)?.index, ready.index, "\(file): «Ver ahora» no pone la que pediste")
                XCTAssertTrue(cards.contains { $0.id == ready.index && $0.requested && $0.cached }, "\(file): «Al instante · la pediste» no sale en «Versión»")
            }
            if let request = title.debridRequest, request.state == .ready {
                XCTAssertTrue(found.contains(where: \.requested), "\(file): el pedido está listo y ninguna versión lo dice")
            }

            // 4 · Nunca una de cine, un tráiler, otro título u otro episodio como recomendada u ofrecida.
            for s in [title.recommendedSource, title.debridOffer?.instantSource].compactMap({ $0 }) where found.contains(where: { !Self.bad($0) }) {
                XCTAssertFalse(Self.bad(s), "\(file): se recomienda u ofrece «\(s.release)» (\(s.tags))")
            }
            if let offer = title.debridOffer, let s = found.first(where: { $0.torrent == offer.torrent }), found.contains(where: { !Self.bad($0) }) {
                XCTAssertFalse(Self.bad(s), "\(file): «Pedirlo y avisarme» pediría «\(s.release)»")
            }
            for card in list.languageRows.flatMap(\.options) where card.recommended {
                let s = try XCTUnwrap(list.source(card.id))
                XCTAssertFalse(SourcesModel.hidden(s), "\(file): recomendada de cine o tráiler")
            }

            // 5 · Todo problema tiene su salida: sin «Ver» que funcione, hay qué tocar.
            switch primary {
            case .unavailable?:
                let cause = try XCTUnwrap(title.unavailableCause, "\(file): sin versión y sin decir por qué")
                XCTAssertNotNil(cause.action, "\(file): «\(cause.title())» sin salida")
                if cause.action == .otherVersion { XCTAssertFalse(found.isEmpty, "\(file): «Elegir otra versión» sin otra versión") }
            case .otherVersion?:
                XCTAssertTrue(found.contains { $0.torrent?.hash != title.debridRequest?.hash } || !list.toRequest.isEmpty,
                              "\(file): «Probar otra versión» sin otra versión")
            default: break
            }

            // 6 · El título: en español si existe; el original si su idioma original es el de la app.
            if let tmdb = rig.scenario["tmdb"]?["detail"], tmdb.object != nil {
                let key = rig.kind == "movie" ? "title" : "name", original = rig.kind == "movie" ? "original_title" : "original_name"
                if tmdb["original_language"]?.string == "es" { XCTAssertEqual(title.title, tmdb[original]?.string, "\(file): hecha en español, su título original") }
                else if let es = tmdb[key]?.nonEmptyString { XCTAssertEqual(title.title, es, "\(file): el título en español") }
            }

            // 9 · La causa dice exactamente el texto de la tabla común (`design/vocabulario.json › causas`, en su orden).
            if let key = seen.json["cause"]?.string {
                let causes = try Fixtures.json("../../design/vocabulario.json")["causas"]?.array ?? []
                let index = try XCTUnwrap(RDScenarioRig.causeOrder.firstIndex(of: key), "\(file): causa «\(key)» sin lugar en la tabla")
                let text = (causes[index]["texto"]?.string ?? "") + (seen.json["cause_arg"]?.string ?? "")
                let cause = try XCTUnwrap(title.unavailableCause ?? (key == "not_in_rd" ? .notInDebrid(language: "") : key == "refused" ? .debridRefused : nil))
                XCTAssertEqual(cause.title(), text, "\(file): la causa no dice lo de la tabla común")
            }

            // 7 · La misma versión (torrent) nunca sale dos veces en «Versión» con dos promesas: al instante en un lado y por
            // pedir en otro («Hay que pedirlas» incluida). Una dual sale en sus dos idiomas, pero igual en los dos.
            var promises: [String: Set<Bool>] = [:]
            for card in cards { if let hash = list.source(card.id)?.torrent?.hash { promises[hash, default: []].insert(card.cached) } }
            for wanted in list.toRequest { if let hash = list.source(wanted.id)?.torrent?.hash { promises[hash, default: []].insert(false) } }
            for (hash, said) in promises { XCTAssertEqual(said.count, 1, "\(file): \(hash) sale al instante y por pedir a la vez") }
            let requestable = Set(list.toRequest.compactMap { list.source($0.id)?.torrent?.hash })
            let onCards = Set(cards.compactMap { list.source($0.id)?.torrent?.hash })
            XCTAssertTrue(requestable.isDisjoint(with: onCards), "\(file): «Hay que pedirlas» repite una versión de arriba: \(requestable.intersection(onCards))")

            // 8 · «Ver ahora» de un pedido listo pone exactamente ese torrent (o su enlace de tu Real-Debrid), nunca «la mejor».
            if let ready = title.debridRequest, ready.state == .ready {
                let playing = SourcesModel.toPlay(found, resume: nil, family: nil)
                XCTAssertEqual(playing?.torrent?.hash, ready.hash, "\(file): «Ver ahora» no pone lo que pediste (\(playing?.release ?? "nada"))")
                let said = seen.json["play_now"]?.string
                XCTAssertTrue(said == ready.hash || said == "ready_source", "\(file): «play_now» \(said ?? "null") no es lo pedido")
            }
        }
    }

    /// De cine, un tráiler, en 3D, de otro año («¿Otro título?») u otra temporada («¿Otro episodio?»): nunca la recomendada ni
    /// la ofrecida (si hay otra). Un nombre que no menciona el título (`otherTitle`) solo baja: puede ser su nombre en otro
    /// país («Farsante» es «Phony» en España), y en tu idioma le gana a otro idioma (pregunta abierta en el README).
    static func bad(_ s: Source) -> Bool {
        SourcesModel.hidden(s) || s.tags.contains(Streams.otherTitleTag) || s.tags.contains(Streams.otherEpisodeTag) || s.tags.contains("3D")
    }
}
