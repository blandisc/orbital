import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas del reproductor: los botones con nombre, «Audio y subtítulos» (`SubtitleDock`) y sus partes.

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
        // Arriba la imagen y cuál es; abajo los dos botones lado a lado, del mismo ancho y a todo lo ancho (antes iban uno
        // bajo el otro junto a la imagen y dejaban un hueco debajo de ella).
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                if let thumb = card.thumbnail.flatMap(URL.init(string:)) {
                    RemoteImage(url: thumb, maxPoints: DS.PlayerPanel.upNextThumb) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() } else { DS.fill }
                    }
                    .frame(width: DS.PlayerPanel.upNextThumb, height: DS.PlayerPanel.upNextThumb / DS.Poster.stillAspect)
                    .clipShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius / 2, style: .continuous))
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Siguiente episodio").recipe(.caption)
                    Text(verbatim: [card.label, card.title].filter { !$0.isEmpty }.joined(separator: " · "))
                        .recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: DS.Space.s2) { upNextButtons }
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
            .font(DS.TextRecipe.secondary.font.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .dsPrimaryButton()
        .accessibilityValue(card.secondsLeft > 0 ? Text("Empieza en \(card.secondsLeft) s") : Text(verbatim: ""))
        Button(action: cancel) {
            Text("Ahora no").lineLimit(1).font(DS.TextRecipe.secondary.font.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
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
        // Todo el ancho que le dan (si se lo dan): así un renglón lleno puede estirarse hasta la orilla (ver `placeSubviews`).
        return CGSize(width: width.isFinite ? width : widest, height: y + line)
    }
    /// Cada renglón centra sus piezas a lo alto (una insignia con borde, más baja que una cápsula, ya no queda arriba).
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var lines: [[(LayoutSubview, CGSize)]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, bounds.minX + x + size.width > bounds.maxX { lines.append([]); x = 0 }
            lines[lines.count - 1].append((view, size)); x += size.width + spacing
        }
        var y = bounds.minY
        for (n, line) in lines.enumerated() {
            let height = line.map(\.1.height).max() ?? 0
            // Un renglón lleno (o el único) se estira a todo lo ancho, repartiendo lo que sobra entre sus piezas: sin hueco a la
            // derecha (antes «Apagados · Español · Inglés · Buscar…» ocupaban tres cuartos y el panel iba de orilla a orilla).
            // El último de varios no se estira: una cápsula sola a todo lo ancho parecería un botón.
            let used = line.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(0, line.count - 1))
            let extra = (lines.count == 1 || n < lines.count - 1) && !line.isEmpty ? max(0, bounds.width - used) / CGFloat(line.count) : 0
            var lineX = bounds.minX
            for (view, size) in line {
                let width = size.width + extra
                view.place(at: CGPoint(x: lineX, y: y + (height - size.height) / 2), proposal: ProposedViewSize(width: width, height: size.height))
                lineX += width + spacing
            }
            y += height + spacing
        }
    }
}

/// El aviso de la app (una sola familia): arriba, en vidrio, con su glifo de color, el texto y, si la tiene, una acción
/// («Deshacer», «Ver»). Se va solo; tocarlo lo cierra.
struct Toast: View {
    let tone: DSNotice.Tone
    let title: Text
    var detail: Text?
    var actionTitle: LocalizedStringKey?
    var actionSymbol: String?
    var action: (() -> Void)?
    /// Otro ícono y color que el del tono (el de pasar a la TV: la tele en el color de Orbital).
    var symbol: String?
    var color: Color?
    /// nil: se queda hasta que lo toques o lo deslices (el que te necesita); si no, lo que dure según traiga salida o no.
    var seconds: UInt64?
    let dismiss: () -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// Cuánto se queda según el tono y si trae salida: solo informa, 4 s; con salida, 8 s; si te necesita, hasta que lo toques.
    static func duration(_ tone: DSNotice.Tone, hasAction: Bool) -> UInt64? {
        if hasAction, tone == .warn || tone == .error { return nil }
        return hasAction ? DS.Timing.toastAction : DS.Timing.banner
    }

    static func symbol(_ tone: DSNotice.Tone) -> String {
        switch tone { case .info: "info.circle"; case .success: "checkmark.circle"; case .warn: "exclamationmark.triangle"; case .error: "exclamationmark.circle" }
    }

    static func color(_ tone: DSNotice.Tone) -> Color {
        switch tone { case .info: DS.textMuted; case .success: DS.brandMoon; case .warn: DS.warning; case .error: DS.danger }
    }

    /// Lo que hay que hacer (Conectar, Reintentar) va en la cápsula clara; lo opcional (Otra, Ver, Deshacer), en la gris.
    private var prominent: Bool { tone == .warn || tone == .error }

