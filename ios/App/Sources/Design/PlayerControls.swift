import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas del reproductor: los botones con nombre, «Audio y subtítulos» (`SubtitleDock`) y sus partes.

/// Los controles del reproductor: botones redondos, el aviso del candado, «Siguiente», fichas del panel, el toast, play/pausa, la barra de avance y los renglones de menú.

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

/// Bloqueado: una cápsula chica arriba. Al bloquear solo dice «Pantalla bloqueada»; tras un toque, trae «Desbloquear».
/// Encogida (`collapsed`) queda el círculo del candado; `risen` la sube y la desvanece (con «Reducir movimiento», solo se desvanece).
struct PlayerLockNotice: View {
    var showsUnlock: Bool
    var collapsed: Bool
    var risen: Bool
    let unlock: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "lock.fill").font(DS.TextRecipe.footnote.font.weight(.bold))
            if !collapsed {
                Text("Pantalla bloqueada").font(DS.TextRecipe.footnote.font.weight(.semibold))
                if showsUnlock {
                    Button(action: unlock) {
                        Text("Desbloquear").font(DS.TextRecipe.footnote.font.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent).controlSize(.small).tint(DS.primary).foregroundStyle(DS.onPrimary)
                    .accessibilityIdentifier("player-unlock")
                }
            }
        }
        .foregroundStyle(DS.text)
        .padding(.horizontal, collapsed ? DS.Space.s2 : DS.Space.s3)
        .padding(.vertical, DS.Space.s2)
        .frame(width: collapsed ? DS.PlayerPanel.lockNoticeIcon : nil, height: collapsed ? DS.PlayerPanel.lockNoticeIcon : nil)
        .glassEffect(.regular, in: Capsule())
        .offset(y: risen && !reduceMotion ? -DS.PlayerPanel.lockNoticeRise : 0)
        .opacity(risen ? 0 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player-lock-notice")
        .allowsHitTesting(showsUnlock && !collapsed && !risen)
    }
}

/// «Siguiente episodio»: la imagen del episodio (si la hay), cuál es, «Ver ahora» con la cuenta atrás en un anillo y «Ahora no».
struct UpNextCard: View {
    let card: UpNext
    /// Cuántos segundos dura la cuenta completa (para el anillo).
    let total: Double
    let watchNow: () -> Void
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
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
                .animation(DS.Motion.base(reduceMotion), value: card.secondsLeft)   // respeta «Reducir movimiento»
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
        // Más aire por dentro (antes el texto y «Cambiar» casi tocaban el borde).
        .padding(.leading, DS.Space.s4).padding(.trailing, action == nil ? DS.Space.s4 : DS.Space.s3).padding(.vertical, DS.Space.s3)
        .glassEffect(.regular, in: Capsule())
        .overlay { if prominent { Capsule().strokeBorder(Self.color(tone).opacity(DS.Toast.toneStroke), lineWidth: DS.Toast.strokeWidth) } }
        .contentShape(Capsule())
        .onTapGesture(perform: dismiss)
        // Deslizar hacia abajo lo quita (el que te necesita no se va solo).
        .gesture(DragGesture(minimumDistance: DS.Toast.swipe).onEnded { if $0.translation.height > 0 { dismiss() } })
        .frame(maxWidth: DS.Toast.maxWidth)
        .padding(.horizontal, DS.Space.gutter)   // el mismo margen que la barra de arriba del reproductor y que las pantallas
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
    /// Cargando (abrir, buscar versión, volver a la app, llenar el búfer): la animación de carga vive dentro del botón, en su lugar.
    var loading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                // La luna recorre la orilla del botón (antes un anillo más chico adentro: se veía como un disco gris raro).
                if loading { DSLoader(size: DS.PlayerPanel.playButton - DS.Loader.buttonInset * 2, showsTrack: false) }
                else {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: DS.PlayerPanel.playGlyph, weight: .bold))   // ds-exception: el glifo del botón grande se mide con el botón, no con Dynamic Type
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(DS.text)
                }
            }
            .frame(width: DS.PlayerPanel.playButton, height: DS.PlayerPanel.playButton)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loading ? Text("Cargando") : playing ? Text("Pausa") : Text("Continuar"))
    }
}

