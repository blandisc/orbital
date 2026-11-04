import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Elegir versión»: un idioma con sus calidades (solo las que existen). El nombre del idioma y, si toca, «tu idioma» u
/// «original»; debajo, una cápsula por calidad que pasa al siguiente renglón si no cabe (en un iPhone angosto).
struct VersionLanguageRow: View {
    let row: LanguageRow
    let uiLanguage: String
    /// RX2-A · lo que ya pediste y baja en la nube dice cómo va («Bajando · 42 %»), no «Por pedir». nil: no está pedida.
    var cloud: (VersionOption) -> String? = { _ in nil }
    let pick: (VersionOption) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Un nombre de idioma a media frase: en minúsculas en español («en latino»), con su mayúscula en inglés («in Latin
    /// American Spanish»).
    static func inline(_ name: String, _ ui: String) -> String { ui.hasPrefix("en") ? name : name.lowercased() }

    /// La fila «Español» se llama así a secas; abajo dice que no se sabe cuál.
    static func spanish(_ ui: String) -> String { ui.hasPrefix("en") ? "Spanish" : "Español" }

    private var note: Text? {
        if row.yours { return Text("Tu idioma") }
        if row.original { return Text("Original") }
        if row.allMaybe { return Text("Tal vez") }
        if row.code == "es" { return Text("No dice si latino o castellano") }
        return nil
    }

    var body: some View { bodyContent.pointerHover(.highlight) }
    @ViewBuilder private var bodyContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // El nombre y, debajo, lo que hay que saber de la fila (las mismas palabras que la TV).
            VStack(alignment: .leading, spacing: 0) {
                (Text("\(Text.flag(row.code))\(Text(verbatim: row.code == "es" ? Self.spanish(uiLanguage) : Streams.versionLanguageName(row.code, in: uiLanguage)))"))
                    .recipe(.cardTitle, color: DS.text)
                if let note { note.recipe(.footnote, color: row.allMaybe ? DS.warning : DS.textMuted) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            // Con letra de accesibilidad, una por renglón (en dos, «1080p» se partía en tres renglones).
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: DS.Version.chipMinimum), spacing: DS.Space.s2)],
                      alignment: .leading, spacing: DS.Space.s2) {
                ForEach(row.options) { option in
                    VersionChip(option: option, language: Streams.versionLanguageName(row.code, in: uiLanguage), cloud: cloud(option)) { pick(option) }
                }
            }
        }
        .padding(DS.Space.s3)
        .dsCard(translucent: true)
    }
}

/// Una calidad de un idioma: «1080p», su tamaño y lo que la distingue, y si arranca al instante. La recomendada va marcada.
struct VersionChip: View {
    let option: VersionOption
    let language: String
    /// Ya pedida: cómo va en la nube («Bajando · 42 %»).
    var cloud: String?
    let action: () -> Void

