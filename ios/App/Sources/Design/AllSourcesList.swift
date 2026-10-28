import SwiftUI
import UIKit
import OrbitalCore
import OrbitalModels

/// «Todas las fuentes»: la lista completa y plana para quien quiere ver todo, honesta con lo que sabemos. Arriba, «Filtrar»
/// (orden, solo las que ya están en Real-Debrid, idioma, grabaciones de cine y tráileres) y qué quiere decir cada punto;
/// luego una sección por calidad («4K · 6») con las primeras tres y «+N más». Cada renglón dice en dos líneas la calidad,
/// la imagen y el tamaño (con el punto de qué tan rápido arranca) y sus idiomas («· se supone» si nada lo dice). Tocarlo lo
/// abre ahí mismo (uno a la vez): el nombre técnico, semillas, de dónde viene, cómo sabemos cada idioma y los botones.
struct AllSourcesList: View {
    /// Ya ordenadas (la recomendada primero).
    let sources: [Source]
    /// El índice de la que se está viendo (o la recomendada).
    var current: Int?
    /// `current` es la que se está viendo («La que ves»); si no, la recomendada («Recomendada»).
    var currentIsPlaying = false
    let primary: (LocalizedStringKey, (Source) -> Void)
    var secondary: (LocalizedStringKey, (Source) -> Void)?
    /// El idioma de la app, para los nombres de los idiomas.
    let uiLanguage: String
    /// Tus idiomas (los de este título): el que va a sonar va primero en cada renglón.
    var prefs: Preferences?
    /// Si la acción secundaria aplica a esa fuente (Descargar: solo un archivo, no una lista HLS).
    var offersSecondary: (Source) -> Bool = { _ in true }

