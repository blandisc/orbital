import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Audio y subtítulos»: un panel chico sobre el video (no una hoja que lo tapa), para arreglarlos sin dejar de ver la escena.
/// S1 (Fernando, 11 nov 2026): renglones con palomita, todo a la vista, sin cápsulas ni acordeones. Arriba el título (o las
/// pestañas, en horizontal) y «Listo», fijos; debajo la lista, que se desplaza por dentro si no cabe:
/// - Subtítulos: Apagados, un renglón por idioma (el elegido con ✓, su versión en gris y ‹ 1 de 2 ›), «Otro idioma».
/// - Ajustes: Sincronía y Tamaño (con «−» «+»), «Sincronizar con una línea», Audio y la versión del video.
struct SubtitleDock: View {
    /// Un idioma de subtítulos (o «Apagados», con id vacío).
    struct LanguagePick: Identifiable {
        let id: String
        /// El nombre sin bandera (la bandera la pinta el renglón, en su columna).
        let name: String
        var selected = false
        /// La segunda línea: cuántas versiones hay, o por qué no hay («Sin conexión», «No hay para este video»).
        var detail: String?
        /// Se están buscando sus versiones en internet: la ruedita en el lugar de la palomita.
        var searching = false
        /// Sin conexión y sin subtítulos de ese idioma: se ve apagado y lo dice.
        var unavailable = false
    }
    /// La versión puesta del idioma elegido: su nombre, por qué está ahí («Misma versión») y «2 de 9».
    struct Version: Equatable { let title: String; let reason: String?; let index: Int; let count: Int }

    let choices: [LanguagePick]
    let pick: (String) -> Void
    let otherLanguage: () -> Void
    /// Sin conexión: qué subtítulos hay (los del video y los guardados con la descarga); nil con red.
    var offlineNote: String?
    /// nil sin subtítulos o mientras llega la elegida (`loading`).
    let version: Version?
    var loading = false
    let step: (Int) -> Void
    let allVersions: () -> Void
    /// El tiempo solo si los subtítulos los dibuja la app (con AVPlayer no se pueden mover); `restored`: lo puso solo, porque
    /// ya lo habías ajustado para esta versión.
    let delay: Double?
    var restored = false
    let nudge: (Double) -> Void
    let resetDelay: () -> Void
    /// nil: esta versión no trae frases de texto (PGS) o el motor no lo permite.
    var sync: (() -> Void)?
    let sizeName: String
    let smaller: (() -> Void)?
    let larger: (() -> Void)?
    /// El audio puesto («Inglés · 5.1»); nil si no hay de dónde elegir (una sola pista y nada en otra versión).
    var audioValue: String?
    var openAudio: () -> Void = {}
    /// La versión del video («Inglés · 1080p · 12.3 GB») y abrir su página (nil: no hay otras, p. ej. una descarga sin red).
    var videoVersion = ""
    var openVersion: (() -> Void)?
    let done: () -> Void
    /// El idioma de la app (para los textos armados con números).
    var language = "es"
    /// En horizontal: las pestañas «Audio y subtítulos · Versión» en el lugar del título.
    var tabs: AnyView?
    /// Lo que mide entero (título, lista y aire): en vertical el video se acomoda arriba de él.
    var onNeed: (CGFloat) -> Void = { _ in }

