import SwiftUI
import OrbitalCore
import OrbitalModels

/// V1 · «Versión» como lista (Fernando, 9 nov: V1 + V3): renglones con íconos, sin cápsulas. Tu idioma va primero con su
/// bandera de encabezado; los demás, bajo «Otros idiomas» con la bandera en cada renglón. Tocar el renglón reproduce (o la
/// pide, si hay que pedirla); mantenerlo presionado da los detalles y las demás acciones.

/// El encabezado de un grupo de renglones: «🇲🇽 Latino» (tu idioma) u «Otros idiomas».
struct VersionGroupHeader: View {
    let title: Text
    var body: some View {
        title.recipe(.cardTitle, color: DS.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.Space.s2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Un grupo de renglones en una sola tarjeta, con una raya fina entre uno y otro (como Música o TV de Apple).
struct VersionGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Rectangle().fill(DS.hairline).frame(height: DS.Stroke.hairline).padding(.leading, DS.Space.s3 + DS.Version.mark) }
                    row
                }
            }
        }
        .dsCard(translucent: true)
    }
}

/// Tu idioma primero, con su bandera de encabezado; los demás bajo «Otros idiomas», con la bandera en cada renglón. `row`
/// arma cada renglón (la hoja «Versión» y el reproductor ponen su toque y su menú).
struct VersionLanguageList<Row: View>: View {
    let rows: [LanguageRow]
    let uiLanguage: String
    @ViewBuilder let row: (LanguageRow, VersionOption, Bool) -> Row

    var body: some View {
        let yours = rows.first.flatMap { $0.yours ? $0 : nil }
        let others = rows.filter { $0.code != yours?.code }
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let yours {
                VersionGroupHeader(title: Text("\(Text.flag(yours.code))\(Text(verbatim: VersionText.name(yours.code, uiLanguage)))"))
                VersionGroup { ForEach(yours.options) { row(yours, $0, false) } }
            }
            if !others.isEmpty {
                if yours != nil { VersionGroupHeader(title: Text("Otros idiomas")) }
                VersionGroup { ForEach(others) { r in ForEach(r.options) { row(r, $0, true) } } }
            }
        }
    }
}

/// Un ícono de estado de una versión: qué es, de qué color y cómo se dice (VoiceOver y la ⓘ).
struct VersionMark: Equatable {
    let symbol: String
    let color: Color
    let words: String

    /// ⚡ al instante, ☁︎ hay que pedirla (o cómo va, si ya la pediste), el triángulo si Real-Debrid no la dejó bajar y ? si
    /// el idioma es «tal vez» (el triángulo es solo de «no lo dejó bajar», PT10).
    static func marks(_ option: VersionOption, cloud: DebridRequestStatus?, _ tr: (String) -> String) -> [VersionMark] {
        var marks: [VersionMark] = []
        if option.evidence == .maybe { marks.append(VersionMark(symbol: "questionmark.circle", color: DS.warning, words: tr("Tal vez"))) }
        if option.refused {
            marks.append(VersionMark(symbol: DebridRequestWords.Icon.refused, color: DS.warning, words: tr("Real-Debrid no lo dejó bajar")))
        } else if option.speed == .realDebridMustDownload, let cloud {
            marks.append(VersionMark(symbol: cloud.symbol, color: cloud.warn ? DS.warning : DS.textMuted, words: cloud.title))
        } else if option.speed == .realDebridMustDownload {
            marks.append(VersionMark(symbol: DS.Symbol.cloud, color: DS.warning, words: tr("Hay que pedirla")))
        } else if option.speed == .inRealDebrid {
            marks.append(VersionMark(symbol: "bolt.fill", color: DS.success, words: tr(option.requested ? "Al instante · la pediste" : "Al instante")))
        }
        return marks
    }
}