    var body: some View {
        // Una píldora (como los avisos de iOS): el ícono en su tono, lo que pasó y su dato, y a la derecha la salida en su cápsula
        // (sin «›»: la flecha es para ir a otra pantalla).
        HStack(spacing: DS.Space.s3) {
            Image(systemName: symbol ?? Self.symbol(tone)).font(DS.TextRecipe.body.font.weight(.semibold)).foregroundStyle(color ?? Self.color(tone))
            VStack(alignment: .leading, spacing: 0) {
                title.recipe(.footnote, color: DS.text).fontWeight(.semibold).lineLimit(1)
                // El dato en dos renglones si hace falta (en un iPhone angosto se cortaba justo lo que importa).
                if let detail { detail.recipe(.caption).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button { action(); dismiss() } label: {
                    HStack(spacing: DS.Space.s1) {
                        if let actionSymbol { Image(systemName: actionSymbol).font(DS.TextRecipe.caption.font.weight(.bold)) }
                        Text(actionTitle).fontWeight(.semibold)
                    }
                    .font(DS.TextRecipe.footnote.font).foregroundStyle(prominent ? DS.bg : DS.text)
                    .padding(.horizontal, DS.Space.s3).frame(minHeight: DS.Toast.actionHeight)
                    .background(prominent ? DS.solidPrimary : DS.fillStrong, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .padding(.leading, DS.Space.s4).padding(.trailing, action == nil ? DS.Space.s4 : DS.Space.s2).padding(.vertical, DS.Space.s2)
        .glassEffect(.regular, in: Capsule())
        .overlay { if prominent { Capsule().strokeBorder(Self.color(tone).opacity(DS.Toast.toneStroke), lineWidth: DS.Toast.strokeWidth) } }
        .contentShape(Capsule())
        .onTapGesture(perform: dismiss)
        // Deslizar hacia abajo lo quita (el que te necesita no se va solo).
        .gesture(DragGesture(minimumDistance: DS.Toast.swipe).onEnded { if $0.translation.height > 0 { dismiss() } })
        .frame(maxWidth: DS.Toast.maxWidth)
        .padding(.horizontal, DS.Space.s3)
        // Con VoiceOver se anuncia y no se va solo (si no, la salida desaparecía antes de poder llegar a ella).
        .task {
            if voiceOver { UIAccessibility.post(notification: .layoutChanged, argument: nil); return }
            guard let seconds else { return }
            try? await Task.sleep(nanoseconds: seconds); dismiss()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Cerrar"), dismiss)
    }
}

/// Reproducir o pausar: el botón grande del centro, el único con círculo (de vidrio), entre ±10.
struct PlayPauseButton: View {
    let playing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: DS.PlayerPanel.playGlyph, weight: .bold))   // ds-exception: el glifo del botón grande se mide con el botón, no con Dynamic Type
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(DS.text)
                .frame(width: DS.PlayerPanel.playButton, height: DS.PlayerPanel.playButton)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? Text("Pausa") : Text("Continuar"))
    }
}

/// ±10 s junto al botón grande: la flecha en círculo con el 10, sin fondo (se ve qué lado regresa y cuál adelanta).
struct SkipButton: View {
    let forward: Bool
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button { taps += 1; action() } label: {
            Image(systemName: forward ? "goforward.10" : "gobackward.10")
                .font(.system(size: DS.PlayerPanel.skipGlyph, weight: .medium))   // ds-exception: el glifo se mide con el botón grande, no con Dynamic Type
                .symbolEffect(.rotate.byLayer, options: .speed(2), value: taps)
                .foregroundStyle(DS.text)
                .frame(width: DS.PlayerPanel.sideButton, height: DS.PlayerPanel.sideButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(forward ? Text("Adelantar 10 segundos") : Text("Retroceder 10 segundos"))
    }
}

/// La barra de avance fina (la misma en vertical y en horizontal): el riel, lo visto en el color de Orbital y una perilla
/// chica que crece mientras la arrastras; al arrastrar, la intro, el resumen y los créditos se marcan más claros.
struct PlayerScrubBar: View {
    let value: Double
    let duration: Double
    /// Los tramos marcados (intro, resumen, créditos), en segundos.
    var marks: [ClosedRange<Double>] = []
    let change: (Double) -> Void
    let editing: (Bool) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (t: Double) in CGFloat(min(max(t / max(duration, 1), 0), 1)) * width }
            ZStack(alignment: .leading) {
                Capsule().fill(DS.track).frame(height: DS.PlayerPanel.scrubTrack)
                // Solo mientras arrastras (para no caer en la intro o los créditos): quieta, la marca de los créditos al final
                // de la barra parecía una rayita gris suelta.
                ForEach(Array((dragging ? marks : []).enumerated()), id: \.offset) { _, mark in
                    Rectangle().fill(DS.textFaint)
                        .frame(width: max(0, x(mark.upperBound) - x(mark.lowerBound)), height: DS.PlayerPanel.scrubTrack)
                        .offset(x: x(mark.lowerBound))
                }
                Capsule().fill(DS.brandMoon).frame(width: x(value), height: DS.PlayerPanel.scrubTrack)
                Circle().fill(DS.text)
                    .frame(width: dragging ? DS.PlayerPanel.scrubKnobActive : DS.PlayerPanel.scrubKnob,
                           height: dragging ? DS.PlayerPanel.scrubKnobActive : DS.PlayerPanel.scrubKnob)
                    .offset(x: x(value) - (dragging ? DS.PlayerPanel.scrubKnobActive : DS.PlayerPanel.scrubKnob) / 2)
                    .animation(.snappy, value: dragging)
            }
            .frame(width: width, height: DS.PlayerPanel.scrubHit)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !dragging { dragging = true; editing(true) }
                    change(Double(min(max(g.location.x / max(width, 1), 0), 1)) * duration)
                }
                .onEnded { _ in dragging = false; editing(false) })
        }
        .frame(height: DS.PlayerPanel.scrubHit)
        .sensoryFeedback(.selection, trigger: dragging)
    }
}

