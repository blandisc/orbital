import SwiftUI
import OrbitalCore
import OrbitalModels

/// La versión que va a sonar, para la zona derecha del botón principal (`SplitPlayButton`, L3, Fernando, 11 nov 2026). Es el
/// único lugar de la ficha que arma la versión elegible: no hay renglón aparte (`DesignRulesTests.testVersionLivesInThePlayButton`).
extension TitleView {
    /// nil: el botón va entero. Sin versiones o sin red (el aviso de abajo lo dice), o en una versión de la app que no deja
    /// elegir versión (Orbital, sin `instantStreams`). Mientras se busca, la zona en gris con su ancho (nada brinca).
    func playVersion(_ model: TitleModel, languageName: String?, pending: Bool) -> VersionSummary? {
        guard env.services.capabilities.instantStreams else { return nil }
        if pending || model.continueVideoID == nil { return .searchingPlaceholder }
        guard model.sourceCheck != .none, model.sourceCheck != .offline, let video = model.continueVideoID,
              let source = model.recommendedSource else { return nil }
        let code = model.recommendedLanguage
        let quality = source.qualitySummary
        let mark = LanguageFlags.flag(code) ?? languageName ?? quality.first ?? ""
        return VersionSummary(compact: Text.withFlagImages(([mark] + quality.prefix(1)).joined(separator: " ")),
                              mark: Text.withFlagImages(mark),
                              spoken: ([languageName].compactMap { $0 } + quality).joined(separator: ", "),
                              open: { openVersions(video) })
    }
}
