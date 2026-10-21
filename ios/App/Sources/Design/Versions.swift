import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Elegir versión»: un idioma con sus calidades (solo las que existen). El nombre del idioma y, si toca, «tu idioma» u
/// «original»; debajo, una cápsula por calidad que pasa al siguiente renglón si no cabe (en un iPhone angosto).
struct VersionLanguageRow: View {
    let row: LanguageRow
    let uiLanguage: String
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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // El nombre y, debajo, lo que hay que saber de la fila (las mismas palabras que la TV).
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: row.code == "es" ? Self.spanish(uiLanguage) : Streams.versionLanguageName(row.code, in: uiLanguage))
                    .recipe(.cardTitle, color: DS.text)
                if let note { note.recipe(.footnote, color: row.allMaybe ? DS.warning : DS.textMuted) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            // Con letra de accesibilidad, una por renglón (en dos, «1080p» se partía en tres renglones).
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: DS.Version.chipMinimum), spacing: DS.Space.s2)],
                      alignment: .leading, spacing: DS.Space.s2) {
                ForEach(row.options) { option in
                    VersionChip(option: option, language: Streams.versionLanguageName(row.code, in: uiLanguage)) { pick(option) }
                }
            }
        }
        .padding(DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }
}

/// Una calidad de un idioma: «1080p», su tamaño y lo que la distingue, y si arranca al instante. La recomendada va marcada.
struct VersionChip: View {
    let option: VersionOption
    let language: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(spacing: DS.Space.s1) {
                    Text(verbatim: option.quality).font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text).lineLimit(1).fixedSize()
                    if option.recommended { Image(systemName: "sparkles").font(DS.TextRecipe.caption.font).foregroundStyle(DS.brandMoon) }
                }
                Text(verbatim: Self.facts(option)).recipe(.caption).lineLimit(1)
                HStack(spacing: DS.Space.s1) {
                    Circle().fill(option.cached ? DS.brandMoon : DS.warning).frame(width: DS.Version.dot, height: DS.Version.dot)
                    (option.cached ? Text("Al instante") : Text("Tarda en empezar")).recipe(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s2)
            .background(option.recommended ? DS.fillStrong : DS.fill, in: shape)
            .overlay(shape.strokeBorder(option.recommended ? DS.brandMoon : DS.hairline, lineWidth: option.recommended ? DS.Version.pickedStroke : DS.Size.hairline))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: [language, option.quality, Self.size(option)].compactMap { $0 }.joined(separator: ", "))
                            + Text(verbatim: ", ") + (option.cached ? Text("Al instante") : Text("Tarda en empezar"))
                            + (option.recommended ? Text(verbatim: ", ") + Text("Recomendada") : Text(verbatim: "")))
        .accessibilityIdentifier("version-\(option.quality)")
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
                title.recipe(.secondary, color: DS.text).fontWeight(.semibold)
            }
            detail.recipe(.footnote)
            if !release.isEmpty, evidence == .name || evidence == .maybe {
                Text(verbatim: release).font(DS.TextRecipe.caption.font.monospaced()).foregroundStyle(DS.textMuted).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch evidence { case .checked, .name, .site: DS.brandMoon; case .original, .unknown: DS.textMuted; case .maybe: DS.warning }
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