/// Un renglón del menú «⋯» del reproductor: el ícono, el nombre y, a la derecha, un dato (el zoom puesto).
struct PlayerMenuRow: View {
    let title: LocalizedStringKey
    let symbol: String
    var detail: Text?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: symbol).font(DS.TextRecipe.secondary.font.weight(.semibold)).frame(width: DS.Size.touchTarget / 2)
                Text(title).recipe(.secondary, color: DS.text).lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                if let detail { detail.recipe(.footnote).lineLimit(1) }
            }
            .foregroundStyle(DS.text)
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: DS.Size.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                Image(systemName: code == nil ? "text.bubble" : "text.bubble.fill").font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text)
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
                                    Text(verbatim: name(a.code)).foregroundStyle(DS.text)
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
        case .noneWorked: Text("No pude reproducirlo")
        case .sourceDied: Text("Se cortó el video")
        case .network: Text("Sin conexión")
        case .localFile: Text("No se puede abrir la descarga")
        }
    }

    private var message: Text {
        switch failure {
        case .noSources: isEpisode ? Text("Real-Debrid aún no tiene este episodio. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.")
            : Text("Real-Debrid aún no tiene esta película. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.")
        case .noneWorked: Text("Probamos las versiones que hay y ninguna respondió. A veces es momentáneo.")
        case .sourceDied: Text("La versión dejó de responder. Al intentar de nuevo seguimos donde ibas, con otra si hace falta.")
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
    struct Language: Identifiable {
        let id: String; let title: String; let selected: Bool
        /// Un idioma de otra versión: a qué va («↻ 1080p · en Real-Debrid») y si es una suposición («se supone»).
        var detail: String? = nil
        var guessed = false
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
    /// El renglón abierto al aparecer (el botón de subtítulos abre Subtítulos).
    var initiallyOpen: Section? = .subtitles
    @State private var open: Section?
    @State private var opened = false

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
                        ForEach(audio) { a in pill(Text(verbatim: a.title), selected: a.selected) { pickAudio(a.id) } }
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
                        ForEach(languages) { l in pill(Text(verbatim: l.title), selected: l.selected) { pickLanguage(l.id) } }
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
                .id(languages.map { "\($0.id)\($0.selected)" }.joined())
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
        .onAppear { if !opened { opened = true; open = initiallyOpen } }
        .animation(DS.Motion.base(false), value: open)
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
                Text(verbatim: v.title).font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.text)
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
        .accessibilityLabel(Text(verbatim: v.title + ", " + (v.detail ?? "")))
        .accessibilityHint(Text("Abre otra versión del video en el mismo punto"))
    }

    // MARK: renglones
    private func versionRow(_ version: Version) -> some View {
        HStack(spacing: DS.Space.s2) {
            stepButton("chevron.left", label: "Subtítulo anterior", enabled: canStep, action: previous)
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

    private func pill(_ title: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.font(DS.TextRecipe.footnote.font.weight(.semibold)).lineLimit(1).fixedSize()
                .foregroundStyle(selected ? DS.onPrimary : DS.text)
                // Cada cápsula mide lo de su nombre más aire a los lados (antes todas iguales: «Apagados» quedaba justo o se
                // encogía); lo que sobra se reparte.
                .padding(.horizontal, DS.Space.s3)
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
