import Foundation
import OrbitalCore

/// ¿Este episodio tiene tu idioma al instante? (Fernando, 13 nov, con la ruleta de Los Simpson: «Sigue pasando que no
/// aparecen las versiones en latino, solamente inglés».) Una sola regla para «Versión» («Hay latino, pero hay que pedirlo a
/// la nube») y el reproductor directo (ruleta, widget, Centro de control, «Continuar»): cuenta solo lo que arranca ya y
/// suena en tu idioma con evidencia sólida. Un «español» que no dice cuál (si quieres latino), un «Multi» o un «tal vez» no
/// cuentan. Es la que usará la ruleta si Fernando decide que evite los episodios sin tu idioma.
@MainActor
public enum YourLanguageNow {
    /// Las que arrancan al instante en tu idioma (ni de cine, ni tráiler, ni de otro título, ni rechazadas por Real-Debrid).
    public static func instant(_ found: [Source], prefs: Preferences) -> [Source] {
        found.filter { $0.instant && !SourcesModel.hidden($0) && !$0.refused && !$0.isOtherTitle && SourcesModel.speaksYours($0, prefs: prefs) }
    }

    /// Hay al menos una versión en tu idioma que arranca al instante.
    public static func available(_ found: [Source], prefs: Preferences) -> Bool { !instant(found, prefs: prefs).isEmpty }

    /// Para la bitácora: «en es-419 al instante: 3» o «sin es-419 al instante: 30 en, 5 fr, 2 es (tal vez)». Por idioma que
    /// suena (el de cada versión según tu orden), solo de las que arrancan al instante.
    public static func summary(_ found: [Source], prefs: Preferences) -> String {
        let yours = instant(found, prefs: prefs).count
        if yours > 0 { return "en \(prefs.wanted) al instante: \(yours)" }
        var counts: [String: Int] = [:], order: [String] = []
        for source in found where source.instant && !SourcesModel.hidden(source) && !source.isOtherTitle {
            let audio = Streams.playingLanguage(source, prefs)
            let code = audio.map { $0.evidence.solid ? SourcesModel.rowCode($0) : "\(SourcesModel.rowCode($0)) (tal vez)" } ?? "sin idioma"
            if counts[code] == nil { order.append(code) }
            counts[code, default: 0] += 1
        }
        let said = order.sorted { counts[$0]! > counts[$1]! }.map { "\(counts[$0]!) \($0)" }.joined(separator: ", ")
        return "sin \(prefs.wanted) al instante: \(said.isEmpty ? "ninguna" : said)"
    }
}
