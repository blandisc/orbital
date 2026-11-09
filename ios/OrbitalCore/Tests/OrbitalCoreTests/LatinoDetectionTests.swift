import XCTest
@testable import OrbitalCore

/// Fernando, 9 nov: «no me encuentro a Los Simpson latino en ningún episodio». Nombres reales del Torrentio público para
/// tt0096697 (5x16, 3x17, 7x02, 8x03, 10x05, 15x03, 20x01): el latino existe y tiene que salir primero si lo pides.
final class LatinoDetectionTests: XCTestCase {
    let simpsons = TitleOrigin(language: "en", country: "United States", titles: ["The Simpsons", "Los Simpson"])
    let latino = Preferences(audio: "es", quality: "1080p", spanish: "es-419")

    func stream(_ title: String, file: String, size: String = "49.7 MB", site: String = "ThePirateBay", marks: String = "", name: String = "Torrentio") -> JSON {
        .object(["name": .string(name), "title": .string("\(title)\n👤 15 💾 \(size) ⚙️ \(site)" + (marks.isEmpty ? "" : "\n\(marks)")),
                 "infoHash": "abc", "behaviorHints": .object(["filename": .string(file)])])
    }
    func parse(_ streams: [JSON]) -> [Source] {
        streams.enumerated().map { Streams.parse($0.element, addon: "Torrentio", transportURL: "https://torrentio.strem.fun/manifest.json", index: $0.offset, origin: simpsons) }
    }
    func audio(_ s: JSON) -> [AudioLanguage] { parse([s])[0].audio }

    /// 5x16 real: el paquete «Completa Latino» de 50 MB sin resolución contra el «Español» en .avi (antes le ganaba: no decía
    /// cuál; es el castellano, por «Homer») y el inglés en 1080p. (Un «MULTi-ESP» en 1080p todavía le gana: el peso de
    /// «español sin decir cuál» es común con la TV y cambiarlo es decisión de Fernando.)
    func testTheLatinoPackOutranksSpanishThatDoesNotSayWhich() {
        let completa = stream("Los Simpsons (Completa Latino) 24 !!\nTemporada 05/Los Simpsons 5x16 - Homero ama a Flanders.mp4",
                              file: "Los Simpsons 5x16 - Homero ama a Flanders.mp4", marks: "🇲🇽")
        let homer = stream("Los Simpson: Español: Temporadas 1 A 10\nLos Simpson T05/Los Simpson 5x16 - Homer ama a Flanders.avi",
                           file: "Los Simpson 5x16 - Homer ama a Flanders.avi", size: "174 MB", site: "MagnetDL", marks: "🇪🇸")
        let english = stream("The.Simpsons.S05.1080p.DSNP.WEB-DL.DDP5.1.x264-POWER\nThe.Simpsons.S05E16.1080p.DSNP.WEB-DL.DDP5.1.x264-POWER.mkv",
                             file: "The.Simpsons.S05E16.1080p.DSNP.WEB-DL.DDP5.1.x264-POWER.mkv", size: "493 MB", site: "EXT", name: "Torrentio\n1080p")
        let ranked = Streams.rank(parse([homer, english, completa]), prefs: latino, kind: "series")
        XCTAssertEqual(ranked.first?.dub, "latino", "lo latino de verdad va antes que el castellano y el inglés en 1080p")
        XCTAssertEqual(ranked.first?.release, "Los Simpsons (Completa Latino) 24 !!")
    }

    /// «Los Simpson: Español: Temporadas 1 A 10» (MagnetDL, 🇪🇸): dice «Homer», no «Homero». Es el castellano.
    func testSpanishSimpsonsThatSayHomerAreCastilian() {
        let homer = stream("Los Simpson: Español: Temporadas 1 A 10\nLos Simpson T05/Los Simpson 5x16 - Homer ama a Flanders.avi",
                           file: "Los Simpson 5x16 - Homer ama a Flanders.avi", size: "174 MB", site: "MagnetDL", marks: "🇪🇸")
        XCTAssertEqual(audio(homer), [AudioLanguage("es-ES", .name)])
        let bateador = stream("Los Simpson: Español: Temporadas 1 A 10\nLos Simpson T03/3x17.Homer.Bateador.avi", file: "3x17.Homer.Bateador.avi", site: "MagnetDL", marks: "🇪🇸")
        XCTAssertEqual(audio(bateador), [AudioLanguage("es-ES", .name)])
        // Sin pista de Homero, sigue sin decir cuál (7x02 «Radiactivo-Man»): no se inventa.
        let radiactivo = stream("Los Simpson: Español: Temporadas 1 A 10\nLos Simpson T07/7x02 Radiactivo-Man.avi", file: "7x02 Radiactivo-Man.avi", site: "MagnetDL", marks: "🇪🇸")
        XCTAssertEqual(audio(radiactivo), [AudioLanguage("es", .name)])
    }

