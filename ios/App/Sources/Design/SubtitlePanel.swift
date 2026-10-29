import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas del reproductor: los botones con nombre, «Audio y subtítulos» (`SubtitleDock`) y sus partes.

/// «Subtítulos» del panel de abajo: versiones por idioma, el botón, la búsqueda de idioma, el panel (`SubtitleDock`), sincronizar con una línea y la vista previa.

/// Una versión de subtítulos en la lista: el círculo de elegir, el nombre (de la copia o la pista) y sus marcas
/// («Del video», «Coincide con tu copia», las descargas).
struct SubtitleVersionRow: View {
    let title: String
    let selected: Bool
    var fromVideo = false
    var matchesCopy = false
    var downloads: Int?
    var loading = false
    /// El nombre del archivo o de la pista, chico y cortado (el título ya dice lo que importa).
    var detail: String?
    let action: () -> Void

    var body: some View { bodyContent.pointerHover(.highlight) }
    @ViewBuilder private var bodyContent: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(DS.TextRecipe.secondary.font).foregroundStyle(selected ? DS.text : DS.textFaint)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(verbatim: title).recipe(.footnote, color: DS.text).fontWeight(selected ? .semibold : .regular).lineLimit(2)
                    if let detail, !detail.isEmpty { Text(verbatim: detail).recipe(.caption, color: DS.textFaint).lineLimit(1).truncationMode(.middle) }
                    HStack(spacing: DS.Space.s1) {
                        if fromVideo { DSChip(text: "Del video") }
                        if matchesCopy { DSChip(text: "Coincide con tu copia", tone: .good) }
                        if let downloads, downloads > 0 {
                            Label { Text(verbatim: downloads.formatted(.number.notation(.compactName))) } icon: { Image(systemName: "arrow.down.circle") }
                                .recipe(.caption).labelStyle(.titleAndIcon)
                        }
                        if loading { ProgressView().controlSize(.mini) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
            .background(selected ? DS.fillStrong : DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                Image(systemName: code == nil ? "character.bubble" : "character.bubble.fill").font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
        .glassEffect(.regular.interactive(), in: Circle())
        .contentShape(Circle())
        .onTapGesture(perform: open)
        .onLongPressGesture(minimumDuration: DS.Timing.longPressDelay, perform: toggle)
        .sensoryFeedback(.selection, trigger: code)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Audio y subtítulos"))
        .accessibilityValue(Text(verbatim: state))
        .accessibilityHint(Text("Mantén presionado para apagar o prender los subtítulos"))
        .accessibilityAction(.default, open)
        .accessibilityAction(named: code == nil ? Text("Prender subtítulos") : Text("Apagar subtítulos"), toggle)
    }
}

/// «Más idiomas…»: todos los idiomas, con buscador.
struct LanguageSearchList: View {
    let codes: [String]
    /// Los que tienen subtítulos para este video (con cuántas versiones): van primero, aparte.
    var available: [(code: String, count: Int)] = []
    let name: (String) -> String
    let pick: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let all = codes.map { ($0, name($0)) }.sorted { $0.1.localizedCompare($1.1) == .orderedAscending }
        let shown = query.isEmpty ? all : all.filter { $0.1.localizedCaseInsensitiveContains(query) || $0.0.hasPrefix(query.lowercased()) }
        let ready = available.filter { a in query.isEmpty || name(a.code).localizedCaseInsensitiveContains(query) }
            .sorted { name($0.code).localizedCompare(name($1.code)) == .orderedAscending }
        let readyCodes = Set(ready.map(\.code))
        NavigationStack {
            List {
                if !ready.isEmpty {
                    Section("Con subtítulos para este video") {
                        ForEach(ready, id: \.code) { a in
                            Button { pick(a.code); dismiss() } label: {
                                HStack {
                                    Text.flagged(name(a.code)).foregroundStyle(DS.text)
                                    Spacer()
                                    (a.count == 1 ? Text("1 versión") : Text("\(a.count) versiones")).recipe(.footnote)
                                }
                            }
                        }
                    }
                }
                Section(ready.isEmpty ? "Idiomas" : "Buscar en internet") {
                    ForEach(shown.filter { !readyCodes.contains($0.0) }, id: \.0) { code, title in
                        Button { pick(code); dismiss() } label: { Text(verbatim: title).foregroundStyle(DS.text) }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Buscar idioma"))
            .navigationTitle(Text("Más idiomas"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}

/// Centrado si cabe; si no (horizontal, letra grande), se desliza.
struct ScrollIfNeeded: ViewModifier {
    func body(content: Content) -> some View {
        ViewThatFits(in: .vertical) { content; ScrollView { content } }
    }
}

/// Subtítulos rápidos: un panel chico sobre el video (no una hoja que lo tapa), para arreglarlos sin dejar de ver la escena.
/// De arriba abajo: el idioma (Apagados · Español · Inglés · Otro…), la versión con ‹ › y por qué está ahí («Hecho para
/// tu copia», «Del video», descargas) y «N de M», la pregunta «¿Va a tiempo?» al cambiar de versión, el tiempo
/// («− Antes · A tiempo · Después +»), «Sincronizar con una línea» y el tamaño. En horizontal, tres renglones arriba.
struct SubtitleDock: View {
    struct Language: Identifiable {
        let id: String; let title: String; let selected: Bool
        /// Un idioma de otra versión: a qué va («↻ 1080p · en Real-Debrid») y si es una suposición («se supone»).
        var detail: String? = nil
        var guessed = false
        /// Sin conexión y sin subtítulos de ese idioma en el video ni guardados con la descarga: se ve apagado y lo dice.
        var unavailable = false
    }
    /// Los renglones que se abren (uno a la vez).
    enum Section: Hashable { case audio, subtitles, sync, size }
    /// La versión puesta: su nombre, su etiqueta (`strong`: hecha para tu copia, en verde) y «2 de 9».
    struct Version { let title: String; let badge: String?; let strong: Bool; let position: String }
    /// Lo que se pregunta o se avisa debajo de la versión.
    enum Check: Equatable {
        case inSync                // «¿Va a tiempo?» después de cambiar de versión
        case restored(Double)      // «Usamos tu ajuste de +1.5 s» al volver a una versión que ya ajustaste
    }
    /// El audio: las pistas de este archivo y, aparte, los idiomas que solo están en otra versión («Latino · otra versión»).
    var audio: [Language] = []
    var pickAudio: (String) -> Void = { _ in }
    var otherVersions: [Language] = []
    var pickVersion: (String) -> Void = { _ in }
    let languages: [Language]
    let pickLanguage: (String) -> Void
    let otherLanguage: () -> Void
    /// nil sin subtítulos; `loading` mientras llega la versión elegida.
    let version: Version?
    var loading = false
    let canStep: Bool
    let previous: () -> Void
    let next: () -> Void
    let allVersions: () -> Void
    var check: Check?
    var confirm: () -> Void = {}
    var tryAnother: (() -> Void)?
    /// Los nombres de las versiones que ya probaste en este video (tachados).
    var tried: [String] = []
    /// El tiempo solo si los subtítulos los dibuja la app (con AVPlayer no se pueden mover).
    let delay: Double?
    let nudge: (Double) -> Void
    let resetDelay: () -> Void
    /// nil: esta versión no trae frases de texto (PGS) o el motor no lo permite.
    var sync: (() -> Void)?
    let sizeName: String
    let smaller: (() -> Void)?
    let larger: (() -> Void)?
    let done: () -> Void
    /// En horizontal (poco alto): sin título; «Listo» junto a los idiomas y el tiempo junto a la versión.
    var compact = false
    /// El idioma de la app (para los textos armados con números).
    var language = "es"
    /// Lo que dice cada renglón cerrado: el audio puesto, los subtítulos («Español · 2 de 6» o «Apagados»).
    var audioValue = ""
    var subtitleValue = ""
    /// La versión del video («Inglés · 1080p · 12.3 GB») y abrir su página (nil: no hay otras, p. ej. una descarga sin red).
    var videoVersion = ""
    var openVersion: (() -> Void)?
    /// Sin el título «Audio y subtítulos» (en horizontal lo dicen las pestañas de arriba).
    var showsHeader = true
    /// Sin conexión: qué subtítulos hay (los del video y los guardados con la descarga); nil con red.
    var offlineNote: String?
    /// El renglón abierto (el botón de subtítulos abre Subtítulos). Lo guarda la pantalla: el panel se dibuja tres veces (tal cual,
    /// con desplazamiento si no cabe y una copia invisible que lo mide) y cada una recordaba el suyo; al abrir o cerrar un
    /// renglón, la medida no cambiaba y la tarjeta quedaba arriba con espacio muerto abajo.
    @Binding var open: Section?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Renglones que dicen lo que tienes puesto y se abren uno a la vez (antes todo a la vista: en horizontal no cabía y se
        // sentía cargado). Lo mismo en vertical y en horizontal.
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if showsHeader {
                // Con el mismo margen que los nombres y las flechitas de los renglones: el título arriba de «Audio», «Listo»
                // arriba de las flechitas.
                HStack {
                    Text("Audio y subtítulos").recipe(.cardTitle)
                    Spacer()
                    doneButton
                }
                .padding(.horizontal, DS.Space.s3)
            }
            // La pregunta va arriba, a la vista aunque su renglón esté cerrado.
            if let check, version != nil { checkCard(check) }
            if audio.count > 1 || !otherVersions.isEmpty {
                section(.audio, title: "Audio", value: audioValue) {
                    FlowChips(spacing: DS.Space.s1) {
                        ForEach(audio) { a in pill(Text.flagged(a.title), selected: a.selected) { pickAudio(a.id) } }
                        ForEach(otherVersions) { v in otherPill(v) }
                    }
                    .id(audio.map { "\($0.id)\($0.selected)" }.joined() + otherVersions.map(\.id).joined())   // que se redibuje al elegir (ver `FlowChips`)
                }
            }
            // Abierto, el renglón dice solo el idioma: el «N de M» ya va abajo, en el selector (no dos veces).
            section(.subtitles, title: "Subtítulos", value: open == .subtitles ? (subtitleValue.components(separatedBy: " · ").first ?? subtitleValue) : subtitleValue) {
                // Los idiomas llenan el renglón; «Buscar» (una acción, no una opción) es la lupa redonda al final, con contorno.
                HStack(alignment: .top, spacing: DS.Space.s1) {
                    FlowChips(spacing: DS.Space.s1) {
                        ForEach(languages) { l in pill(Text.flagged(l.title), selected: l.selected, unavailable: l.unavailable) { pickLanguage(l.id) } }
                    }
                    Button(action: otherLanguage) {
                        Image(systemName: "magnifyingglass").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.text)
                            .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                            .overlay(Circle().strokeBorder(DS.hairline))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Buscar…"))
                    .accessibilityIdentifier("subtitle-dock-other")
                }
                .id(languages.map { "\($0.id)\($0.selected)\($0.unavailable)" }.joined())
                if let offlineNote {
                    Label { Text(verbatim: offlineNote) } icon: { Image(systemName: "wifi.slash") }
                        .recipe(.caption).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("subtitle-dock-offline")
                }
                if let version { versionRow(version) }
                if !tried.isEmpty, check != nil { triedLine }
            }
            if delay != nil, version != nil {
                section(.sync, title: "Sincronía", value: delayValue) {
                    timeRow
                    if let sync { syncButton(sync) }
                }
            }
            if version != nil {
                section(.size, title: "Tamaño", value: sizeName) { sizeRow }
            }
            versionLink
        }
        .padding(DS.Space.s4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
        .accessibilityElement(children: .contain)
        .animation(DS.Motion.base(reduceMotion), value: open)
    }

    private var delayValue: String {
        let value = delay ?? 0
        // Lo que la app sabe es el ajuste, no si va a tiempo: «Sin ajuste» o el valor.
        return value == 0 ? Strings.tr("Sin ajuste", language: language) : String(format: "%+.1f s", value)
    }

    /// Un renglón: su nombre y lo que tiene puesto; al tocarlo se abre (y se cierra el que estaba abierto).
    private func section<Content: View>(_ id: Section, title: LocalizedStringKey, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Button { open = open == id ? nil : id } label: {
                HStack(spacing: DS.Space.s2) {
                    Text(title).recipe(.secondary, color: DS.text).fontWeight(.semibold)
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: value).recipe(.footnote).lineLimit(1)
                    Image(systemName: open == id ? "chevron.up" : "chevron.down").font(DS.TextRecipe.caption.font.weight(.semibold)).foregroundStyle(DS.textMuted)
                }
                .frame(minHeight: DS.Size.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(verbatim: value))
            .accessibilityHint(open == id ? Text("Cerrar") : Text("Abrir"))
            if open == id { content() }
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.bottom, open == id ? DS.Space.s3 : 0)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
    }

    /// «Versión · Inglés · 1080p · 12.3 GB ›»: abre la página de versiones (por idioma o todas).
    @ViewBuilder private var versionLink: some View {
        if !videoVersion.isEmpty {
            Button { openVersion?() } label: {
                HStack(spacing: DS.Space.s2) {
                    Text("Versión").recipe(.secondary, color: DS.text).fontWeight(.semibold)
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: videoVersion).recipe(.footnote).lineLimit(1)
                    if openVersion != nil { Image(systemName: "chevron.right").font(DS.TextRecipe.caption.font.weight(.semibold)).foregroundStyle(DS.textMuted) }
                }
                .padding(.horizontal, DS.Space.s3)
                .frame(minHeight: DS.Size.touchTarget)
                .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(openVersion == nil)
            .accessibilityIdentifier("player-version")
        }
    }

    /// Un idioma que solo trae otra versión: «Latino» y, abajo, a qué va («↻ 1080p · en Real-Debrid»); si es una suposición,
    /// con borde punteado y «se supone».
    private func otherPill(_ v: Language) -> some View {
        Button { pickVersion(v.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text.flagged(v.title).font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.text)
                if let detail = v.detail { Text(verbatim: detail).recipe(.caption, color: v.guessed ? DS.warning : DS.primary) }
            }
            .lineLimit(1).fixedSize()
            .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s1)
            .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading)
            .background(DS.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(v.guessed ? DS.warning : .clear, style: StrokeStyle(lineWidth: DS.Version.guessLine, dash: [DS.Version.guessDash])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: LanguageFlags.withoutFlags(v.title) + ", " + (v.detail ?? "")))
        .accessibilityHint(Text("Abre otra versión del video en el mismo punto"))
    }

    // MARK: renglones
    private func versionRow(_ version: Version) -> some View {
        HStack(spacing: DS.Space.s2) {
            stepButton("chevron.left", label: "Subtítulo anterior", enabled: canStep, action: previous)
            Button(action: allVersions) {
                VStack(spacing: DS.Space.s1) {
                    HStack(spacing: DS.Space.s1) {
                        Text.flagged(version.title).recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                        if loading { ProgressView().controlSize(.mini) }
                    }
                    HStack(spacing: DS.Space.s1) {
                        if let badge = version.badge {
                            Text(verbatim: badge).font(DS.TextRecipe.caption.font.weight(.bold)).lineLimit(1)
                                .foregroundStyle(version.strong ? DS.onPrimary : DS.text)
                                .padding(.horizontal, DS.Space.s1)
                                .background(version.strong ? DS.success : DS.fillStrong, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
                        }
                        Text(verbatim: version.position).recipe(.caption).monospacedDigit().lineLimit(1)
                    }
                    .minimumScaleFactor(DS.Size.statScale)
                }
                .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Ver todas las versiones"))
            .accessibilityIdentifier("subtitle-dock-versions")
            stepButton("chevron.right", label: "Subtítulo siguiente", enabled: canStep, action: next)
                .accessibilityIdentifier("subtitle-dock-next")
        }
    }

    /// «− Antes · A tiempo · Después +»: dice hacia dónde se mueven (no «+0.5»); el valor del centro vuelve a como venían.
    private var timeRow: some View {
        let value = delay ?? 0
        return HStack(spacing: DS.Space.s1) {
            capsule(Text("− Antes"), label: "Subtítulos antes") { nudge(-PlayerModel.subtitleStep) }
            Button(action: resetDelay) {
                (value == 0 ? Text("A tiempo") : Text(verbatim: String(format: "%+.1f s", value)))
                    .recipe(.footnote, color: DS.text).fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(value == 0 ? Text("A tiempo") : Text(verbatim: String(format: "%+.1f s", value)))
            .accessibilityHint(Text("Volver a como venían"))
            capsule(Text("Después +"), label: "Subtítulos después") { nudge(PlayerModel.subtitleStep) }
        }
        .accessibilityIdentifier("subtitle-dock-time")
    }

    private func syncButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Sincronizar con una línea").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.text)
                .lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                .padding(.horizontal, DS.Space.s3)
                .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                .overlay(Capsule().strokeBorder(DS.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("subtitle-dock-sync")
    }

    private var sizeRow: some View {
        HStack(spacing: DS.Space.s1) {
            Text("Tamaño").recipe(.footnote).fixedSize()
            if !compact { Spacer(minLength: DS.Space.s2) }
            stepButton("minus", label: "Más chico", enabled: smaller != nil) { smaller?() }
            Text(verbatim: sizeName).recipe(.footnote, color: DS.text).fontWeight(.semibold).fixedSize()
                .frame(minWidth: DS.PlayerPanel.sizeValue)
            stepButton("plus", label: "Más grande", enabled: larger != nil) { larger?() }
        }
        .accessibilityElement(children: .contain)
    }

    /// La tarjeta clara de la pregunta (o del aviso del ajuste recordado), con sus dos respuestas del mismo tamaño.
    private func checkCard(_ check: Check) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            switch check {
            case .inSync:
                if !compact {
                    Text("¿Va a tiempo?").recipe(.secondary, color: DS.onSolidPrimary).fontWeight(.bold)
                    Text("Mira unas frases. Si las letras no van con la voz, prueba otra.").recipe(.caption, color: DS.onSolidPrimary)
                }
                HStack(spacing: DS.Space.s2) {
                    if compact { Text("¿Va a tiempo?").recipe(.footnote, color: DS.onSolidPrimary).fontWeight(.bold).fixedSize() }
                    answer(Text("Sí, va bien"), primary: true, action: confirm).accessibilityIdentifier("subtitle-dock-in-sync")
                    if let tryAnother { answer(Text("Probar otra"), primary: false, action: tryAnother).accessibilityIdentifier("subtitle-dock-try-another") }
                }
            case .restored(let value):
                HStack(spacing: DS.Space.s2) {
                    Text(String(format: Strings.tr("Usamos tu ajuste de %@ para esta versión.", language: language), String(format: "%+.1f s", value)))
                        .recipe(.footnote, color: DS.onSolidPrimary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    answer(Text("Bien"), primary: true, action: confirm).fixedSize()
                }
            }
        }
        .padding(DS.Space.s3)
        .background(DS.solidPrimary, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
    }

    private func answer(_ title: Text, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.font(DS.TextRecipe.footnote.font.weight(.semibold)).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                .foregroundStyle(primary ? DS.solidPrimary : DS.onSolidPrimary)
                .padding(.horizontal, DS.Space.s3)
                .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                .background(primary ? DS.onSolidPrimary : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(primary ? .clear : DS.onSolidPrimary.opacity(DesignTokens.Opacity.disabled)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var triedLine: some View {
        HStack(spacing: DS.Space.s1) {
            Text("Ya probaste:").recipe(.caption)
            ForEach(tried, id: \.self) { Text(verbatim: $0).recipe(.caption).strikethrough() }
        }
        .lineLimit(1).minimumScaleFactor(DS.Size.statScale)
    }

    // MARK: piezas
    private var doneButton: some View {
        // Chico: es una salida, no la acción del panel (antes, del tamaño de un botón principal, pesaba más que lo que cierra).
        Button(action: done) { Text("Listo").font(DS.TextRecipe.footnote.font.weight(.semibold)) }
            .buttonStyle(.glassProminent).controlSize(.small).tint(DS.primary).foregroundStyle(DS.onPrimary)
            .accessibilityIdentifier("subtitle-dock-done")
    }

    private func pill(_ title: Text, selected: Bool, unavailable: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.font(DS.TextRecipe.footnote.font.weight(.semibold)).lineLimit(1).fixedSize()
                .strikethrough(unavailable && !selected)
                .foregroundStyle(selected ? DS.onPrimary : unavailable ? DS.textFaint : DS.text)
                // Cada cápsula mide lo de su nombre más aire a los lados (antes todas iguales: «Apagados» quedaba justo o se
                // encogía); lo que sobra se reparte.
                .padding(.horizontal, DS.Space.s3)
                .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                .background(selected ? DS.primary : DS.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(unavailable ? Text("No disponible sin conexión") : Text(verbatim: ""))
    }

    private func capsule(_ title: Text, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.text).lineLimit(1).fixedSize()
                .padding(.horizontal, DS.Space.s3)
                .frame(minHeight: DS.Size.touchTarget)
                .background(DS.fillStrong, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font.weight(.bold)).foregroundStyle(DS.text)
                .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                .background(DS.fillStrong, in: Circle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : DesignTokens.Opacity.faint)
        .accessibilityLabel(Text(label))
    }
}