    var body: some View { bodyContent.pointerHover(.highlight) }
    @ViewBuilder private var bodyContent: some View {
        let shape = RoundedRectangle(cornerRadius: DSCardLevel.row.radius, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(spacing: DS.Space.s1) {
                    Text(verbatim: option.quality).font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text).lineLimit(1).fixedSize()
                    if option.recommended { Image(systemName: "sparkles").font(DS.TextRecipe.caption.font).foregroundStyle(DS.brandMoon) }
                }
                Text(verbatim: Self.facts(option)).recipe(.caption).lineLimit(1)
                // Solo lo que se sabe: al instante si Real-Debrid ya la tiene; si aún no, se dice; si no se sabe, nada.
                // T8-A: la que hay que pedir lo dice corto y con su flecha (antes «Real-Debrid aún no la t…», cortado).
                if option.refused {
                    // FQ2-A: Real-Debrid no la dejó bajar; nunca la recomendada (escenarios comunes con la TV, 3 nov).
                    Label { Text("Real-Debrid no lo dejó bajar") } icon: { Image(systemName: "nosign") }
                        .recipe(.caption, color: DS.warning).labelStyle(.titleAndIcon).lineLimit(1)
                } else if option.speed == .realDebridMustDownload, let cloud {
                    Label { Text(verbatim: cloud) } icon: { Image(systemName: "icloud.and.arrow.down") }
                        .recipe(.caption, color: DS.textMuted).labelStyle(.titleAndIcon).lineLimit(1)
                } else if option.speed == .realDebridMustDownload {
                    Label { Text("Por pedir") } icon: { Image(systemName: "arrow.down.circle") }
                        .recipe(.caption, color: DS.warning).labelStyle(.titleAndIcon).lineLimit(1)
                } else if let speed = Self.speedText(option), let color = Self.speedColor(option.speed) {
                    HStack(spacing: DS.Space.s1) {
                        Circle().fill(color).frame(width: DS.Version.dot, height: DS.Version.dot)
                        speed.recipe(.caption).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s2)
            .dsCard(translucent: true, fill: option.recommended ? DS.fillStrong : nil)
            .overlay(shape.strokeBorder(option.recommended ? .clear : DS.hairline, lineWidth: DS.Stroke.hairline))
            .dsSelectionRing(option.recommended, in: shape)   // la recomendada, con el anillo de lo elegido (D5; antes turquesa)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(Text(verbatim: [language, option.quality, Self.size(option)].compactMap { $0 }.joined(separator: ", ")))\(Self.speedText(option).map { Text("\(Text(verbatim: ", "))\($0)") } ?? Text(verbatim: ""))\(option.recommended ? Text("\(Text(verbatim: ", "))\(Text("Recomendada"))") : Text(verbatim: ""))"))
        .accessibilityIdentifier("version-\(option.quality)")
    }

    /// Qué tan rápido arranca, en palabras: «Al instante» (ya está en Real-Debrid), «Real-Debrid aún no la tiene» o nada.
    static func speedText(_ speed: SourceSpeed) -> Text? {
        switch speed {
        case .inRealDebrid: Text("Al instante")
        case .realDebridMustDownload: Text("Todavía no está en la nube")
        case .unknown: nil
        }
    }

    /// La de una versión: lo que pediste y ya está lo dice («Al instante · la pediste»).
    static func speedText(_ option: VersionOption) -> Text? {
        if option.refused { return Text("Real-Debrid no lo dejó bajar") }
        return option.requested && option.speed == .inRealDebrid ? Text("Al instante · la pediste") : speedText(option.speed)
    }

    static func speedColor(_ speed: SourceSpeed) -> Color? {
        switch speed {
        case .inRealDebrid: DS.success   // listo al instante: el verde de «listo», no el turquesa
        case .realDebridMustDownload: DS.warning
        case .unknown: nil
        }
    }

    static func size(_ option: VersionOption) -> String? {
        option.sizeGB.map { $0 >= 1 ? String(format: "%.1f GB", $0) : String(format: "%.0f MB", $0 * 1000) }
    }

    /// «2.9 GB · DV · Atmos».
    static func facts(_ option: VersionOption) -> String {
        ([size(option)] + option.badges.prefix(2).map { $0 == "Dolby Vision" ? "DV" : $0 }).compactMap { $0 }.joined(separator: " · ")
    }
}

/// Cómo sabemos el idioma de una versión, en palabras (las mismas de la TV) y con su color: lo seguro en turquesa, lo
/// supuesto en gris y lo «tal vez» en ámbar.
struct VersionEvidence: View {
    let evidence: AudioLanguage.Evidence
    let language: String
    let release: String
    let site: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(spacing: DS.Space.s2) {
                Circle().fill(color).frame(width: DS.Version.dot, height: DS.Version.dot)
                title.recipe(.labelLarge, color: DS.text)
            }
            detail.recipe(.footnote)
            if !release.isEmpty, evidence == .name || evidence == .maybe {
                Text(verbatim: release).font(DS.TextRecipe.caption.font.monospaced()).foregroundStyle(DS.textMuted).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s3)
        .dsCard(.row, translucent: true)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch evidence { case .checked, .name, .site: DS.success; case .original, .unknown: DS.textMuted; case .maybe: DS.warning }
    }

    private var title: Text {
        switch evidence {
        case .checked: Text("Comprobado")
        case .name: Text("Lo dice el nombre")
        case .site: Text("Lo dice el sitio")
        case .original: Text("Es el original")
        case .unknown: Text("No dice idioma")
        case .maybe: Text("Tal vez")
        }
    }

    private var detail: Text {
        switch evidence {
        case .checked: Text("Ya la viste: son las pistas de audio del archivo.")
        case .name: Text("El nombre del archivo dice el idioma:")
        case .site: Text("Viene de \(site), que solo sube \(language.lowercased()).")
        case .original: Text("Nada en el nombre lo dice: es el idioma original del título.")
        case .unknown: Text("Nada lo dice y no se sabe el idioma original: suponemos inglés.")
        case .maybe: Text("Hay pistas, pero no seguras (muchas banderas o solo «español»).")
        }
    }
}
