import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas del reproductor: los botones con nombre, «Audio y subtítulos» (`SubtitleDock`) y sus partes.

/// «Subtítulos» del panel de abajo: versiones por idioma, el botón, la búsqueda de idioma, el panel (`SubtitleDock`), sincronizar con una línea y la vista previa.

/// Una versión de subtítulos en la lista de todas las versiones: un renglón como los del panel (`SubtitleRow`), con su nombre,
/// el archivo o la pista en gris, para sordos o forzados con su ícono y su palabra, si coincide con tu copia y cuántos la
/// bajaron; la puesta con ✓ (antes un círculo de radio y placas de texto).
struct SubtitleVersionRow: View {
    let title: String
    let selected: Bool
    var matchesCopy = false
    var downloads: Int?
    var loading = false
    /// El nombre del archivo o de la pista (o «Ya la probaste · …»).
    var detail: String?
    /// Para sordos o forzados: su ícono y su palabra (S1, 10).
    var kind: (symbol: String, word: String)?
    var language = "es"
    let action: () -> Void

    var body: some View {
        SubtitleRow(lead: .symbol(kind?.symbol ?? DS.Symbol.subtitleVersion), title: Text.flagged(title), detail: detailText,
                    mark: loading ? .loading : selected ? .check : .none, action: action, selected: selected)
            .pointerHover(.highlight)
    }

    private var detailText: Text? {
        var parts: [String] = []
        if let kind { parts.append(kind.word) }
        if matchesCopy { parts.append(Strings.tr("Coincide con tu copia", language: language)) }
        if let downloads, downloads > 0 {
            parts.append(String(format: Strings.tr("%@ descargas", language: language), downloads.formatted(.number.notation(.compactName).locale(Locale(identifier: language)))))
        }
        if let detail, !detail.isEmpty { parts.append(detail) }
        return parts.isEmpty ? nil : Text.withFlagImages(parts.joined(separator: " · "))
    }
}

/// El botón de subtítulos de la barra del reproductor: dice qué está puesto (el ícono lleno y el idioma en corto, «ES»).
/// Un toque abre la hoja de subtítulos; mantenerlo presionado los apaga o los vuelve a prender.
struct SubtitleButton: View {
    /// El idioma puesto en corto («ES»); nil: apagados.
    let code: String?
    /// El estado completo para VoiceOver («Español · 2 de 7», «Desactivados»).
    let state: String
    let loading: Bool
    let open: () -> Void
    let toggle: () -> Void

    var body: some View {
        // «Audio y subtítulos»: la burbuja de iOS (la de su reproductor); llena con subtítulos prendidos, vacía si no.
        ZStack {
            if loading { ProgressView().tint(DS.text) }
            else {
                // Idioma y subtítulos (el botón cambia los dos): antes «text.bubble», que solo decía subtítulos.
                Image(systemName: code == nil ? "character.bubble" : "character.bubble.fill").font(DS.TextRecipe.labelLarge.font).foregroundStyle(DS.text)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
        .glassEffect(.regular.interactive(), in: Circle())
        .contentShape(Circle())
        .onTapGesture(perform: open)
        .onLongPressGesture(minimumDuration: DS.Timing.longPressDelay, perform: toggle)
        .dsFeedback(.selection, trigger: code)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Audio y subtítulos"))
        .accessibilityValue(Text(verbatim: state))
        .accessibilityHint(Text("Mantén presionado para apagar o prender los subtítulos"))
        .accessibilityAction(.default, open)
        .accessibilityAction(named: code == nil ? Text("Prender subtítulos") : Text("Apagar subtítulos"), toggle)
    }
}

/// «Otro idioma»: todos los idiomas, con buscador. Ordenados por su nombre (antes por la bandera que llevaba delante: salía
/// «Búlgaro, Chino, Checo… Catalán»); la bandera la pinta cada renglón.
struct LanguageSearchList: View {
    let codes: [String]
    /// Los que tienen subtítulos para este video (con cuántas versiones): van primero, aparte.
    var available: [(code: String, count: Int)] = []
    /// El nombre del idioma, sin bandera.
    let name: (String) -> String
    let pick: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let byName = { (a: String, b: String) in name(a).localizedStandardCompare(name(b)) == .orderedAscending }
        let matches = { (code: String) in query.isEmpty || name(code).localizedStandardContains(query) || code.hasPrefix(query.lowercased()) }
        let ready = available.filter { matches($0.code) }.sorted { byName($0.code, $1.code) }
        let readyCodes = Set(ready.map(\.code))
        let rest = codes.filter { matches($0) && !readyCodes.contains($0) }.sorted(by: byName)
        NavigationStack {
            List {
                if !ready.isEmpty {
                    Section("Con subtítulos para este video") {
                        ForEach(ready, id: \.code) { a in
                            Button { pick(a.code); dismiss() } label: {
                                HStack {
                                    languageName(a.code)
                                    Spacer()
                                    (a.count == 1 ? Text("1 versión") : Text("\(a.count) versiones")).recipe(.footnote)
                                }
                            }
                        }
                    }
                }
                // Sin encabezado vacío: la sección solo sale si tiene idiomas.
                if !rest.isEmpty {
                    Section(ready.isEmpty ? "Idiomas" : "Buscar en internet") {
                        ForEach(rest, id: \.self) { code in
                            Button { pick(code); dismiss() } label: { languageName(code) }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Buscar idioma"))
            .navigationTitle(Text("Otro idioma"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }

    /// Como los renglones del panel: una sola bandera en su columna fija (o el globo), y el nombre donde empieza el texto.
    private func languageName(_ code: String) -> some View {
        HStack(spacing: DS.Space.s3) {
            Group {
                if let flag = Text.flagMark(SubtitleLanguage.code(code) ?? code) { flag.font(DS.TextRecipe.labelLarge.font) }
                else { Image(systemName: "globe").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted) }
            }
            .frame(width: DS.PlayerPanel.rowLead)
            .accessibilityHidden(true)
            Text(verbatim: name(code)).foregroundStyle(DS.text)
        }
    }
}

/// Centrado si cabe; si no (horizontal, letra grande), se desliza.
struct ScrollIfNeeded: ViewModifier {
    func body(content: Content) -> some View {
        ViewThatFits(in: .vertical) { content; ScrollView { content } }
    }
}
