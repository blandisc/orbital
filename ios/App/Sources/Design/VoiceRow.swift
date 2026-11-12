import SwiftUI
import OrbitalCore

/// El renglón de la voz, la misma pieza en la hoja corta, en el control estirado y en el panel del iPad. Quieto es un botón
/// grande con una pista que va cambiando («Prueba: «pausa»», tocarla la manda) y el «?» de la guía. Al tocar el micrófono
/// crece ahí mismo, una sola vez, al alto de la respuesta: enseña lo que dices, luego qué hizo con sus salidas («Otro»,
/// «Elegir episodio»), las varias coincidencias en carrusel o qué tramo de la conexión falló. Lo de abajo (el volumen, el
/// pad) se recorre con él y se sigue pudiendo tocar.
struct VoiceRow: View {
    @Environment(\.titleName) var titleName
    enum Phase: Equatable { case idle, listening, asking, open }

    struct Actions {
        var mic: () -> Void
        var guide: () -> Void
        var say: (String) -> Void
        var close: () -> Void
        var other: () -> Void
        var episodes: () -> Void
        var choose: (OrbitalRemote.VoiceChoice) -> Void
        var retry: () -> Void
        var checkConnection: () -> Void
    }

    let phase: Phase
    let transcript: String
    let reply: OrbitalRemote.VoiceReply?
    /// La pista de ahora (una de las tres frases del momento) y, después de plegarse, lo último que hizo («✓ …»).
    let hint: String?
    let lastAnswer: String?
    let denied: Bool
    let heardNothing: Bool
    /// Lo que suena en la TV, para el póster de la respuesta y para saber si hay episodios que elegir.
    let now: OrbitalRemote.NowPlaying?
    /// Qué tramo no contestó cuando la orden no llegó (`nil` mientras se prueba o si sí llegó).
    let issue: ConnectionIssue?
    let actions: Actions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var taps = 0

    var body: some View {
        Group {
            // Escuchar, las varias coincidencias y el tramo que falló reservan su alto; una respuesta corta («Prendiendo la
            // tele») mide lo que mide (antes dejaba medio renglón gris vacío abajo).
            if phase == .idle { idle } else { open.frame(minHeight: plainAnswer ? nil : DS.Remote.voiceOpenHeight, alignment: .top) }
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(translucent: true)
        .dsFeedback(.impact(flexibility: .soft), trigger: taps)
        // Lo de adentro se funde en el mismo alto (escuchar → responder); el alto cambia solo al abrir y al plegar.
        .animation(DS.Motion.base(reduceMotion), value: phase)
        .animation(DS.Motion.base(reduceMotion), value: reply)
    }

    // MARK: Quieto

    private var idle: some View {
        HStack(spacing: DS.Space.s3) {
            micButton(listening: false)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Button { tap(actions.mic) } label: { Text("Dile a Orbital").recipe(.cardTitle).frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(.plain)
                subtitle
            }
            guideButton
        }
    }

    @ViewBuilder private var subtitle: some View {
        if denied {
            Text("Permite el micrófono y el dictado en Ajustes").recipe(.caption, color: DS.textMuted).lineLimit(2)
        } else if heardNothing {
            Text("No te escuché. Toca y vuelve a intentar").recipe(.caption, color: DS.textMuted).lineLimit(2)
        } else if let lastAnswer {
            Label { Text(verbatim: lastAnswer) } icon: { Image(systemName: DS.Symbol.done) }.recipe(.caption, color: DS.success).lineLimit(1)
        } else if let hint {
            // La pista: una frase del momento; tocarla la manda tal cual (atajo y lección a la vez).
            Button { tap { actions.say(hint) } } label: {
                Text("Prueba: \(Text(verbatim: "«\(hint)»").foregroundStyle(DS.text).fontWeight(.medium))")
                    .recipe(.caption, color: DS.textMuted).lineLimit(typeSize.isAccessibilitySize ? nil : 1)   // I3: «Prueba: «pau…»; R4: con letra grande, entera
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Mandar «\(hint)»"))
            .accessibilityIdentifier("voice-hint")
            .id(hint)
            .transition(.opacity)
        } else {
            Text("Toca y habla").recipe(.caption, color: DS.textMuted)
        }
    }

    // MARK: Abierto

    /// Abierto con una respuesta sencilla (ni escuchando, ni varias coincidencias, ni la conexión que falló).
    private var plainAnswer: Bool {
        guard phase == .open, let reply else { return false }
        return reply.choices.isEmpty && (reply.ok || issue == nil)
    }

    @ViewBuilder private var open: some View {
        switch phase {
        case .listening, .asking: listening
        default:
            if let reply, !reply.choices.isEmpty { VoiceChoicesCarousel(reply: reply, actions: actions) }
            else if let reply, !reply.ok, let issue { ConnectionTrail(issue: issue, heard: reply.heard, retry: actions.retry, check: actions.checkConnection, close: actions.close) }
            else { answer }
        }
    }

    private var listening: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack {
                Text(phase == .asking ? "Preguntándole a tu Orbital" : "Te escucho").recipe(.eyebrow)
                Spacer(minLength: DS.Space.s2)
                closeButton
            }
            // Las palabras tal cual llegan, sin animarlas (animarlas se siente lento).
            (transcript.isEmpty ? Text("…") : Text(verbatim: transcript)).recipe(.section).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(nil, value: transcript)
            Spacer(minLength: 0)
            HStack(spacing: DS.Space.s3) {
                micButton(listening: true)
                if phase == .asking { DSInlineProgress(text: Text("Un momento")) }
                else { Text("Se detiene sola al callarte").recipe(.caption, color: DS.textMuted) }
            }
        }
    }

