import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas del panel «Ajustes del video» y de los botones con nombre del reproductor.

/// Un botón de la fila del reproductor en vertical («Ajustes», «Bloquear», «Ventana», «En la TV»): el ícono arriba y el
/// nombre corto abajo; todos del mismo ancho (la fila se reparte en partes iguales). `accessibility`: el nombre largo.
struct PlayerLabelButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var accessibility: LocalizedStringKey?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s1) {
                Image(systemName: symbol).font(DS.TextRecipe.secondary.font.weight(.semibold)).frame(height: DS.Size.touchTarget / 2)
                Text(title).recipe(.caption, color: DS.text).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(DS.PlayerPanel.labelMinScale)
            }
            .foregroundStyle(DS.text)
            .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget * 1.25)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibility ?? title))
    }
}

/// Un botón redondo de la barra de arriba del reproductor: todos del mismo diámetro (el del toque mínimo).
struct PlayerCircleButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) { PlayerCircleGlyph(symbol: symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(label))
    }
}

/// El círculo de vidrio con su glifo (los botones de la barra de arriba).
struct PlayerCircleGlyph: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text)
            .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
    }
}

/// Bloqueado: el primer toque enseña esto; el botón grande «Desbloquear» es lo único que responde.
struct PlayerUnlockPrompt: View {
    let unlock: () -> Void
    var body: some View {
        VStack(spacing: DS.Space.s3) {
            Label("Pantalla y giro bloqueados", systemImage: "lock.fill").recipe(.footnote, color: DS.text).fontWeight(.semibold)
            Button(action: unlock) {
                Label("Desbloquear", systemImage: "lock.open.fill").font(DS.TextRecipe.secondary.font.weight(.semibold))
                    .padding(.horizontal, DS.Space.s4).frame(minHeight: DS.Size.touchTarget)
            }
            .buttonStyle(.glassProminent).tint(DS.primary).foregroundStyle(DS.onPrimary)
            .accessibilityIdentifier("player-unlock")
        }
        .padding(DS.Space.s4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
    }
}

/// «Siguiente episodio»: la imagen del episodio (si la hay), cuál es, «Ver ahora» con la cuenta atrás en un anillo y «Ahora no».
struct UpNextCard: View {
    let card: UpNext
    /// Cuántos segundos dura la cuenta completa (para el anillo).
    let total: Double
    let watchNow: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            if let thumb = card.thumbnail.flatMap(URL.init(string:)) {
                RemoteImage(url: thumb, maxPoints: DS.PlayerPanel.upNextThumb) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { DS.fill }
                }
                .frame(width: DS.PlayerPanel.upNextThumb, height: DS.PlayerPanel.upNextThumb / DS.Poster.stillAspect)
                .clipShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius / 2, style: .continuous))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Siguiente episodio").recipe(.caption)
                Text(verbatim: [card.label, card.title].filter { !$0.isEmpty }.joined(separator: " · "))
                    .recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(2)
                // Si no caben lado a lado (vertical, SE), uno bajo el otro.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.s2) { upNextButtons }
                    VStack(alignment: .leading, spacing: DS.Space.s2) { upNextButtons }
                }
            }
        }
        .padding(DS.Space.s4).frame(maxWidth: DS.Size.cardMax, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var upNextButtons: some View {
        Button(action: watchNow) {
            HStack(spacing: DS.Space.s2) {
                if card.secondsLeft > 0 { countdown }
                Text("Ver ahora").lineLimit(1)
            }
            .fixedSize()
        }
        .dsPrimaryButton()
        .accessibilityValue(card.secondsLeft > 0 ? Text("Empieza en \(card.secondsLeft) s") : Text(verbatim: ""))
        Button(action: cancel) { Text("Ahora no").lineLimit(1).fixedSize() }.buttonStyle(.glass)
    }

    /// El anillo que se llena hasta que empieza solo, con los segundos dentro.
    private var countdown: some View {
        let progress = total > 0 ? 1 - Double(card.secondsLeft) / total : 1
        return ZStack {
            Circle().stroke(DS.onPrimary.opacity(DesignTokens.Opacity.scrim), lineWidth: DS.PlayerPanel.ringWidth)
            Circle().trim(from: 0, to: progress).stroke(DS.onPrimary, style: StrokeStyle(lineWidth: DS.PlayerPanel.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(DS.Motion.base(false), value: card.secondsLeft)
            Text(verbatim: "\(card.secondsLeft)").recipe(.caption, color: DS.onPrimary).fontWeight(.bold).monospacedDigit()
        }
        .frame(width: DS.PlayerPanel.ring, height: DS.PlayerPanel.ring)
        .accessibilityHidden(true)
    }
}

/// El ícono de un renglón del panel: el símbolo del sistema en su color, sin fondo (como los renglones de Ajustes).
struct PanelIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(color)
            .frame(width: DS.PlayerPanel.icon).accessibilityHidden(true)
    }
}