/// Un renglón: ✦ si es la recomendada, la calidad (con la bandera y el idioma si va en «Otros idiomas»), los íconos de
/// estado y el tamaño a la derecha. Tocarlo hace lo de siempre (`action`); mantenerlo presionado, `menu` con `VersionPreview`.
struct VersionListRow<Menu: View>: View {
    let option: VersionOption
    let code: String
    let uiLanguage: String
    /// En «Otros idiomas»: la bandera y el nombre del idioma en el renglón.
    var showsLanguage = false
    /// Ya pedida: cómo va en la nube.
    var cloud: DebridRequestStatus?
    let action: () -> Void
    @ViewBuilder let menu: () -> Menu
    @Environment(\.locale) private var locale

    private func tr(_ key: String) -> String { Strings.tr(key, language: uiLanguage) }

    var body: some View { bodyContent.pointerHover(.highlight) }
    @ViewBuilder private var bodyContent: some View {
        let marks = VersionMark.marks(option, cloud: cloud, tr)
        let language = VersionText.name(code, uiLanguage)
        let size = VersionText.size(option, locale: locale)
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "sparkles").font(DS.TextRecipe.caption.font).foregroundStyle(DS.brandMoon)
                    .frame(width: DS.Version.mark).opacity(option.recommended ? 1 : 0).accessibilityHidden(true)
                Text(verbatim: option.quality).font(DS.TextRecipe.labelLarge.font).foregroundStyle(DS.text).lineLimit(1).fixedSize()
                if showsLanguage {
                    Text("\(Text.flag(code))\(Text(verbatim: language))").recipe(.footnote).lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                ForEach(marks, id: \.symbol) { mark in
                    Image(systemName: mark.symbol).font(DS.TextRecipe.footnote.font).foregroundStyle(mark.color)
                }
                if let size { Text(verbatim: size).recipe(.footnote).monospacedDigit().lineLimit(1).fixedSize() }
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: DS.Size.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menu() } preview: { VersionPreview(option: option, code: code, uiLanguage: uiLanguage, marks: marks) }
        .accessibilityLabel(Text(verbatim: ([language, option.quality, size] + marks.map(\.words) + [option.recommended ? tr("Recomendada") : nil]).compactMap { $0 }.joined(separator: ", ")))
        .accessibilityHint(Text(option.speed == .realDebridMustDownload && !option.refused ? "Toca para pedirla. Mantén presionado para más." : "Toca para verla. Mantén presionado para más."))
        .accessibilityIdentifier("version-\(code)-\(option.quality)")
    }
}

/// Lo que se ve al mantener presionado un renglón (lo que decía la tarjeta): el idioma y la calidad, sus datos, cómo sabemos
/// el idioma, qué más trae, de qué complemento viene y, si toca, «¿Otro título?».
struct VersionPreview: View {
    let option: VersionOption
    let code: String
    let uiLanguage: String
    let marks: [VersionMark]
    @Environment(\.locale) private var locale

    var body: some View {
        let language = VersionText.name(code, uiLanguage)
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("\(Text.flag(code))\(Text(verbatim: "\(language) · \(option.quality)"))").recipe(.cardTitle, color: DS.text)
                let facts = [VersionText.size(option, locale: locale), option.badges.isEmpty ? nil : option.badges.joined(separator: " · ")]
                    .compactMap { $0 } + marks.map(\.words)
                Text(verbatim: facts.joined(separator: " · ")).recipe(.footnote)
                HStack(spacing: DS.Space.s1) { AddonMark(kind: option.from); AddonMark.name(option.from).recipe(.caption) }
            }
            if option.otherEpisode {
                DSNotice(text: "¿Otro episodio? El nombre dice otra temporada.", tone: .warn)
            } else if option.otherTitle {
                DSNotice(text: "¿Otro título? El nombre dice otro año: puede ser otra película.", tone: .warn)
            }
            VersionEvidence(evidence: option.evidence, language: language, release: option.release, site: option.site)
            if !option.alsoHas.isEmpty {
                Text("\(Text("También trae: "))\(Text.withFlagImages(option.alsoHas.map { LanguageFlags.flagged(Streams.versionLanguageName($0, in: uiLanguage), $0) }.joined(separator: ", ")))")
                    .recipe(.footnote)
            }
        }
        .padding(DS.Space.s4)
        .frame(width: DS.Version.preview, alignment: .leading)
    }
}