/// La barra de avance (la misma en vertical y en horizontal), a todo lo ancho: delgada con un punto chico mientras miras, gruesa
/// mientras la arrastras, con una burbuja encima que dice a qué minuto vas y cuánto saltas. Dos rayitas tenues marcan dónde
/// termina la intro y dónde empiezan los créditos (desde ahí el episodio cuenta como visto); al arrastrar, los tramos se aclaran.
struct PlayerScrubBar: View {
    let value: Double
    let duration: Double
    /// Los tramos marcados (intro, resumen, créditos), en segundos.
    var marks: [ClosedRange<Double>] = []
    /// Las rayitas fijas: el fin de la intro y el inicio de los créditos (segundos).
    var ticks: [Double] = []
    /// Cómo se dice un minuto («11:16»).
    var clock: (Double) -> String = { _ in "" }
    /// Buscando arrastrando sobre el video (no sobre la barra): desde dónde. La barra se ve igual que al arrastrarla, con la misma
    /// burbuja en el mismo lugar.
    var previewFrom: Double? = nil
    let change: (Double) -> Void
    let editing: (Bool) -> Void
    @State private var dragging = false
    @State private var startValue: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (t: Double) in CGFloat(min(max(t / max(duration, 1), 0), 1)) * width }
            let active = dragging || previewFrom != nil
            let track = active ? DS.PlayerPanel.scrubTrackActive : DS.PlayerPanel.scrubTrack
            ZStack(alignment: .leading) {
                Capsule().fill(DS.track).frame(height: track)
                ForEach(Array((active ? marks : []).enumerated()), id: \.offset) { _, mark in
                    Rectangle().fill(DS.textFaint)
                        .frame(width: max(0, x(mark.upperBound) - x(mark.lowerBound)), height: track)
                        .offset(x: x(mark.lowerBound))
                }
                Capsule().fill(DS.brandMoon).frame(width: max(track, x(value)), height: track)
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                    Rectangle().fill(DS.textMuted)
                        .frame(width: DS.PlayerPanel.scrubTickWidth, height: track + DS.PlayerPanel.scrubTickReach * 2)
                        .offset(x: x(tick) - DS.PlayerPanel.scrubTickWidth / 2)
                }
                // El punto: dónde vas. Chico mientras miras, más grande mientras lo arrastras.
                let knob = active ? DS.PlayerPanel.scrubKnobActive : DS.PlayerPanel.scrubKnob
                Circle().fill(DS.text).frame(width: knob, height: knob).offset(x: x(value) - knob / 2)
                    .shadow(DS.Elevation.low)
                // Arrastrando: la burbuja arriba de la barra, centrada sobre el dedo (sin salirse de la barra ni tapar los tiempos).
                if active {
                    let delta = value - (previewFrom ?? startValue)
                    DSSeekBubble(time: clock(value), delta: (delta >= 0 ? "+" : "−") + clock(abs(delta)))
                        .fixedSize()
                        .position(x: min(max(x(value), DS.Gesture.seekBubbleSideMargin), width - DS.Gesture.seekBubbleSideMargin),
                                  y: DS.PlayerPanel.scrubHit / 2 - DS.PlayerPanel.scrubBubbleLift)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(DS.Motion.base(reduceMotion), value: active)
            .frame(width: width, height: DS.PlayerPanel.scrubHit)
            // Ocupa 32 pt (no se mueve nada), pero se toca en 44: la zona sobresale lo mismo arriba y abajo.
            .contentShape(Rectangle().size(width: width, height: DS.Size.touchTarget)
                .offset(y: (DS.PlayerPanel.scrubHit - DS.Size.touchTarget) / 2))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !dragging { startValue = value; dragging = true; editing(true) }
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