    /// «Homero» en el archivo es latino aunque nada más lo diga (8x03 «Homero pòr el campeonato.mp4»).
    func testHomeroIsLatino() {
        let perz = stream("Los Simpsons Audio Latino Temp 8 By The PerzBlazer\n08x03 Homero pòr el campeonato.mp4", file: "08x03 Homero pòr el campeonato.mp4", marks: "🇲🇽")
        XCTAssertEqual(audio(perz).first, AudioLanguage("es-419", .name))
        let bare = stream("Simpsons temporada 8\n08x03 Homero por el campeonato.mp4", file: "08x03 Homero por el campeonato.mp4")
        XCTAssertEqual(audio(bare), [AudioLanguage("es-419", .name)], "sin bandera ni «latino»: Homero basta")
        // «Homer Loves Flanders» en inglés no es castellano (solo se lee «Homer» si el nombre ya dice español).
        let english = stream("The.Simpsons.S05E16.Homer.Loves.Flanders.720p\nThe.Simpsons.S05E16.Homer.Loves.Flanders.mkv", file: "The.Simpsons.S05E16.Homer.Loves.Flanders.mkv")
        XCTAssertEqual(audio(english), [AudioLanguage("en", .original)])
    }

    /// Más formas de decir latino o castellano que salen en los nombres.
    func testMoreWaysToSayWhichSpanish() {
        let cases: [(String, String)] = [
            ("Coco.2017.1080p.WEB-DL.[Lat].mkv", "es-419"), ("Coco.2017.1080p.BluRay.Esp-Lat.x264.mkv", "es-419"),
            ("Coco.2017.1080p.Lat-Ing.WEB-DL.mkv", "es-419"), ("Coco.2017.1080p.WEB-DL.spa_mx.AAC.mkv", "es-419"),
            ("Coco (2017) 1080p Doblaje Mexicano", "es-419"), ("Coco.2017.1080p.BluRay.[Cast].mkv", "es-ES"),
            ("Coco.2017.1080p.Esp-Cast.x264.mkv", "es-ES"), ("Coco (2017) 1080p Español de España", "es-ES"),
        ]
        for (title, code) in cases {
            XCTAssertEqual(audio(stream(title, file: "")).first?.code, code, title)
        }
    }

    /// 🇨🇴, 🇨🇱, 🇵🇪, 🇻🇪 como 🇦🇷: son latino.
    func testLatinAmericanFlags() {
        for flag in ["🇨🇴", "🇨🇱", "🇵🇪", "🇻🇪"] {
            XCTAssertEqual(audio(stream("Encanto.2021.1080p.WEB-DL", file: "", marks: flag)).first, AudioLanguage("es-419", .name), flag)
        }
    }

    /// 7x02 real: «The Simpsons S07 1995 DVDrip Xvid MP3 Dual» con «Episódio 02 - Radioactive Man.avi»: el doblaje es el brasileño.
    func testBrazilianDualByTheFileName() {
        let dual = stream("The Simpsons S07 1995 DVDrip Xvid MP3 Dual\nEpisódio 02 - Radioactive Man.avi", file: "Episódio 02 - Radioactive Man.avi",
                          size: "195.85 MB", site: "MagnetDL", marks: "Dual Audio", name: "Torrentio\nDVDRip")
        XCTAssertEqual(Set(audio(dual).map(\.code)), ["pt", "en"])
        XCTAssertFalse(audio(dual).contains { Streams.spanish.contains($0.code) })
    }

    /// Comet escribe los idiomas con 🌎 («la» es latino): pesa como 🇲🇽 de Torrentio; los demás, «tal vez».
    func testCometLanguageLine() {
        let comet: JSON = .object(["name": "[RD⚡] Comet 1080p", "description": .string("📄 The.Simpsons.S05E16.1080p.WEB-DL.mkv\n📹 WEB-DL\n🌎 la/en\n📦 900 MB"),
                                   "url": "https://x/a.mkv"])
        let src = Streams.parse(comet, addon: "Comet", transportURL: "https://comet.elfhosted.com/x/manifest.json", index: 0, origin: simpsons)
        XCTAssertEqual(src.audio.first, AudioLanguage("es-419", .name))
        XCTAssertEqual(src.dub, "latino")
        XCTAssertEqual(Streams.cometFlags("🌎 Multi es fr"), "Multi Audio 🇪🇸 🇫🇷")
        XCTAssertEqual(Streams.cometFlags("📄 nada"), "")
    }

    /// Lo que nada dice no se pinta como inglés seguro: «se supone» (sin origen) o «el original» (con origen), nunca «lo dice».
    func testNothingSaysItIsNotSure() {
        let plain = stream("The Simpsons Season 1-25", file: "", site: "TorrentGalaxy")
        let unknown = Streams.parse(plain, addon: "Torrentio", transportURL: "", index: 0, origin: nil)
        XCTAssertEqual(unknown.audio, [AudioLanguage("en", .unknown)])
        XCTAssertFalse(unknown.audio[0].evidence.level >= AudioLanguage.Evidence.name.level)
        XCTAssertEqual(audio(plain), [AudioLanguage("en", .original)])
    }
}
