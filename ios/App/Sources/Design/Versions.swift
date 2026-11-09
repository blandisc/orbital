import SwiftUI
import OrbitalCore
import OrbitalModels

/// Las palabras de una versión, las mismas en «Versión», la ficha y el reproductor.
enum VersionText {
    /// Un nombre de idioma a media frase: en minúsculas en español («en latino»), con su mayúscula en inglés («in Latin
    /// American Spanish»).
    static func inline(_ name: String, _ ui: String) -> String { ui.hasPrefix("en") ? name : name.lowercased() }

    /// El español que no dice cuál se llama así a secas.
    static func spanish(_ ui: String) -> String { ui.hasPrefix("en") ? "Spanish" : "Español" }

    /// El nombre de un idioma de versión («Latino», «Castellano», «Español» a secas, «Inglés»).
    static func name(_ code: String, _ ui: String) -> String { code == "es" ? spanish(ui) : Streams.versionLanguageName(code, in: ui) }

    /// Qué tan rápido arranca, en palabras: «Al instante» (ya está en Real-Debrid), «Todavía no está en la nube» o nada.
    static func speedText(_ speed: SourceSpeed) -> Text? {
        switch speed {
        case .inRealDebrid: Text("Al instante")
        case .realDebridMustDownload: Text("Todavía no está en la nube")
        case .unknown: nil
        }
    }

    /// «2.9 GB · DV · Al instante»: los datos y, si se sabe, qué tan rápido arranca.
    static func withSpeed(_ facts: String, _ speed: SourceSpeed) -> Text {
        guard let words = speedText(speed) else { return Text(verbatim: facts) }
        return facts.isEmpty ? words : Text("\(Text(verbatim: facts + " · "))\(words)")
    }

    static func size(_ option: VersionOption, locale: Locale) -> String? {
        option.sizeGB.map { ByteSize.text(Int64($0 * 1e9), locale: locale) }
    }

    /// «2,9 GB · DV · Atmos».
    static func facts(_ option: VersionOption, locale: Locale) -> String {
        ([size(option, locale: locale)] + option.badges.prefix(2).map { $0 == "Dolby Vision" ? "DV" : $0 }).compactMap { $0 }.joined(separator: " · ")
    }
}

/// «Elegir versión» mientras se buscan (Fernando, 6 nov: «el parrafito sin info»): la forma de la lista de verdad (tu idioma
/// con dos renglones y «Otros idiomas» con uno) en gris, para que al llegar nada brinque. VoiceOver dice «Buscando versiones».
struct VersionsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(0..<2, id: \.self) { group in
                Text(verbatim: group == 0 ? "🇲🇽 Latino" : "Otros idiomas").recipe(.cardTitle, color: DS.text).padding(.top, DS.Space.s2)
                VStack(spacing: 0) {
                    ForEach(0..<(group == 0 ? 2 : 1), id: \.self) { _ in
                        HStack(spacing: DS.Space.s2) {
                            Text(verbatim: "1080p").font(DS.TextRecipe.labelLarge.font)
                            Spacer(minLength: DS.Space.s2)
                            Text(verbatim: "2.9 GB").recipe(.footnote)
                        }
                        .padding(.horizontal, DS.Space.s3)
                        .frame(minHeight: DS.Size.touchTarget)
                    }
                }
                .dsCard(translucent: true)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Buscando versiones"))
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

/// V4 · «Versión» sin ninguna versión: la causa con la tabla de «Ver» (`UnavailableCause`), su ícono, la frase y su única
/// salida (Renovar, Ajustes, Reintentar). «Pedir a la nube» no lleva botón aquí: las que se pueden pedir están abajo, en
/// «Hay que pedirlas». Nunca una hoja en blanco.
struct VersionsEmptyCause: View {
    let cause: UnavailableCause
    let uiLanguage: String
    /// La salida de la causa; nil si aquí no aplica (se queda sin botón).
    let perform: (UnavailableCause.Action) -> (() -> Void)?

    private func tr(_ key: String) -> String { Strings.tr(key, language: uiLanguage) }

    var body: some View {
        let detail = cause.detail(tr, languageName: { VersionText.inline(Streams.versionLanguageName($0, in: uiLanguage), uiLanguage) })
        DSEmptyState(symbol: cause.symbol, title: Text(verbatim: cause.title(tr)), message: detail.map { Text(verbatim: $0) }) {
            if let action = cause.action, let run = perform(action) {
                Button(UnavailableCause.label(action, tr), systemImage: action.symbol, action: run)
                    .accessibilityIdentifier("sources-empty-action")
            }
        }
        .accessibilityIdentifier("sources-empty")
    }
}

extension UnavailableCause {
    /// El ícono de cada causa, el mismo en «Versión» y en el reproductor (`PlayerFailureView`).
    var symbol: String {
        switch self {
        case .debridExpired, .noPremium, .reconnectDebrid: "person.crop.circle.badge.exclamationmark"
        case .debridRefused: DebridRequestWords.Icon.refused   // PT10: el triángulo, como en Tus pedidos
        case .notInDebrid, .downloading: DS.Symbol.cloud
        case .nobodyHasIt: "magnifyingglass"
        case .unreleased: "calendar"
        case .cannotSearch, .addonsOffline: "exclamationmark.icloud"
        case .noAddonsOn: "puzzlepiece.extension"
        }
    }
}

extension UnavailableCause.Action {
    /// El ícono del botón de cada salida.
    var symbol: String {
        switch self {
        case .renew: "arrow.up.right"   // abre el navegador
        case .settings: "gear"
        case .retry: "arrow.clockwise"
        case .otherVersion: "rectangle.stack"
        case .request: DS.Symbol.cloud
        }
    }
}
