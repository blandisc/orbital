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

/// El botón de subtítulos de los controles del reproductor: un toque pone la versión siguiente (sin pausar ni abrir nada),
/// mantenerlo abre la lista de Subtítulos. Mientras baja una versión de internet, enseña que carga.
struct SubtitleCycleButton: View {
    let on: Bool
    let loading: Bool
    let next: () -> Void
    let openList: () -> Void

    var body: some View {
        ZStack {
            if loading { ProgressView().tint(DS.text) }
            else { Image(systemName: on ? "captions.bubble.fill" : "captions.bubble").font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text) }
        }
        .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
        .glassEffect(.regular.interactive(), in: Circle())
        .contentShape(Circle())
        .onTapGesture(perform: next)
        .onLongPressGesture(minimumDuration: DS.Timing.longPressDelay, perform: openList)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Siguiente subtítulo"))
        .accessibilityHint(Text("Mantén presionado para ver la lista de subtítulos"))
        .accessibilityAction(.default, next)
        .accessibilityAction(named: Text("Lista de subtítulos"), openList)
    }
}

/// «Más idiomas…»: todos los idiomas, con buscador.
struct LanguageSearchList: View {
    let codes: [String]
    let name: (String) -> String
    let pick: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let all = codes.map { ($0, name($0)) }.sorted { $0.1.localizedCompare($1.1) == .orderedAscending }
        let shown = query.isEmpty ? all : all.filter { $0.1.localizedCaseInsensitiveContains(query) || $0.0.hasPrefix(query.lowercased()) }
        NavigationStack {
            List(shown, id: \.0) { code, title in
                Button { pick(code); dismiss() } label: { Text(verbatim: title).foregroundStyle(DS.text) }
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