/// La velocidad en un solo control: − 1× + (un toque, el paso siguiente; el valor siempre a la vista).
struct SpeedStepper: View {
    let rates: [Float]
    let rate: Float
    let set: (Float) -> Void

    var body: some View {
        let index = rates.firstIndex(of: rate) ?? rates.firstIndex(of: 1) ?? 0
        HStack(spacing: 0) {
            step("minus", enabled: index > 0) { set(rates[index - 1]) }.accessibilityLabel(Text("Más lento"))
            Text(verbatim: rate == 1 ? "1×" : String(format: "%g×", rate)).font(DS.TextRecipe.secondary.font.weight(.semibold)).monospacedDigit()
                .foregroundStyle(DS.text).frame(minWidth: DS.PlayerPanel.speedValue)
                .contentTransition(.numericText())
            step("plus", enabled: index < rates.count - 1) { set(rates[index + 1]) }.accessibilityLabel(Text("Más rápido"))
        }
        .background(DS.fill, in: Capsule())
        .sensoryFeedback(.selection, trigger: rate)
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(verbatim: String(format: "%g×", rate)))
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(DS.TextRecipe.footnote.font.weight(.bold))
                .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget * 3 / 4)
        }
        .buttonStyle(.plain).foregroundStyle(enabled ? DS.text : DS.textFaint).disabled(!enabled)
    }
}

/// Un renglón del panel: ícono, nombre y cómo está ahora; con `action`, lleva a su página (chevron).
struct PanelRow<Value: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color
    var action: (() -> Void)?
    @ViewBuilder var value: () -> Value

    var body: some View {
        let row = HStack(spacing: DS.Space.s3) {
            PanelIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).recipe(.secondary, color: DS.text).fontWeight(.semibold)
                value()
            }
            Spacer(minLength: DS.Space.s2)
            if action != nil { Image(systemName: "chevron.right").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textFaint) }
        }
        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
        .contentShape(Rectangle())
        if let action { Button(action: action) { row }.buttonStyle(.plain) } else { row }
    }
}

/// Una opción en cápsula (subtítulos, velocidad, tamaño): la elegida en papel con ✓.
struct PanelChip: View {
    let title: Text
    let selected: Bool
    var font: Font = DS.TextRecipe.footnote.font
    /// Un glifo que acompaña al texto (los ánimos de «Decide por mí»); con él, elegirlo no agrega la palomita.
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s1) {
                if let symbol {
                    Image(systemName: symbol).font(font.weight(.semibold)).symbolVariant(selected ? .fill : .none)
                } else if selected { Image(systemName: "checkmark").font(DS.TextRecipe.caption.font.weight(.bold)) }
                title.font(font).fontWeight(selected ? .semibold : .regular).lineLimit(1)
            }
            .foregroundStyle(selected ? DS.onPrimary : DS.text)   // elegido: el color principal del modo (en claro el papel se perdía en el fondo)
            .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
            .background(selected ? DS.primary : DS.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Un rótulo de grupo dentro del panel («Tu idioma», «Otros», «Tamaño»).
struct PanelGroupTitle: View {
    let title: LocalizedStringKey
    var body: some View { Text(title).recipe(.caption, color: DS.textMuted).textCase(.uppercase).padding(.top, DS.Space.s2) }
}

/// Chips que se acomodan en renglones (los subtítulos de un idioma, las velocidades).
struct FlowChips: Layout {
    var spacing: CGFloat = DS.Space.s2
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing; line = max(line, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}

/// El aviso de la app (una sola familia): arriba, en vidrio, con su glifo de color, el texto y, si la tiene, una acción
/// («Deshacer», «Ver»). Se va solo; tocarlo lo cierra.
struct Toast: View {
    let symbol: String
    let color: Color
    let title: Text
    var detail: Text?
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?
    var seconds: UInt64 = DS.Timing.banner
    let dismiss: () -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        // Una píldora chica y discreta (como los avisos de iOS): el ícono en su color, el texto en una línea y «Ver ›» como enlace.
        HStack(spacing: DS.Space.s2) {
            Image(systemName: symbol).font(DS.TextRecipe.footnote.font.weight(.bold)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                title.recipe(.footnote, color: DS.text).fontWeight(.semibold).lineLimit(1)
                if let detail { detail.recipe(.caption).lineLimit(1) }
            }
            if let actionTitle, let action {
                Button { action(); dismiss() } label: {
                    HStack(spacing: DS.Space.s1) { Text(actionTitle).fontWeight(.semibold); Image(systemName: "chevron.right").font(DS.TextRecipe.caption.font.weight(.bold)) }
                        .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, DS.Space.s1)
            }
        }
        .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s2)
        .glassEffect(.regular, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: dismiss)
        .frame(maxWidth: .infinity)   // al centro, del ancho de lo que dice
        .padding(.horizontal, DS.Space.s4)
        // Con VoiceOver se anuncia y no se va solo (si no, «Deshacer» desaparecía antes de poder llegar a él).
        .task {
            if voiceOver { UIAccessibility.post(notification: .layoutChanged, argument: nil); return }   // VoiceOver lo encuentra y se queda
            try? await Task.sleep(nanoseconds: seconds); dismiss()
        }
        .accessibilityElement(children: .contain)
    }
}