    private var answer: some View {
        let ok = reply?.ok == true
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .center, spacing: DS.Space.s3) {
                // Lo que quedó en la TV: su póster; sin póster (prender la tele, el volumen), el ícono de la tele.
                if ok, let now {
                    PosterView(url: now.art, title: titleName(now.title, id: now.metaID, kind: now.kind), aspect: DS.Poster.aspect, whole: true).frame(width: DS.Size.thumbSmall)
                        .transition(.opacity.combined(with: .scale(scale: DS.Remote.revealScale)))
                } else {
                    statusTile(ok: ok)
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    if ok { Label("En la TV", systemImage: DS.Symbol.done).recipe(.eyebrow, color: DS.success) }
                    Text(verbatim: reply?.speech.isEmpty == false ? reply!.speech : "Listo").recipe(.cardTitle).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let heard = reply?.heard, !heard.isEmpty { Text("Entendí: «\(heard)»").recipe(.caption, color: DS.textMuted).lineLimit(2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                micButton(listening: false, small: true)
            }
            // Las salidas solo cuando aplican: «pausa» no trae ninguna; una película no trae «Elegir episodio».
            if ok, let now, !now.live {
                HStack(spacing: DS.Space.s2) {
                    pill("Otro", id: "voice-other", action: actions.other)
                    if now.kind == "series" { pill("Elegir episodio", id: "voice-episodes", action: actions.episodes) }
                }
            }
        }
    }

    /// El ícono de la respuesta sin póster: la tele en verde si llegó, un aviso en ámbar si no.
    private func statusTile(ok: Bool) -> some View {
        let tint = ok ? DS.success : DS.warning
        return Image(systemName: ok ? "tv.and.mediabox" : "exclamationmark.bubble").font(DS.TextRecipe.section.font).foregroundStyle(tint)
            .frame(width: DS.Remote.voiceMic, height: DS.Remote.voiceMic)
            .background(tint.opacity(DS.Opacity.selectedFill), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: Piezas

    private func micButton(listening: Bool, small: Bool = false) -> some View {
        Button { tap(actions.mic) } label: {
            ZStack {
                // El chico (volver a hablar, junto a una respuesta) es secundario: relleno tenue, no la bola del principal.
                Circle().fill(listening ? DS.brandMoon : small ? DS.fillStrong : DS.primary)
                if listening {
                    RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous).fill(DS.onPrimary)
                        .frame(width: DS.Space.s4, height: DS.Space.s4)
                } else {
                    Image(systemName: "mic.fill").font(small ? DS.TextRecipe.footnote.font : DS.TextRecipe.cardTitle.font)
                        .foregroundStyle(small ? DS.text : DS.onPrimary)
                }
            }
            .frame(width: small ? DS.Size.touchTarget : DS.Remote.voiceMic, height: small ? DS.Size.touchTarget : DS.Remote.voiceMic)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listening ? Text("Terminar la orden") : Text("Dile a Orbital"))
        .accessibilityIdentifier(listening ? "voice-stop" : small ? "voice-mic-again" : "voice-mic")
    }

    private var guideButton: some View {
        DSIconButton(symbol: "questionmark", label: "Lo que puedes decir") { tap(actions.guide) }
            .accessibilityIdentifier("remote-voice-guide")
    }

    private var closeButton: some View {
        DSIconButton(symbol: "xmark", label: "Cerrar", size: .regular) { tap(actions.close) }
            .accessibilityIdentifier("voice-close")
    }

    private func pill(_ title: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button { tap(action) } label: { Text(title).font(DS.TextRecipe.label.font).frame(maxWidth: .infinity) }
            .dsSecondaryButton().controlSize(.large)
            .accessibilityIdentifier(id)
    }

    private func tap(_ action: () -> Void) { taps += 1; action() }
}

/// Varias coincidencias, la misma pieza para «pon Dune» (ya puso la más popular: `picked`) y «busca Dune» (nada se puso:
/// para elegir). La principal al centro, en grande; las demás asoman a los lados y se deslizan. Al poner otra solo cambia
/// su letrero: el renglón no cambia de alto.
struct VoiceChoicesCarousel: View {
    let reply: OrbitalRemote.VoiceReply
    let actions: VoiceRow.Actions
    @State private var current: String?
    /// La que está en la TV ahora (la que puso la voz o la que tocaste después).
    @State private var playing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    if reply.picked != nil { Label("En la TV", systemImage: DS.Symbol.done).recipe(.eyebrow, color: DS.success) }
                    else { Text("¿Cuál?").recipe(.cardTitle) }
                    if !reply.heard.isEmpty { Text("Entendí: «\(reply.heard)» · desliza para ver más").recipe(.caption, color: DS.textMuted).lineLimit(1) }
                }
                Spacer(minLength: DS.Space.s2)
                DSIconButton(symbol: "xmark", label: "Cerrar", size: .regular) { actions.close() }
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: DS.Space.s3) {
                    ForEach(reply.choices) { choice in card(choice).containerRelativeFrame(.horizontal) { width, _ in width * DS.Remote.choiceCardShare } }   // ds-exception: su carrusel, dentro del control
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current, anchor: .center)
            .contentMargins(.horizontal, DS.Space.s5, for: .scrollContent)
            .scrollIndicators(.hidden)
            .padding(.horizontal, -DS.Space.s3)   // el carrusel llega a las orillas del renglón: así asoman las de los lados
            PageDots(count: reply.choices.count, index: reply.choices.firstIndex { $0.id == current } ?? 0).frame(maxWidth: .infinity)
        }
        .onAppear {
            let main = reply.choices.first { $0.metaID == reply.picked } ?? reply.choices.first
            current = main?.id
            playing = reply.picked.flatMap { picked in reply.choices.first { $0.metaID == picked }?.id }
        }
    }

    private func card(_ choice: OrbitalRemote.VoiceChoice) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            PosterView(url: choice.image, title: choice.title, aspect: DS.Poster.aspect).frame(width: DS.Remote.choicePoster)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: choice.title).recipe(.cardTitle).lineLimit(2)
                if !choice.subtitle.isEmpty { Text(verbatim: choice.subtitle).recipe(.footnote, color: DS.textMuted).lineLimit(1) }
                Spacer(minLength: DS.Space.s2)
                if playing == choice.id {
                    // Lo que pasa ahora, en turquesa y sin cápsula teñida (2 nov 2026: el turquesa no pinta fondos).
                    Text("Poniéndose").font(DS.TextRecipe.label.font).foregroundStyle(DS.brandMoon)
                        .padding(.horizontal, DS.Space.s3).frame(minHeight: DS.Size.touchTarget)
                } else {
                    Button { playing = choice.id; actions.choose(choice) } label: {
                        Label(reply.picked == nil ? "Poner" : "Poner esta", systemImage: "play.fill").font(DS.TextRecipe.label.font)
                    }
                    .dsPrimaryButton(size: .large)
                    .accessibilityIdentifier("voice-choice-play")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Space.s3)
        .dsCard(fill: DS.fillStrong)
        .id(choice.id)
        .accessibilityElement(children: .contain)
    }
}