    @State private var listHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            // Siempre en un ScrollView del alto de la lista (nunca más): si cabe no se mueve; si no (SE, horizontal, letra
            // grande), se desplaza por dentro y nada se corta en la orilla. Antes un `ViewThatFits` lo dibujaba tres veces.
            ScrollView {
                list.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: listHeight > 0 ? listHeight : nil)
        }
        .padding(DS.Space.s4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
        .accessibilityElement(children: .contain)
        .onChange(of: need, initial: true) { _, value in onNeed(value) }
    }

    private var need: CGFloat {
        listHeight > 0 && headerHeight > 0 ? headerHeight + DS.Space.s3 + listHeight + DS.Space.s4 * 2 : 0
    }

    // MARK: arriba

    private var header: some View {
        HStack(spacing: DS.Space.s2) {
            if let tabs { tabs } else { Text("Audio y subtítulos").recipe(.cardTitle).accessibilityAddTraits(.isHeader) }
            Spacer(minLength: DS.Space.s2)
            Button(action: done) { Text("Listo").font(DS.TextRecipe.label.font) }
                .dsPrimaryButton(size: .small)
                .accessibilityIdentifier("subtitle-dock-done")
        }
        .frame(minHeight: DS.Size.touchTarget)
    }

    // MARK: la lista

    private var list: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            VersionGroup(inset: SubtitleRow.textInset) {
                ForEach(choices) { choice in languageRow(choice) }
                SubtitleRow(lead: .symbol(DS.Symbol.otherLanguage), title: Text("Otro idioma"), mark: .opens,
                            identifier: "subtitle-dock-other", action: otherLanguage)
                if let offlineNote {
                    SubtitleRow(lead: .symbol(DS.Symbol.offline), title: Text("Sin conexión"), detail: Text(verbatim: offlineNote),
                                identifier: "subtitle-dock-offline")
                }
            }
            if version != nil || audioValue != nil || !videoVersion.isEmpty {
                PanelGroupTitle(title: "Ajustes")
                VersionGroup(inset: SubtitleRow.textInset) { settings }
            }
        }
    }

    @ViewBuilder private func languageRow(_ choice: LanguagePick) -> some View {
        if choice.id.isEmpty {
            SubtitleRow(lead: .symbol(DS.Symbol.subtitlesOff), title: Text(verbatim: choice.name), mark: choice.selected ? .check : .none,
                        identifier: "subtitle-dock-off", action: { pick("") }, selected: choice.selected)
        } else if choice.selected {
            selectedRow(choice)
        } else {
            SubtitleRow(lead: .flag(choice.id), title: Text(verbatim: choice.name), detail: choice.detail.map { Text(verbatim: $0) },
                        mark: choice.searching ? .loading : .none, dimmed: choice.unavailable, identifier: "subtitle-dock-\(choice.id)",
                        action: { pick(choice.id) })
        }
    }

    /// El idioma puesto: ✓, su versión en gris y, si hay más de una, ‹ 1 de 2 › debajo. Tocar el nombre abre todas las
    /// versiones (no recarga nada); solo ‹ › cambian de versión.
    private func selectedRow(_ choice: LanguagePick) -> some View {
        let named = version.map { [$0.title, $0.reason].compactMap { $0 }.joined(separator: " · ") }
        let position = version.map { String(format: Strings.tr("%lld de %lld", language: language), $0.index + 1, $0.count) }
        let several = (version?.count ?? 0) > 1
        let steps: AnyView? = several ? AnyView(
            SubtitleSteps(back: "chevron.left", forward: "chevron.right", backLabel: "Subtítulo anterior", forwardLabel: "Subtítulo siguiente",
                          value: Text(verbatim: position ?? ""), backID: "subtitle-dock-previous", forwardID: "subtitle-dock-next", step: step)) : nil
        let spoken = [named.map(LanguageFlags.withoutFlags),
                      version.map { String(format: Strings.tr("versión %lld de %lld", language: language), $0.index + 1, $0.count) }]
            .compactMap { $0 }.joined(separator: ", ")
        return SubtitleRow(lead: .flag(choice.id), title: Text(verbatim: choice.name), detail: named.map { Text.flagged($0) } ?? Text("Cargando…"),
                           mark: loading || version == nil ? .loading : .check, opensList: version != nil, identifier: "subtitle-dock-versions",
                           action: version == nil ? nil : allVersions, below: steps,
                           selected: true, spoken: spoken, hint: "Ver todas las versiones", versionStep: several ? step : nil)
    }

    // MARK: ajustes

    @ViewBuilder private var settings: some View {
        if let delay, version != nil { syncRow(delay) }
        if let sync, version != nil {
            SubtitleRow(lead: .symbol(DS.Symbol.syncWithLine), title: Text("Sincronizar con una línea"), mark: .opens,
                        identifier: "subtitle-dock-sync", action: sync)
        }
        if version != nil { sizeRow }
        if let audioValue {
            SubtitleRow(lead: .symbol(DS.Symbol.audioTrack), title: Text("Audio"), detail: Text.flagged(audioValue), mark: .opens,
                        identifier: "subtitle-dock-audio", action: openAudio)
        }
        if !videoVersion.isEmpty {
            SubtitleRow(lead: .symbol(DS.Symbol.videoVersion), title: Text("Versión"), detail: Text.flagged(videoVersion),
                        mark: openVersion == nil ? .none : .opens, identifier: "player-version", action: openVersion)
        }
    }

    /// «Sincronía»: el valor abajo («A tiempo», «+1.0 s») y «−» «+» de 0.5 s (mantener presionado repite). Con ajuste, tocar el
    /// valor lo regresa a cero; si lo puso solo («recordado para esta versión») lo dice ahí, sin tarjeta aparte.
    private func syncRow(_ value: Double) -> some View {
        let amount = String(format: "%+.1f s", value)
        let detail: Text = value == 0 ? Text("A tiempo")
            : restored ? Text(verbatim: "\(amount) · \(Strings.tr("recordado para esta versión", language: language))")
            : Text("\(Text(verbatim: amount + " · "))\(Image(systemName: DS.Symbol.resetDelay)) \(Text("Volver a cero"))")
        let limit = PlayerModel.subtitleMaxDelay
        let nudgeStep = { (d: Int) in nudge(Double(d) * PlayerModel.subtitleStep) }
        return SubtitleRow(lead: .symbol(DS.Symbol.subtitleSync), title: Text("Sincronía"), detail: detail, identifier: "subtitle-dock-time",
                           action: value == 0 ? nil : resetDelay,
                           trailing: AnyView(SubtitleSteps(back: "minus", forward: "plus", backLabel: "Subtítulos antes", forwardLabel: "Subtítulos después",
                                                           canBack: value > -limit, canForward: value < limit, repeats: true, step: nudgeStep)),
                           spoken: value == 0 ? Strings.tr("A tiempo", language: language) : amount,
                           hint: value == 0 ? nil : "Volver a cero", adjust: nudgeStep)
    }

    private var sizeRow: some View {
        let change = { (d: Int) in _ = d < 0 ? smaller?() : larger?() }
        return SubtitleRow(lead: .symbol(DS.Symbol.subtitleSize), title: Text("Tamaño"), detail: Text(verbatim: sizeName), identifier: "subtitle-dock-size",
                           trailing: AnyView(SubtitleSteps(back: "minus", forward: "plus", backLabel: "Más chico", forwardLabel: "Más grande",
                                                           canBack: smaller != nil, canForward: larger != nil, step: change)),
                           spoken: sizeName, adjust: change)
    }
}
