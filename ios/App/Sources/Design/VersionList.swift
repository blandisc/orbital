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
    /// Se explica al tocarlo (un globito con `words`): «¿Otro título?», que antes era un aviso amarillo de texto (R4).
    var tip = false

    /// ⚡ al instante, ☁︎ hay que pedirla (o cómo va, si ya la pediste), el triángulo si Real-Debrid no la dejó bajar y ⓘ si
    /// el idioma es «tal vez» (el triángulo es solo de «no lo dejó bajar», PT10; amarillo solo para eso, I6).
    static func marks(_ option: VersionOption, cloud: DebridRequestStatus?, _ tr: (String) -> String) -> [VersionMark] {
        var marks: [VersionMark] = []
        // I6 · la duda va en gris (ⓘ): el amarillo queda para el riesgo de verdad (Real-Debrid no la dejó bajar).
        if option.evidence == .maybe { marks.append(VersionMark(symbol: "info.circle", color: DS.textMuted, words: tr("Tal vez"))) }
        // R4 · «¿Otro título?» (u otro episodio): su ícono, que se explica al tocarlo y en VoiceOver; nunca una cápsula de texto.
        if option.otherEpisode {
            marks.append(VersionMark(symbol: DS.Symbol.otherTitle, color: DS.textMuted, words: tr("¿Otro episodio? El nombre dice otra temporada."), tip: true))
        } else if option.otherTitle {
            marks.append(VersionMark(symbol: DS.Symbol.otherTitle, color: DS.textMuted, words: tr("¿Otro título? El nombre dice otro año: puede ser otra película."), tip: true))
        }
        if option.refused {
            marks.append(VersionMark(symbol: DebridRequestWords.Icon.refused, color: DS.warning, words: tr("Real-Debrid no lo dejó bajar")))   // edición: un rechazo solo existe con pedidos a la nube (instantStreams)
        } else if option.speed == .realDebridMustDownload, let cloud {
            marks.append(VersionMark(symbol: cloud.symbol, color: cloud.warn ? DS.warning : DS.textMuted, words: cloud.title))
        } else if option.speed == .realDebridMustDownload {
            marks.append(VersionMark(symbol: DS.Symbol.cloud, color: DS.textMuted, words: tr("Hay que pedirla")))
        } else if option.speed == .inRealDebrid {
            marks.append(VersionMark(symbol: DS.Symbol.instant, color: DS.success, words: tr(option.requested ? "Al instante · la pediste" : "Al instante")))
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
            // En un renglón; si no cabe (letra grande, SE), el idioma baja a su propio renglón en vez de perderse (revisión 2
            // del 11 nov: el renglón recomendado se quedaba sin el idioma, justo lo que decide).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s2) {
                    recommendedMark
                    quality
                    if showsLanguage { languageText(language).fixedSize() }
                    Spacer(minLength: DS.Space.s2)
                    trailing(marks, size)
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack(spacing: DS.Space.s2) {
                        recommendedMark
                        quality
                        Spacer(minLength: DS.Space.s2)
                        trailing(marks, size)
                    }
                    if showsLanguage { languageText(language).fixedSize(horizontal: false, vertical: true).padding(.leading, DS.Version.mark + DS.Space.s2) }
                }
                .padding(.vertical, DS.Space.s1)
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

    private var recommendedMark: some View {
        Image(systemName: DS.Symbol.recommended).font(DS.TextRecipe.caption.font).foregroundStyle(DS.brandMoon)
            .frame(width: DS.Version.mark).opacity(option.recommended ? 1 : 0).accessibilityHidden(true)
    }

    private var quality: some View {
        Text(verbatim: option.quality).font(DS.TextRecipe.labelLarge.font).foregroundStyle(DS.text).lineLimit(1).fixedSize()
    }

    private func languageText(_ language: String) -> some View {
        Text("\(Text.flag(code))\(Text(verbatim: language))").recipe(.footnote)
    }

    @ViewBuilder private func trailing(_ marks: [VersionMark], _ size: String?) -> some View {
        ForEach(marks, id: \.symbol) { mark in
            if mark.tip { VersionMarkTip(mark: mark) } else {
                Image(systemName: mark.symbol).font(DS.TextRecipe.footnote.font).foregroundStyle(mark.color)
            }
        }
        if let size { Text(verbatim: size).recipe(.footnote).monospacedDigit().lineLimit(1).fixedSize() }
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
                    .compactMap { $0 } + marks.filter { !$0.tip }.map(\.words)
                Text(verbatim: facts.joined(separator: " · ")).recipe(.footnote)
                HStack(spacing: DS.Space.s1) { AddonMark(kind: option.from); AddonMark.name(option.from).recipe(.caption) }
            }
            // Su ícono con la explicación (R4: antes, un aviso amarillo de texto).
            ForEach(marks.filter(\.tip), id: \.symbol) { mark in
                Label { Text(verbatim: mark.words) } icon: { Image(systemName: mark.symbol) }.recipe(.footnote)
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

/// La primera vez que abres «Versión»: qué quiere decir el destello (la recomendada) y el rayo (lista al instante). Después
/// de verla una vez ya no sale (revisión 2 del 11 nov: los dos íconos no se explicaban en ningún lado).
struct VersionLegend: View {
    static let seenKey = "version-legend-seen"
    @AppStorage(VersionLegend.seenKey) private var seen = false
    /// Al abrir la hoja: si ya se había visto antes. Así no desaparece mientras la lees.
    @State private var shownBefore: Bool?

    var body: some View {
        Group {
            if shownBefore == false {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.s3) { items }
                    VStack(alignment: .leading, spacing: DS.Space.s1) { items }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear { if shownBefore == nil { shownBefore = seen; seen = true } }
    }

    @ViewBuilder private var items: some View {
        Label { Text("Recomendada").recipe(.caption) } icon: { Image(systemName: DS.Symbol.recommended).foregroundStyle(DS.brandMoon) }
            .font(DS.TextRecipe.caption.font)
        Label { Text("Lista al instante").recipe(.caption) } icon: { Image(systemName: DS.Symbol.instant).foregroundStyle(DS.success) }
            .font(DS.TextRecipe.caption.font)
    }
}

/// El ícono de un aviso que se explica al tocarlo (`VersionMark.tip`): un globito con sus palabras, que VoiceOver lee igual.
/// El toque es del ícono, no del renglón (tocar el resto del renglón la sigue abriendo).
struct VersionMarkTip: View {
    let mark: VersionMark
    @State private var shown = false

    var body: some View {
        Image(systemName: mark.symbol).font(DS.TextRecipe.footnote.font).foregroundStyle(mark.color)
            .padding(.horizontal, DS.Space.s1)
            .frame(minHeight: DS.Size.touchTarget)
            .contentShape(Rectangle())
            .onTapGesture { shown = true }
            .popover(isPresented: $shown) {
                Text(verbatim: mark.words).recipe(.footnote, color: DS.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: DS.Version.preview)
                    .padding(DS.Space.s3)
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel(Text(verbatim: mark.words))
    }
}