/// La orden no llegó: qué tramo falló, iPhone → túnel → tu Orbital, con el arreglo de ese tramo.
struct ConnectionTrail: View {
    let issue: ConnectionIssue
    let heard: String
    let retry: () -> Void
    let check: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("No llegó a tu Orbital").recipe(.cardTitle)
                    if !heard.isEmpty { Text("Entendí: «\(heard)» · no se mandó").recipe(.caption, color: DS.textMuted).lineLimit(1) }
                }
                Spacer(minLength: DS.Space.s2)
                DSIconButton(symbol: "xmark", label: "Cerrar", size: .regular, action: close)
            }
            HStack(spacing: DS.Space.s2) {
                node("iphone", Text("Tu iPhone"), ok: issue != .noInternet)
                link(failed: issue == .noInternet || issue == .tunnelDown)
                node("network", Text("Internet"), ok: issue == .orbitalDown || issue == .tokenChanged)
                link(failed: issue == .orbitalDown || issue == .tokenChanged)
                node("tv.and.mediabox", Text("Orbital"), ok: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(message)
            message.recipe(.footnote, color: DS.text).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s2) {
                Button(action: retry) { Text("Probar otra vez").font(DS.TextRecipe.label.font).frame(maxWidth: .infinity) }
                    .dsPrimaryButton(size: .large).accessibilityIdentifier("voice-retry")
                Button(action: check) { Text("Probar la conexión").font(DS.TextRecipe.label.font).frame(maxWidth: .infinity) }
                    .dsSecondaryButton().controlSize(.large).accessibilityIdentifier("voice-check-connection")
            }
        }
    }

    private var message: Text {
        switch issue {
        case .noInternet: Text("Tu iPhone no tiene internet. Conéctate a una red y prueba otra vez.")
        case .tunnelDown: Text("Tu TV no contesta: puede estar dormida. «Prende la tele» la despierta.")
        case .orbitalDown: Text("Tu TV contesta, pero Orbital no: puede estar cerrada o reiniciándose. Espera un momento.")
        case .tokenChanged: Text("Tu Orbital ya no reconoce este iPhone. Vuelve a conectarlo en Ajustes › Usar con tu Orbital.")
        }
    }

    private func node(_ symbol: String, _ title: Text, ok: Bool) -> some View {
        VStack(spacing: DS.Space.s1) {
            Image(systemName: symbol).font(DS.TextRecipe.footnote.font).foregroundStyle(ok ? DS.success : DS.textMuted)
                .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                .background((ok ? DS.success.opacity(DS.Opacity.selectedFill) : DS.fill), in: Circle())
            title.recipe(.caption, color: DS.textMuted).lineLimit(1)
        }
    }

    private func link(failed: Bool) -> some View {
        VStack(spacing: DS.Space.s1) {
            Rectangle().fill(failed ? DS.danger : DS.success).frame(height: DS.Stroke.regular)
            if failed { Image(systemName: "xmark").font(DS.TextRecipe.badge.font).foregroundStyle(DS.danger) }   // ds-exception: la ✕ marca el tramo que falló (no es cerrar)
        }
        .frame(maxWidth: .infinity)
    }
}