/// El ícono de Infuse (el de su app, de la App Store; se busca una vez y se recuerda). Sin red, el de «abrir en otra app».
struct InfuseIcon: View {
    @AppStorage("infuse-icon-url") private var url = ""

    var body: some View {
        Group {
            if let u = URL(string: url), !url.isEmpty {
                RemoteImage(url: u, maxPoints: DS.PlayerPanel.icon) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFit() } else { fallback }
                }
            } else { fallback }
        }
        .frame(width: DS.PlayerPanel.appIcon, height: DS.PlayerPanel.appIcon)
        .clipShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.appIcon * DS.PlayerPanel.appIconCorner, style: .continuous))
        .task { if url.isEmpty { url = await Self.lookup() ?? "" } }
        .accessibilityHidden(true)
    }

    private var fallback: some View { Image(systemName: "arrow.up.forward.app").resizable().scaledToFit() }

    /// El ícono que la App Store publica para Infuse (com.firecore.infuse).
    static func lookup() async -> String? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=com.firecore.infuse"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first else { return nil }
        return (first["artworkUrl100"] ?? first["artworkUrl60"]) as? String
    }
}

/// Reproducir o pausar: el botón grande del centro (papel, círculo) entre ±10, que son más chicos y de vidrio.
struct PlayPauseButton: View {
    let playing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: DS.PlayerPanel.playGlyph, weight: .bold))   // ds-exception: el glifo del botón grande se mide con el botón, no con Dynamic Type
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(DS.onPrimary)
                .frame(width: DS.PlayerPanel.playButton, height: DS.PlayerPanel.playButton)
                .background(DS.primary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? Text("Pausa") : Text("Continuar"))
    }
}

/// ±10 s junto al botón grande.
struct SkipButton: View {
    let forward: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: forward ? "goforward.10" : "gobackward.10").font(DS.TextRecipe.title.font.weight(.semibold))
                .foregroundStyle(DS.text)
                .frame(width: DS.PlayerPanel.sideButton, height: DS.PlayerPanel.sideButton)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(forward ? Text("Adelantar 10 segundos") : Text("Retroceder 10 segundos"))
    }
}