    @State private var filter = AllSources.Filter()
    @State private var order = AllSources.Order.recommended
    @State private var expandedGroups: Set<String> = []
    @State private var opened: Int?
    @State private var copied: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let groups = AllSources.groups(sources, filter: filter, order: order,
                                       shownPerGroup: Int.max)   // se corta abajo (para poder abrir un grupo)
        let hidden = AllSources.count(sources, filter: filter).hidden
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                legend
                Spacer(minLength: 0)
                filterMenu
            }
            if groups.isEmpty {
                VStack(spacing: DS.Space.s2) {
                    Text("Ninguna con estos filtros").recipe(.secondary)
                    if filter != AllSources.Filter() {
                        Button("Quitar filtros") { withAnimation(DS.Motion.base(reduceMotion)) { filter = AllSources.Filter() } }
                            .buttonStyle(.bordered).tint(DS.text)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, DS.Space.s4)
            }
            ForEach(groups) { group in section(group) }
            if !filter.showHidden, hidden > 0 {
                Button { withAnimation(DS.Motion.base(reduceMotion)) { filter.showHidden = true } } label: {
                    (hiddenText(hidden) + Text(verbatim: " · ") + Text("Mostrar").foregroundStyle(DS.text))
                        .recipe(.caption, color: DS.textFaint).multilineTextAlignment(.center)
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Arriba: qué quiere decir cada punto y «Filtrar»

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s3) { legendItems }
            VStack(alignment: .leading, spacing: DS.Space.s1) { legendItems }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var legendItems: some View {
        HStack(spacing: DS.Space.s1) { dot(DS.AllSourcesList.ready); Text("en Real-Debrid").recipe(.caption) }
        HStack(spacing: DS.Space.s1) { dot(DS.AllSourcesList.mustDownload); Text("Real-Debrid aún no la tiene").recipe(.caption) }
    }

    private var filterMenu: some View {
        let count = filter.activeCount
        return Menu {
            Section("Ordenar") {
                Picker("Ordenar", selection: $order) {
                    Text("Recomendadas").tag(AllSources.Order.recommended)
                    Text("Más chicas primero").tag(AllSources.Order.smallest)
                    Text("Más semillas primero").tag(AllSources.Order.mostSeeders)
                }
                .pickerStyle(.inline)
            }
            Section("Mostrar") {
                Toggle("Solo las que ya están en Real-Debrid", isOn: $filter.onlyInRealDebrid)
                Picker("Idioma", selection: $filter.language) {
                    Text("Todos").tag(String?.none)
                    ForEach(AllSources.languages(in: sources), id: \.self) { code in
                        (Text.flag(code) + Text(verbatim: Streams.languageName(code, in: uiLanguage))).tag(Optional(code))
                    }
                }
                .pickerStyle(.menu)
                Toggle("Grabaciones de cine y tráileres", isOn: $filter.showHidden)
            }
        } label: {
            DSCapsuleLabel(title: count == 0 ? Text("Filtrar") : Text("Filtrar · \(count)"),
                           symbol: "line.3.horizontal.decrease", selected: count > 0)
        }
        .accessibilityIdentifier("all-sources-filter")
    }

    // MARK: Una calidad

    private func section(_ group: AllSources.Group) -> some View {
        let open = expandedGroups.contains(group.quality)
        let limit = DS.AllSourcesList.shownPerGroup
        let rows = open ? group.shown : Array(group.shown.prefix(limit))
        let more = group.total - rows.count
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            (qualityName(group.quality) + Text(verbatim: " · \(group.total)"))
                .recipe(.eyebrow, color: DS.textMuted)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.index) { i, source in
                    if i > 0 { Divider().overlay(DS.hairline).padding(.leading, DS.Space.s3) }
                    row(source)
                }
            }
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            if more > 0 {
                Button { withAnimation(DS.Motion.base(reduceMotion)) { _ = expandedGroups.insert(group.quality) } } label: {
                    HStack(spacing: DS.Space.s1) {
                        moreText(more, group.quality)
                        Image(systemName: "chevron.forward").imageScale(.small)
                    }
                    .font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.text)
                    .frame(minHeight: DS.Size.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func qualityName(_ quality: String) -> Text { quality == "Otras" ? Text("Otras") : Text(verbatim: quality) }

    private func moreText(_ count: Int, _ quality: String) -> Text {
        quality == "Otras" ? Text("+\(count) más") : Text("+\(count) más en \(quality)")
    }

    private func hiddenText(_ count: Int) -> Text {
        count == 1 ? Text("1 oculta: grabada en el cine o tráiler") : Text("\(count) ocultas: grabadas en el cine o tráileres")
    }

    // MARK: Un renglón

    private func row(_ source: Source) -> some View {
        let isOpen = opened == source.index
        let hidden = AllSources.isHidden(source)
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            Button {
                withAnimation(DS.Motion.base(reduceMotion)) { opened = isOpen ? nil : source.index }
            } label: {
                summary(source)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(source))
            .accessibilityHint(Text(isOpen ? "Toca para cerrar los detalles" : "Toca para ver los detalles"))
            .accessibilityAction(named: Text(primary.0)) { primary.1(source) }
            .modifier(SecondaryAction(action: offersSecondary(source) ? secondary : nil, source: source))
            .accessibilityAction(named: Text("Copiar nombre")) { copy(source) }
            .accessibilityIdentifier("all-sources-row-\(source.index)")
            if isOpen { details(source) }
        }
        .padding(DS.Space.s3)
        .opacity(hidden ? DS.AllSourcesList.hiddenOpacity : 1)
    }

    /// Las dos líneas: «● 1080p · DV · 12.3 GB … La que ves» y los idiomas.
    private func summary(_ source: Source) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    if let color = speedColor(source) { dot(color) }
                    Text(verbatim: facts(source)).recipe(.secondary, color: DS.text).fontWeight(.semibold)
                }
                Spacer(minLength: DS.Space.s2)
                if let marker = marker(source) { marker.recipe(.caption, color: DS.brandMoon).fontWeight(.semibold) }
            }
            languages(source).recipe(.footnote).fixedSize(horizontal: false, vertical: true)
            if let tag = AllSources.hiddenTag(source) {
                (tag == "CAM" ? Text("Grabada en el cine") : Text("Tráiler")).recipe(.caption, color: DS.warning)
            }
            if source.tags.contains(Streams.otherTitleTag) || source.otherTitle { Text("¿Otro título?").recipe(.caption, color: DS.warning) }
        }
    }

    /// Lo que se ve al abrirlo: el nombre técnico, semillas y origen, cómo sabemos cada idioma, qué tan rápido arranca y los botones.
    private func details(_ source: Source) -> some View {
        let ui = uiLanguage
        let origin = [source.addon, source.site].filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !source.release.isEmpty { technical(source.release) }
            if let file = AllSources.fileName(source) { technical(file) }
            let extra = [source.seeders > 0 ? String(format: Strings.tr("%lld semillas", language: uiLanguage), source.seeders) : nil, origin.isEmpty ? nil : origin].compactMap { $0 }
            if !extra.isEmpty { Text(verbatim: extra.joined(separator: " · ")).recipe(.data) }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ForEach(Array(AllSources.languageEvidence(source).enumerated()), id: \.offset) { _, item in
                    (Text.flag(item.code) + Text(verbatim: VersionLanguageRow.inline(Streams.versionLanguageName(item.code, in: ui), ui) + ": ") + evidence(item.kind))
                        .recipe(.footnote)
                }
            }
            switch SourceSpeed(source) {
            case .inRealDebrid: Text("Ya está en Real-Debrid").recipe(.footnote, color: DS.text)
            case .realDebridMustDownload: Text("Real-Debrid aún no la tiene: puede tardar en abrir").recipe(.footnote, color: DS.warning)
            case .unknown: EmptyView()
            }
            if source.tags.contains(Streams.otherTitleTag) {
                Text("¿Otro título? El nombre dice otro año: puede ser otra película.").recipe(.footnote, color: DS.warning)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s2) { buttons(source) }
                VStack(alignment: .leading, spacing: DS.Space.s2) { buttons(source) }
            }
            .padding(.top, DS.Space.s1)
        }
        .transition(.opacity)
    }

    @ViewBuilder private func buttons(_ source: Source) -> some View {
        Button { primary.1(source) } label: { Text(primary.0).lineLimit(1) }
            .dsPrimaryButton().accessibilityIdentifier("all-sources-primary")
        if let secondary, offersSecondary(source) {
            Button { secondary.1(source) } label: { Text(secondary.0).lineLimit(1) }
                .buttonStyle(.glass).accessibilityIdentifier("all-sources-secondary")
        }
        if !AllSources.copyName(source).isEmpty {
            Button { copy(source) } label: {
                Label { copied == source.index ? Text("Copiado") : Text("Copiar nombre") } icon: { Image(systemName: copied == source.index ? "checkmark" : "doc.on.doc") }
                    .lineLimit(1)
            }
            .buttonStyle(.glass)
        }
    }

    private func technical(_ name: String) -> some View {
        Text(verbatim: name).font(DS.TextRecipe.caption.font.monospaced()).foregroundStyle(DS.textMuted)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }

    private func copy(_ source: Source) {
        UIPasteboard.general.string = AllSources.copyName(source)
        copied = source.index
    }

    // MARK: Textos

    /// «1080p · DV · 12.3 GB» (sin tamaño si no se sabe; una sola insignia de imagen).
    private func facts(_ source: Source) -> String {
        let size: String? = source.size > 0
            ? (source.size >= 1_000_000_000 ? String(format: "%.1f GB", Double(source.size) / 1e9) : String(format: "%.0f MB", Double(source.size) / 1e6))
            : nil
        return [source.resolution.isEmpty ? "SD" : source.resolution, AllSources.hdrBadge(source), size].compactMap { $0 }.joined(separator: " · ")
    }

    /// «🇲🇽 Latino · también 🇺🇸 inglés»: el que va a sonar primero y marcado; los demás después, en gris. Y «· se supone»
    /// (con cuáles, si no son todos) cuando nada lo dice.
    private func languages(_ source: Source) -> Text {
        let ui = uiLanguage
        let items = prefs.map { AllSources.languageEvidence(source, playingFirst: $0) } ?? AllSources.languageEvidence(source)
        guard let first = items.first else { return Text(verbatim: "") }
        var text = Text.flag(first.code) + Text(verbatim: Streams.versionLanguageName(first.code, in: ui)).foregroundStyle(DS.text).fontWeight(.semibold)
        let rest = items.dropFirst()
        if !rest.isEmpty {
            text = text + Text(verbatim: " · ") + Text("también") + Text(verbatim: " ")
            for (i, item) in rest.enumerated() {
                if i > 0 { text = text + Text(verbatim: ", ") }
                text = text + Text.flag(item.code) + Text(verbatim: VersionLanguageRow.inline(Streams.versionLanguageName(item.code, in: ui), ui))
            }
        }
        let guessed = items.filter { $0.kind == .assumed }
        if !guessed.isEmpty {
            text = text + Text(verbatim: " · ") + Text("se supone")
            if guessed.count < items.count {
                text = text + Text(verbatim: ": " + guessed.map { VersionLanguageRow.inline(Streams.versionLanguageName($0.code, in: ui), ui) }.joined(separator: ", "))
            }
        }
        return text
    }

    private func evidence(_ kind: AllSources.EvidenceKind) -> Text {
        switch kind {
        case .checked: Text("comprobado")
        case .name: Text("lo dice el nombre")
        case .site: Text("lo dice el sitio")
        case .assumed: Text("se supone")
        }
    }

    private func marker(_ source: Source) -> Text? {
        guard source.index == current else { return nil }
        return currentIsPlaying ? Text("La que ves") : Text("Recomendada")
    }

    private func speedColor(_ source: Source) -> Color? {
        switch SourceSpeed(source) {
        case .inRealDebrid: DS.AllSourcesList.ready
        case .realDebridMustDownload: DS.AllSourcesList.mustDownload
        case .unknown: nil
        }
    }

    private func speedText(_ source: Source) -> Text? {
        switch SourceSpeed(source) {
        case .inRealDebrid: Text("en Real-Debrid")
        case .realDebridMustDownload: Text("Real-Debrid aún no la tiene")
        case .unknown: nil
        }
    }

    private func accessibilityLabel(_ source: Source) -> Text {
        var label = Text(verbatim: facts(source) + ", ") + languages(source)
        if let speed = speedText(source) { label = label + Text(verbatim: ", ") + speed }
        if let marker = marker(source) { label = label + Text(verbatim: ", ") + marker }
        if let tag = AllSources.hiddenTag(source) { label = label + Text(verbatim: ", ") + (tag == "CAM" ? Text("Grabada en el cine") : Text("Tráiler")) }
        if source.tags.contains(Streams.otherTitleTag) || source.otherTitle { label = label + Text(verbatim: ", ") + Text("¿Otro título?") }
        return label
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: DS.AllSourcesList.dot, height: DS.AllSourcesList.dot).accessibilityHidden(true)
    }
}

/// La acción secundaria (Descargar) para VoiceOver, solo si la hay.
private struct SecondaryAction: ViewModifier {
    let action: (LocalizedStringKey, (Source) -> Void)?
    let source: Source

    func body(content: Content) -> some View {
        if let action { content.accessibilityAction(named: Text(action.0)) { action.1(source) } } else { content }
    }
}
