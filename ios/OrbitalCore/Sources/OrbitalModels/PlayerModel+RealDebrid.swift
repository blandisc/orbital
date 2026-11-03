import Foundation
import OrbitalCore
import OrbitalAddons

/// Real-Debrid en el reproductor (R5, R6, D5): los avisos de Torrentio, los reintentos que no piden descargas y la causa en
/// palabras cuando no hay qué ver.
extension PlayerModel {
    /// La causa de tu cuenta, si tu cuenta es el problema.
    var accountCause: UnavailableCause? {
        UnavailableCause.first(notice: nil, account: .from(debridHealth, saved: debridSaved?(), now: clock()), language: wantedLanguage)
    }

    /// Por qué no hay qué ver, en palabras y con una salida (D5, R1, R7), cuando se sabe algo mejor que «no hay» o «ninguna
    /// funcionó»: tu Real-Debrid venció, sin Premium, la clave ya no sirve, Real-Debrid no lo dejó bajar o lo está bajando.
    public var cause: UnavailableCause? {
        guard failure == .noSources || failure == .noneWorked else { return nil }
        let account = UnavailableCause.Account.from(debridHealth, saved: debridSaved?(), now: clock())
        return UnavailableCause.first(notice: lastNotice, account: account, language: wantedLanguage)
    }

    /// Las que quedan por probar en un reintento (las que arrancan al instante y no han fallado).
    var remainingInstant: Int { sourceChoices.filter { $0.instant && !failedSources.contains($0.index) }.count }

    /// «Probando otra versión (2 de 3)»: el intento que sigue y cuántos habrá en total, contando solo las que se van a
    /// probar (las que arrancan al instante, hasta `maxSourceRetries + 1`). Así el número del aviso es el de verdad.
    func triedAnother() -> PlayerNotice {
        let total = min(PlaybackRules.maxSourceRetries + 1, failedSources.count + max(1, remainingInstant))
        return .triedAnotherSource(attempt: min(failedSources.count + 1, total), of: total)
    }

    /// Lo que Torrentio mandó en lugar de versiones: si es de tu cuenta («RD error», sin acceso), se le pregunta ya a
    /// Real-Debrid (lo guardado puede decir «Premium» el día que venció, B-P1-1).
    func noteTorrentioNotices(_ notices: [StreamNotice], generation mine: Int) async {
        guard let first = notices.first(where: \.aboutTheAccount) ?? notices.first else { return }
        lastNotice = first
        guard first.aboutTheAccount, let debridTrouble else { return }
        let health = await debridTrouble()
        if mine == generation { debridHealth = health }
    }
}
