import SwiftUI
import OrbitalCore
import OrbitalModels

/// La prueba del renglón de la versión (11 nov 2026, `VersionRowStyle`): lo que dicen L1, L2 y L3 y dónde va cada una.
extension TitleView {
    /// La versión que va a sonar, para la pieza elegida; nil: hoy (el renglón de `ContinueAction`), o si no hay versión que
    /// tocar (sin versiones, sin red: el renglón solo informa, como hoy).
    func versionSummary(_ model: TitleModel, languageName: String?, pending: Bool) -> VersionSummary? {
        guard VersionRowStyle.current != .today else { return nil }
        if pending || model.continueVideoID == nil { return .placeholder }
        guard model.sourceCheck != .none, model.sourceCheck != .offline, let video = model.continueVideoID,
              let source = model.recommendedSource else { return nil }
        let code = model.recommendedLanguage
        let quality = source.qualitySummary
        let language = languageName.map { LanguageFlags.flagged($0, code) }
        let mark = LanguageFlags.flag(code) ?? languageName ?? quality.first ?? ""
        return VersionSummary(full: Text.withFlagImages(([language].compactMap { $0 } + quality).joined(separator: " · ")),
                              compact: Text.withFlagImages(([mark] + quality.prefix(1)).joined(separator: " ")),
                              mark: Text.withFlagImages(mark),
                              spoken: ([languageName].compactMap { $0 } + quality).joined(separator: ", "),
                              open: { openVersions(video) })
    }

    /// L1: bajo las calificaciones, al centro (o a la izquierda en la ficha ancha).
    @ViewBuilder func versionRowWithFacts(_ model: TitleModel, leading: Bool) -> some View {
        if VersionRowStyle.current == .centered, let summary = continueAction(model).summary {
            VersionRowCentered(summary: summary, leading: leading)
        }
    }

    /// L2: la tarjeta a todo lo ancho, justo encima de Guardar · Descargar · Tráiler.
    @ViewBuilder func versionRowTile(_ action: ContinueAction) -> some View {
        if VersionRowStyle.current == .tile, let summary = action.summary { VersionRowTile(summary: summary) }
    }
}