/// El idioma de los subtítulos en un solo renglón que abre un menú: «Español · 7 opciones ▾».
struct PanelMenuLabel: View {
    let title: String
    let detail: Text
    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Text(verbatim: title).recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(1)
            detail.recipe(.footnote).lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Image(systemName: "chevron.up.chevron.down").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted)
        }
        .padding(DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
        .contentShape(Rectangle())
    }
}

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

    var body: some View {
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

/// La tira para probar subtítulos sobre el video: ‹ › cambian de versión (sin pausar), el nombre y por qué está ahí,
/// la sincronía (−0.5 / +0.5) y ✓ «Este va bien».
struct SubtitleTryStrip: View {
    let title: String
    let reason: Text
    let delay: Double
    let step: Double
    let previous: () -> Void
    let next: () -> Void
    let nudge: (Double) -> Void
    let confirm: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            arrow("chevron.left", label: Text("Versión anterior"), action: previous)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title).recipe(.footnote, color: DS.text).fontWeight(.semibold).lineLimit(1).contentTransition(.numericText())
                reason.recipe(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            arrow("chevron.right", label: Text("Versión siguiente"), action: next)
            Button { nudge(-step) } label: { Text(verbatim: String(format: "−%g s", step)).monospacedDigit().lineLimit(1) }
                .buttonStyle(.glass).accessibilityLabel(Text("Subtítulos antes"))
                .accessibilityHint(Text("Adelantar medio segundo"))
            Button { nudge(step) } label: { Text(verbatim: String(format: "+%g s", step)).monospacedDigit().lineLimit(1) }
                .buttonStyle(.glass).accessibilityLabel(Text("Subtítulos después"))
                .accessibilityHint(Text("Atrasar medio segundo"))
                .accessibilityValue(Text(verbatim: String(format: "%+.1f s", delay)))
            Button(action: confirm) { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(DS.onPrimary) }
                .buttonStyle(.glassProminent).tint(DS.success)
                .accessibilityLabel(Text("Este va bien"))
        }
        .font(DS.TextRecipe.footnote.font)
        .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s2)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: DS.PlayerPanel.tryStripMaxWidth)
        .accessibilityElement(children: .contain)
    }

    private func arrow(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(DS.TextRecipe.secondary.font.weight(.bold)).foregroundStyle(DS.text)
                .frame(width: DS.Size.touchTarget * 3 / 4, height: DS.Size.touchTarget)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
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
        // Prendidos: el idioma («ES») en una placa sólida, como el «CC» de los reproductores, dentro del círculo (antes era
        // una etiqueta en la esquina que se salía). Apagados: la burbuja vacía.
        ZStack {
            if loading { ProgressView().tint(DS.text) }
            else if let code {
                Text(verbatim: code.uppercased()).font(DS.TextRecipe.caption.font.weight(.heavy)).foregroundStyle(DS.onSolidPrimary)
                    .lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                    .padding(.horizontal, DS.Space.s1)
                    .frame(minWidth: DS.Size.touchTarget / 2)
                    .background(DS.solidPrimary, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
            } else {
                Image(systemName: "captions.bubble").font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text)
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
        .accessibilityLabel(Text("Subtítulos"))
        .accessibilityValue(Text(verbatim: state))
        .accessibilityHint(Text("Mantén presionado para apagarlos o prenderlos"))
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
                                    Text(verbatim: name(a.code)).foregroundStyle(DS.text)
                                    Spacer()
                                    Text("\(a.count) versiones").recipe(.footnote)
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

/// Cuando el reproductor no puede: una pantalla propia (no un aviso rojo encima de los controles), con lo que pasó dicho
/// desde tu lado y solo las salidas que sirven en ese caso.
struct PlayerFailureView: View {
    let failure: PlayerModel.Failure
    /// Un episodio (no una película): para decir «este episodio».
    let isEpisode: Bool
    let retry: () -> Void
    let infuse: (() -> Void)?
    let close: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.s4) {
            Image(systemName: symbol).font(DS.TextRecipe.display.font).foregroundStyle(DS.textMuted)
            VStack(spacing: DS.Space.s2) {
                title.recipe(.section).multilineTextAlignment(.center)
                message.recipe(.secondary, color: DS.textMuted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: DS.Size.cardMax)
            VStack(spacing: DS.Space.s2) {
                switch failure {
                case .noSources, .localFile:
                    option(Text("Cerrar"), primary: true, action: close)
                case .network:
                    option(Text("Intentar de nuevo"), primary: true, action: retry)
                    option(Text("Cerrar"), primary: false, action: close)
                case .noneWorked, .sourceDied:
                    option(Text("Intentar de nuevo"), primary: true, action: retry)
                    if let infuse { option(Text("Abrir en Infuse"), primary: false, action: infuse) }
                    option(Text("Cerrar"), primary: false, action: close)
                }
            }
            .frame(maxWidth: DS.Size.cardMax)
        }
        .padding(DS.Space.gutter)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        // En horizontal (poco alto) se desliza en vez de cortar el texto.
        .modifier(ScrollIfNeeded())
        .background(DS.backdropDeep.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch failure {
        case .noSources: "film.stack"
        case .noneWorked, .sourceDied: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .network: "wifi.slash"
        case .localFile: "externaldrive.badge.exclamationmark"
        }
    }

    private var title: Text {
        switch failure {
        case .noSources: Text("Todavía no hay dónde verlo")
        case .noneWorked: Text("No pudimos reproducirlo")
        case .sourceDied: Text("Se cortó el video")
        case .network: Text("Sin conexión")
        case .localFile: Text("No se puede abrir la descarga")
        }
    }

    private var message: Text {
        switch failure {
        case .noSources: isEpisode ? Text("Real-Debrid aún no tiene este episodio. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.")
            : Text("Real-Debrid aún no tiene esta película. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.")
        case .noneWorked: Text("Probamos las fuentes que hay y ninguna respondió. A veces es momentáneo.")
        case .sourceDied: Text("La fuente dejó de responder. Al intentar de nuevo seguimos donde ibas, con otra si hace falta.")
        case .network: Text("Revisa tu conexión a internet e intenta de nuevo.")
        case .localFile: Text("El archivo descargado no se puede leer. Bórralo en Descargas y bájalo otra vez.")
        }
    }

    private func option(_ label: Text, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(primary ? DS.onPrimary : DS.text)
                .frame(maxWidth: .infinity, minHeight: DS.Remote.keyHeight)
                .background(primary ? DS.primary : DS.fillStrong, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Centrado si cabe; si no (horizontal, letra grande), se desliza.
private struct ScrollIfNeeded: ViewModifier {
    func body(content: Content) -> some View {
        ViewThatFits(in: .vertical) { content; ScrollView { content } }
    }
}

/// Subtítulos rápidos: un panel chico sobre el video (no una hoja que lo tapa), para arreglarlos sin dejar de ver la escena.
/// De arriba abajo: el idioma (Apagados · Español · Inglés · Otro…), la versión con ‹ › y por qué está ahí («Hecho para
/// tu copia», «Del video», descargas) y «N de M», la pregunta «¿Va a tiempo?» al cambiar de versión, el tiempo
/// («− Antes · A tiempo · Después +»), «Sincronizar con una línea» y el tamaño. En horizontal, tres renglones arriba.
struct SubtitleDock: View {
    struct Language: Identifiable { let id: String; let title: String; let selected: Bool }
    /// La versión puesta: su nombre, su etiqueta (`strong`: hecha para tu copia, en verde) y «2 de 9».
    struct Version { let title: String; let badge: String?; let strong: Bool; let position: String }
    /// Lo que se pregunta o se avisa debajo de la versión.
    enum Check: Equatable {
        case inSync                // «¿Va a tiempo?» después de cambiar de versión
        case restored(Double)      // «Usamos tu ajuste de +1.5 s» al volver a una versión que ya ajustaste
    }
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

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? DS.Space.s2 : DS.Space.s3) {
            if !compact {
                HStack {
                    Text("Subtítulos").recipe(.cardTitle)
                    Spacer()
                    doneButton
                }
            }
            HStack(spacing: DS.Space.s2) {
                ForEach(languages) { l in pill(Text(verbatim: l.title), selected: l.selected) { pickLanguage(l.id) } }
                pill(Text("Otro…"), selected: false, action: otherLanguage).accessibilityIdentifier("subtitle-dock-other")
                if compact { doneButton }
            }
            if let version {
                if compact {
                    HStack(spacing: DS.Space.s2) {
                        versionRow(version)
                        if delay != nil { Divider().frame(height: DS.Size.touchTarget); timeRow }
                    }
                } else {
                    versionRow(version)
                }
                // Con la pregunta abierta solo se ve la pregunta (lo demás vuelve al contestar).
                if let check {
                    checkCard(check)
                } else {
                    if compact {
                        HStack(spacing: DS.Space.s2) {
                            if delay != nil, let sync { syncButton(sync) }
                            sizeRow
                        }
                    } else {
                        // En vertical cada cosa en su renglón: en un iPhone chico no caben juntas.
                        if delay != nil { timeRow }
                        if delay != nil, let sync { syncButton(sync) }
                        sizeRow
                    }
                }
                if !tried.isEmpty, check != nil { triedLine }
            }
        }
        .padding(compact ? DS.Space.s3 : DS.Space.s4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    // MARK: renglones
    private func versionRow(_ version: Version) -> some View {
        HStack(spacing: DS.Space.s2) {
            stepButton("chevron.left", label: "Versión anterior", enabled: canStep, action: previous)
            Button(action: allVersions) {
                VStack(spacing: DS.Space.s1) {
                    HStack(spacing: DS.Space.s1) {
                        Text(verbatim: version.title).recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
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
            stepButton("chevron.right", label: "Versión siguiente", enabled: canStep, action: next)
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
        Button(action: done) { Text("Listo").fontWeight(.semibold) }.buttonStyle(.glassProminent).tint(DS.primary).foregroundStyle(DS.onPrimary)
            .accessibilityIdentifier("subtitle-dock-done")
    }

    private func pill(_ title: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.font(DS.TextRecipe.footnote.font.weight(.semibold)).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                .foregroundStyle(selected ? DS.onPrimary : DS.text)
                .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                .background(selected ? DS.primary : DS.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

/// «Sincronizar con una línea»: tres frases que vienen; tocas la que escuchas en el momento en que la oyes y el tiempo se
/// ajusta solo (se recuerda para esa versión). Luego, «¿Ya van bien?»: Sí, u Otra vez con las siguientes.
struct SubtitleSyncView: View {
    let lines: [SubtitleLine]
    /// La frase que tocaste y el ajuste que quedó.
    var picked: Double?
    var result: Double?
    let pick: (SubtitleLine) -> Void
    let confirm: () -> Void
    let again: () -> Void
    let back: () -> Void
    var compact = false
    var language = "es"

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? DS.Space.s2 : DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(DS.TextRecipe.secondary.font.weight(.bold)).foregroundStyle(DS.text)
                        .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                        .background(DS.fill, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Volver"))
                Text("Sincronizar con una línea").recipe(.cardTitle).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            }
            if lines.isEmpty {
                Text("Esta versión no trae frases de texto para sincronizar. Usa Antes y Después.").recipe(.footnote)
            } else if let result {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(resultTitle(result)).recipe(.secondary, color: DS.onSolidPrimary).fontWeight(.bold)
                    Text("¿Ya van bien? Se recuerda para esta versión.").recipe(.caption, color: DS.onSolidPrimary)
                    HStack(spacing: DS.Space.s2) {
                        answer(Text("Sí"), primary: true, action: confirm).accessibilityIdentifier("subtitle-sync-yes")
                        answer(Text("Otra vez"), primary: false, action: again).accessibilityIdentifier("subtitle-sync-again")
                    }
                }
                .padding(DS.Space.s3)
                .background(DS.solidPrimary, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
            } else {
                Text("Toca la frase en el momento en que la escuches.").recipe(.footnote)
                ForEach(lines) { line in
                    Button { pick(line) } label: {
                        Text(verbatim: line.text).recipe(.secondary, color: DS.text).lineLimit(compact ? 1 : 2).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading)
                            .padding(.horizontal, DS.Space.s3)
                            .background(picked == line.start ? DS.fillStrong : DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("subtitle-sync-line")
                }
            }
        }
        .padding(compact ? DS.Space.s3 : DS.Space.s4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
    }

    private func resultTitle(_ value: Double) -> String {
        if abs(value) < 0.05 { return Strings.tr("Listo: ya iban a tiempo", language: language) }
        let key = value > 0 ? "Listo: subtítulos %@ s después" : "Listo: subtítulos %@ s antes"
        return String(format: Strings.tr(key, language: language), String(format: "%.1f", abs(value)))
    }

    private func answer(_ title: Text, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.font(DS.TextRecipe.footnote.font.weight(.semibold)).lineLimit(1)
                .foregroundStyle(primary ? DS.solidPrimary : DS.onSolidPrimary)
                .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                .background(primary ? DS.onSolidPrimary : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(primary ? .clear : DS.onSolidPrimary.opacity(DesignTokens.Opacity.disabled)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Ajustes › Subtítulos: una escena de muestra con una línea dibujada con tu estilo (fondo, tamaño, posición).
struct SubtitlePreview: View {
    let look: SubtitleLook

    var body: some View {
        GeometryReader { geo in
            let size = max(DS.Subtitle.minFont, geo.size.width / DS.Poster.stillAspect * look.heightFraction)
            Text("— Así se van a ver.")
                .font(.system(size: size, weight: .semibold))   // ds-exception: la letra se mide con el video, como en el reproductor
                .foregroundStyle(look.text)
                .subtitleLook(look, size: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, geo.size.height * (look.raised ? DS.Subtitle.raisedMargin : DS.Subtitle.edgeMargin) * 2)
        }
        .aspectRatio(DS.Poster.stillAspect, contentMode: .fit)
        .background(LinearGradient(colors: [DS.backdropDeep, DS.warning.opacity(DesignTokens.Opacity.disabled), DS.backdropDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
