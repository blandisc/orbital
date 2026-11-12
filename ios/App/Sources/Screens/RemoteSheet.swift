import SwiftUI
import OrbitalCore
import OrbitalModels

/// El control de tu Orbital, en una hoja con dos alturas (como el reproductor de Música): corta, el control de lo que se
/// ve en la TV (pausa, ±10, siguiente…); estirada hacia arriba, además el control completo de la consola: el pad
/// (`TouchPad`), sus teclas (`RemoteKey`) y «Escribir» cuando la TV tiene dónde.
struct RemoteSheet: View {
    @Environment(\.titleName) var titleName
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var tvNow: ModelObserver<TVNowModel>
    @Binding var large: Bool
    let onContinueHere: (OrbitalRemote.NowPlaying) -> Void
    /// En un panel fijo a la derecha (ventana ancha: iPad horizontal, Mac) en vez de una hoja: con título y «Cerrar», siempre
    /// completo. Sin esto, la hoja de siempre (el iPhone no cambia).
    var close: (() -> Void)? = nil
    @State private var compactHeight: CGFloat = DS.Remote.padHeight
    /// El alto del control completo, medido: la hoja estirada mide eso (sin hueco abajo) y, como no llega a la altura
    /// completa de la pantalla, iOS la deja de vidrio translúcido como la corta (a la altura completa la vuelve opaca).
    @State private var fullHeight: CGFloat = DS.Remote.padHeight * 4
    /// Lo que mide el contenido ahora mismo; la hoja lo alcanza un instante después (`settle`), cuando el contenido dejó de
    /// cambiar, y en una sola animación. Antes tomaba cada medida al vuelo: al pasar del menú de la TV al reproductor el
    /// contenido cambiaba en dos pasos y la hoja bajaba y subía; al ocultar los sustos brincaba.
    @State private var measuredCompact: CGFloat?
    @State private var measuredFull: CGFloat?
    @State private var settling: Task<Void, Never>?
    /// La primera medida va directa (la hoja abre ya de su alto); la espera es solo para lo que cambia después.
    @State private var measuredOnce = false
    /// El alto del panel del iPad (`panel`): su contenido mide al menos eso y el control llega al borde de abajo.
    @State var panelHeight: CGFloat = 0
    @State private var text = ""
    /// Lo que ya tiene la TV de lo que escribiste (para mandar solo la diferencia).
    @State private var sentText = ""
    @State private var speech = SpeechInput()
    @State private var reply: OrbitalRemote.VoiceReply?
    @State private var asking = false
    /// La pregunta en camino a tu Orbital: la X y el botón de detener la cortan (sin conexión tardaba hasta 20 s en rendirse y
    /// el renglón no dejaba salir).
    @State private var askTask: Task<Void, Never>?
    @State private var showsGuide = false
    /// La respuesta abierta en el renglón de la voz (se pliega sola: `DS.Remote.replyStays`).
    @State private var replyOpen = false
    /// Lo último que hizo, como pista un rato después de plegarse («✓ Poniendo The Office · T2 E5»).
    @State private var lastAnswer: String?
    /// Lo último que dijiste, para «Probar otra vez».
    @State private var lastSaid: String?
    /// Qué tramo de la conexión falló cuando la orden no llegó.
    @State private var issue: ConnectionIssue?
    @State private var collapsing: Task<Void, Never>?
    @State private var pickingEpisode = false
    /// Cuál de las tres frases del momento sale de pista: otra cada vez que abres el control.
    @State private var hintIndex = Int.random(in: 0..<3)
    @State private var showsScares = false
    /// En el reproductor o la TV en vivo, el pad va plegado (lo de arriba es lo que se usa); se abre a mano.
    @State private var showsPad = false
    /// El póster, el nombre y la voz son los mismos en las dos alturas: viajan de un lugar al otro (`remoteMorph`).
    @Namespace private var morph
    @Environment(AppEnvironment.self) var env

    var body: some View {
        let model = tvNow.model
        Group {
            // iPad y Mac (CT2, 11 nov 2026): en el panel de la derecha, arriba lo que suena y abajo el control (`panel`).
            if let close { panel(model, close: close) } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Remote.blockGap) {   // ds-exception: la hoja del control no lleva título; sus bloques van a su ritmo
                        header(model)
                            // El alto de la hoja corta: el de la tarjeta completa (estirada se vuelve compacta y no cuenta).
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                if !large { measuredCompact = min(height + DS.Space.sheetTop + DS.Space.s10, WindowMetrics.size.height * DS.Remote.maxShareFitted); settle() }
                            }
                        // Lo completo se funde en su lugar (la voz, que ya estaba, se desliza a su sitio: `remoteMorph`). Antes subía
                        // desde abajo mientras lo de arriba cambiaba de forma, y parecía que todo desaparecía y volvía.
                        if large { full(model).transition(.opacity) }
                        else {
                            Label("Estira hacia arriba para el control completo", systemImage: "chevron.compact.up")
                                .recipe(.caption, color: DS.textFaint).frame(maxWidth: .infinity)
                        }
                    }
                    .dsSheetContent()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if large { measuredFull = min($0 + DS.Remote.sheetAllowance, WindowMetrics.size.height * DS.Remote.maxShareFitted); settle() } }
                }
                .scrollDisabled(!large && compactHeight < WindowMetrics.size.height * DS.Remote.maxShareFitted)   // corta y sin caber (letra grande): se desliza
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationContentInteraction(.resizes)   // deslizar mueve la hoja primero y luego el contenido (antes se peleaban)
        // Sin nada en la TV la hoja corta no tiene qué enseñar (quedaba «Tu Orbital» y un hueco, y bajarla se atoraba ahí):
        // solo la altura completa, y bajarla la cierra.
        .presentationDetents(model.now == nil ? [.height(fullHeight)] : [.height(compactHeight), .height(fullHeight)], selection: Binding(
            get: { large || model.now == nil ? .height(fullHeight) : .height(compactHeight) },
            set: { large = $0 == .height(fullHeight) }))
        .onChange(of: model.now == nil) { _, idle in if idle { large = true } }
        .presentationDragIndicator(.visible)
        .fittedFormSizing(idealHeight: large ? fullHeight : compactHeight)   // iPad y Mac: tarjeta del alto del control (ahí abre siempre completo: `MainTabs`)
        .presentationBackgroundInteraction(.disabled)
        // Vidrio en las dos alturas (la estirada no llega a la altura completa, que iOS volvería opaca).
        // El vidrio nativo se vuelve opaco al estirar la hoja; el control lo pide en las dos alturas.
        .presentationBackground { Rectangle().fill(.clear).glassEffect(.regular, in: Rectangle()) }   // ds-exception: vidrio en las dos alturas del control
        .animation(DS.Motion.smooth(reduceMotion), value: large)
        .animation(DS.Motion.smooth(reduceMotion), value: showsScares)
        // El renglón de la voz crece y se pliega con lo de abajo en el mismo movimiento (nada brinca después).
        .animation(DS.Motion.smooth(reduceMotion), value: voicePhase)
        .onDisappear { speech.cancel(); model.setRemoteOpen(false) }
        .onAppear { model.setRemoteOpen(true) }   // con el control abierto, la TV se consulta más seguido
        .task(id: "\(model.context)·\(model.now?.metaID ?? "")·\(model.now?.live == true)") { await model.loadHints() }   // las frases del momento
        .task(id: model.now?.metaID) { await model.loadScares() }   // el mapa de sustos de la película que suena
        .background { if let scares = model.scares, let now = model.now { ScareWatcher(now: now, fetchedAt: model.fetchedAt, scares: scares) } }
        // Los botones de volumen del iPhone suben y bajan la TV mientras el control está abierto (como el del Apple TV).
        .background { if model.isConfigured { HardwareVolumeButtons { up in Task { await model.changeVolume(by: up ? 5 : -5) } } } }
        #if DEBUG
        .task { if Demo.isOn, Demo.open == "voice-guide" { showsGuide = true }; if Demo.isOn, Demo.open == "remote-pad" { showsPad = true } }   // -demo-open voice-guide: la guía, para capturas
        #endif
        .sheet(isPresented: $showsGuide) {
            NavigationStack {
                VoiceGuideView(hints: model.hints, nowTitle: model.now?.title) { phrase in
                    showsGuide = false
                    say(model, phrase)
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { showsGuide = false } } }
            }
        }
        .sheet(isPresented: $pickingEpisode) {
            if let now = model.now, let seriesID = now.metaID {
                EpisodePickerSheet(title: titleName(now.title, id: now.metaID, kind: now.kind), currentVideoID: now.videoID,
                                   load: { await VoiceAssistant(services: env.services, tvNow: model).episodes(seriesID: seriesID) },
                                   play: { season, episode in
                                       answer(model) { await $0.playEpisode(seriesID: seriesID, episode: episode, season: season.season, title: now.title) }
                                   })
            }
        }
    }

    /// La hoja alcanza lo que mide su contenido cuando este deja de cambiar, con la misma animación que lo de adentro.
    private func settle() {
        settling?.cancel()
        if !measuredOnce {
            measuredOnce = true
            if let measuredCompact { compactHeight = measuredCompact }
            if let measuredFull { fullHeight = measuredFull }
            return
        }
        settling = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(DS.Remote.heightSettle * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.smooth(reduceMotion)) {
                if let measuredCompact { compactHeight = measuredCompact }
                if let measuredFull { fullHeight = measuredFull }
            }
        }
    }

    /// La voz: lo que dices lo atiende el iPhone (descargar, seguir aquí, las teclas) o tu Orbital (`VoiceAssistant`); la
    /// respuesta se enseña y se dice en voz alta, en el idioma de la app.
    private func listen(_ model: TVNowModel) {
        if speech.listening { speech.finish(); return }
        if asking { stopAsking(); return }   // el botón de detener mientras se espera la respuesta
        let language = env.services.appSettings.uiLanguage
        // El nombre de lo que se ve en la TV, para que el dictado lo escriba bien («descarga Shōgun»).
        let hints = ["Orbital"] + [model.now?.title, model.now?.channel].compactMap { $0 }
        Task {
            await speech.start(language: language, hints: hints) { said in lastSaid = said; answer(model) { await $0.handle(said) } }
        }
    }

    /// Lo que contestó (a lo que dijiste o a la opción que tocaste): se enseña, se dice y, si es «sigue aquí», se hace.
    private func answer(_ model: TVNowModel, _ ask: @escaping @MainActor (VoiceAssistant) async -> VoiceAssistant.Outcome) {
        guard !asking else { return }
        let language = env.services.appSettings.uiLanguage
        collapsing?.cancel(); issue = nil; lastAnswer = nil
        asking = true; reply = nil
        askTask = Task {
            let outcome = await ask(VoiceAssistant(services: env.services, tvNow: model))
            guard !Task.isCancelled else { return }   // la cancelaste: no se enseña ni se dice nada
            asking = false; askTask = nil
            var shown = outcome.reply
            shown.speech = Strings.message(outcome.speech, language: language)
            // Una tecla («pausa» la atiende el iPhone) no tiene nada que enseñar: el renglón no se abre.
            if shown.speech.isEmpty && shown.choices.isEmpty && shown.ok { reply = nil; return }
            reply = shown; replyOpen = true
            speech.speak(shown.speech, language: language)
            if outcome.continueHere, let now = model.now { onContinueHere(now) }
            if outcome.guide { showsGuide = true }
            // No llegó: qué tramo falló (iPhone → túnel → tu Orbital).
            if !shown.ok {
                let found = await model.diagnoseConnection()
                if replyOpen { issue = found }
            }
            // Con varias, se queda abierto hasta que elijas o lo cierres; lo demás se pliega solo.
            if shown.choices.isEmpty && shown.ok { collapseLater() }
        }
    }

    /// Dejar de esperar la respuesta (la X o el botón de detener): el renglón vuelve a quieto al momento.
    private func stopAsking() {
        askTask?.cancel(); askTask = nil
        asking = false; reply = nil; issue = nil
    }

    /// Mandar una frase tal cual (la pista, la guía, «otro»), como si la hubieras dicho.
    func say(_ model: TVNowModel, _ phrase: String) {
        lastSaid = phrase
        answer(model) { await $0.handle(phrase) }
    }

    /// El renglón se pliega a los pocos segundos y deja la respuesta como pista otro rato.
    private func collapseLater() {
        collapsing?.cancel()
        collapsing = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(DS.Remote.replyStays * 1_000_000_000))
            guard !Task.isCancelled else { return }
            collapse()
        }
    }

    private func collapse() {
        collapsing?.cancel()
        guard replyOpen else { return }
        let answered = reply?.ok == true && reply?.choices.isEmpty == true ? reply?.speech : nil
        replyOpen = false; issue = nil
        lastAnswer = answered.flatMap { $0.isEmpty ? nil : $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        guard lastAnswer != nil else { return }
        collapsing = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(DS.Remote.answerHintStays * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.base(reduceMotion)) { lastAnswer = nil }
        }
    }

    /// En qué está el renglón de la voz.
    private var voicePhase: VoiceRow.Phase {
        if speech.listening { return .listening }
        if asking { return .asking }
        return replyOpen && reply != nil ? .open : .idle
    }

    /// Una tecla del mando: su nombre es el de la leyenda de la TV para esa tecla si la consola la manda (lo que dice el pie de
    /// la pantalla); si no, el de siempre. Que no salga en el pie no quiere decir que no haga nada (en Inicio A, X y Y están en
    /// los botones del destacado), así que nunca se atenúa.
    private func key(_ model: TVNowModel, _ symbol: String, _ legendKey: String?, _ fallback: Text,
                     _ action: OrbitalRemote.InputAction, hold: OrbitalRemote.InputAction? = nil) -> some View {
        let named = legendKey.flatMap { model.legend[$0] }
        return RemoteKey(symbol: symbol, title: named.map { Text(verbatim: $0) } ?? fallback,
                         longPress: hold.map { held in { Task { await model.press(held) } } }) {
            collapse()
            Task { await model.press(action) }
        }
        .accessibilityIdentifier("remote-\(action.rawValue)")   // fijo aunque el nombre cambie con la leyenda
    }

    /// Lo que se ve en la TV (el control de siempre) o, si nada se reproduce, solo el nombre de tu Orbital.
    @ViewBuilder private func header(_ model: TVNowModel) -> some View {
        if large, let now = model.now {
            // Estirada: lo que se ve en la TV en un renglón (póster, nombre y pausa); el resto del alto es para el control.
            HStack(spacing: DS.Space.s3) {
                PosterView(url: now.art, title: titleName(now.title, id: now.metaID, kind: now.kind), aspect: DS.Poster.aspect, whole: true).frame(width: DS.Size.thumbSmall)
                    .remoteMorph("poster", in: morph)
                VStack(alignment: .leading, spacing: 0) {
                    Text(now.live ? (now.channel ?? now.title) : now.title).recipe(.cardTitle).lineLimit(1)
                        .remoteMorph("title", in: morph)
                    Text(now.live ? "En la TV · En vivo" : "En la TV").recipe(.footnote, color: now.live ? DS.live : DS.textMuted).lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                if model.context == .player || model.context == .live {
                    // Reproduciendo o en vivo (la pausa ya está en sus teclas): el pad, para moverte por la TV cuando quieras.
                    DSIconButton(symbol: showsPad ? "play.rectangle" : "hand.point.up.left", label: showsPad ? (model.context == .live ? LocalizedStringKey("Volver a los canales") : LocalizedStringKey("Volver al reproductor")) : LocalizedStringKey("Moverte por la TV"),
                                 prominent: !showsPad) {
                        withAnimation(DS.Motion.smooth(reduceMotion)) { showsPad.toggle() }
                    }
                    .accessibilityIdentifier("remote-pad-button")
                } else if !now.live {
                    DSIconButton(symbol: now.paused ? "play.fill" : "pause.fill", label: now.paused ? "Continuar" : "Pausa", prominent: true) {
                        Task { await model.control("toggle") }
                    }
                }
            }
            .transition(.opacity)   // lo que no viaja (la pausa, «En la TV») se funde en su lugar
        } else if let now = model.now {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                NowPlayingCard(now: now, fetchedAt: model.fetchedAt, busy: model.busy,
                               onAction: { action, delta in Task { await model.control(action, delta: delta) } },
                               onContinueHere: { onContinueHere(now) }, framed: false, scares: model.scares ?? [], morph: morph)
                // La voz, a la vista en la hoja corta (antes solo al estirarla).
                voice(model).remoteMorph("voice", in: morph)
                // Una película con mapa de sustos: un toque lo abre aquí mismo (la línea de tiempo, el siguiente y el aviso).
                if let scares = model.scares {
                    if showsScares { ScarePanel(now: now, fetchedAt: model.fetchedAt, scares: scares).transition(Self.reveal) }
                    Button { withAnimation(DS.Motion.smooth(reduceMotion)) { showsScares.toggle() } } label: {
                        Label(showsScares ? "Ocultar los sustos" : "Mapa de sustos · \(scares.count)", systemImage: showsScares ? "chevron.up" : "bolt.heart")
                            .recipe(.label, color: DS.text)
                    }
                    .dsSecondaryButton().controlSize(.large).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("remote-scares")
                }
            }
            .transition(.opacity)
        } else {
            RemoteStatusCard(tvNow: tvNow)
        }
    }

    /// El control completo, según lo que hay al frente en la TV:
    /// - **Reproduciendo**: la línea de tiempo (con sus sustos), ±10, pausa, siguiente, subtítulos y audio; el pad plegado.
    /// - **En vivo**: canal anterior y siguiente; el pad plegado.
    /// - **Escribiendo** (la búsqueda o la cuenta de la TV): el campo primero, con el teclado; luego el pad.
    /// - **Navegando**: el pad, las secciones y las teclas con lo que hace cada una en esa pantalla.
    /// Arriba siempre la voz; el volumen en todas.
    @ViewBuilder private func full(_ model: TVNowModel) -> some View {
        VStack(spacing: DS.Remote.groupGap) {
            if model.remoteOutdated { DSNotice(text: "Actualiza tu Orbital para usar el control completo.", tone: .warn) }
            voice(model).remoteMorph("voice", in: morph)
            switch model.context {
            // Reproduciendo o en vivo, el pad no se suma abajo (no cabía y repetía pausa, ±10, volumen, pistas y salir):
            // reemplaza lo de arriba cuando hace falta moverse por un panel de la TV (episodios, fuentes, la guía).
            case .player:
                deckOrPad(model) {
                    if let now = model.now { playerDeck(model, now) }
                    volume(model)
                }
            case .live:
                deckOrPad(model) {
                    liveDeck(model)
                    volume(model)
                }
            case .typing:
                VStack(spacing: DS.Remote.groupGap) {
                    typing(model, autoFocus: true)
                    navigation(model)
                    volume(model)
                }
                .transition(Self.reveal)
            case .browse:
                VStack(spacing: DS.Remote.groupGap) {
                    volume(model)
                    navigation(model)
                    typing(model, autoFocus: model.textField == true)
                }
                .transition(Self.reveal)
            }
        }
        // Lo de adentro cambia en la misma hoja: lo nuevo surge con un fundido y crece un poco desde arriba (`reveal`).
        .animation(DS.Motion.smooth(reduceMotion), value: model.context)
        .animation(DS.Motion.smooth(reduceMotion), value: showsPad)
        .animation(DS.Motion.smooth(reduceMotion), value: model.now == nil)
        .onChange(of: model.context) { _, _ in showsPad = false }   // otra pantalla en la TV: vuelve a lo suyo
    }

    /// Reproduciendo o en vivo: los botones y el pad ocupan el mismo lugar, del mismo alto, así la hoja no cambia de tamaño
    /// y solo se reacomoda lo de adentro: los botones se apagan y se encogen hacia arriba mientras el pad crece desde ahí
    /// (y al revés). Antes uno se iba, el otro llegaba y la hoja brincaba de alto un instante después.
    private func deckOrPad<Deck: View>(_ model: TVNowModel, @ViewBuilder deck: () -> Deck) -> some View {
        VStack(spacing: DS.Remote.groupGap) { deck() }
            .frame(minHeight: DS.Remote.padModeHeight, alignment: .top)
            .opacity(showsPad ? 0 : 1)
            .scaleEffect(showsPad ? DS.Remote.morphScale : 1, anchor: .top)
            .blur(radius: showsPad && !reduceMotion ? DS.Remote.morphBlur : 0)
            .allowsHitTesting(!showsPad)
            .accessibilityHidden(showsPad)
            .overlay(alignment: .top) {
                if showsPad {
                    VStack(spacing: DS.Remote.groupGap) { padMode(model) }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: DS.Remote.morphScale, anchor: .top)))
                }
            }
    }

    /// Cómo surge lo que cambia dentro del control: un fundido y un leve crecimiento desde arriba (y se va con un fundido).
    static let reveal = AnyTransition.asymmetric(insertion: .opacity.combined(with: .scale(scale: DS.Remote.revealScale, anchor: .top)),
                                                 removal: .opacity)

    func voice(_ model: TVNowModel) -> some View {
        // La voz, como Alexa: lo mismo que «Oye Siri, dile a Orbital…». La misma pieza en la hoja corta y estirada.
        var hint = model.hints.isEmpty ? nil : model.hints[hintIndex % model.hints.count]
        #if DEBUG
        if Demo.isOn, let said = Demo.voice { hint = said }   // -demo-voice "pon dune": esa pista, para tocarla en las pruebas
        #endif
        return VoiceRow(phase: voicePhase, transcript: speech.transcript, reply: reply,
                        hint: hint, lastAnswer: lastAnswer,
                        denied: speech.denied, heardNothing: speech.heardNothing, now: model.now, issue: issue,
                        actions: .init(
                            mic: { if voicePhase == .open { collapse() }; listen(model) },
                            guide: { showsGuide = true },
                            say: { say(model, $0) },
                            close: { if speech.listening { speech.cancel() }; if asking { stopAsking() }; collapse(); if voicePhase != .idle { replyOpen = false } },
                            other: { say(model, "otro") },
                            episodes: { pickingEpisode = true },
                            // Otra de las varias: se pone en la TV y solo cambia su letrero (el carrusel se queda).
                            choose: { choice in
                                Task {
                                    _ = await VoiceAssistant(services: env.services, tvNow: model).choose(choice)
                                    collapseLater()
                                }
                            },
                            retry: { if let lastSaid { say(model, lastSaid) } },
                            checkConnection: { Task { issue = nil; issue = await model.diagnoseConnection() } }))
    }

    @ViewBuilder func volume(_ model: TVNowModel) -> some View {
        // El volumen de la TV: − · barra · +, y silencio; con un video, + y − en el orden del mando (V5-B).
        VolumeControl(volume: model.volume,
                      down: { Task { await model.changeVolume(by: -5) } }, up: { Task { await model.changeVolume(by: 5) } },
                      mute: { Task { await model.toggleMute() } })
            .dsFeedback(.impact(weight: .medium), trigger: model.volumeBrakes)   // el + se frena en 100 (V5-B)
        if model.extraOnlyForVideos { DSNotice(text: "El Extra es solo para videos.") }   // V6-A
        if model.volumeOutdated { DSNotice(text: "Actualiza tu Orbital para cambiar el volumen desde aquí.", tone: .warn) }
    }

    /// Reproduciendo: la línea de tiempo (o el mapa de sustos), los botones del reproductor y sus pistas.
    @ViewBuilder func playerDeck(_ model: TVNowModel, _ now: OrbitalRemote.NowPlaying) -> some View {
        let series = now.kind == "series"
        // El mapa abierto va fuera del reloj de la barra (que vuelve a pintar cada segundo): ahí adentro su entrada y su
        // salida se cortaban a medias.
        if let scares = model.scares, showsScares {
            VStack(spacing: DS.Space.s2) {
                ScarePanel(now: now, fetchedAt: model.fetchedAt, scares: scares)
                Button { withAnimation(DS.Motion.smooth(reduceMotion)) { showsScares = false } } label: {
                    Label("Ocultar los sustos", systemImage: "chevron.up").recipe(.footnote, color: DS.textMuted).frame(minHeight: DS.Size.touchTarget)
                }
                .buttonStyle(.plain)
            }
            .transition(Self.reveal)
        } else {
            TimelineView(.periodic(from: model.fetchedAt, by: DS.NowPlaying.progressTick)) { context in
                let position = now.position(at: context.date, since: model.fetchedAt)
                let seek = { (to: Double) in Task { await model.control("seek", delta: to) } }
                if let scares = model.scares {
                    // La barra se arrastra para adelantar o atrasar; el renglón de abajo (cuánto falta para el siguiente
                    // susto) abre el detalle.
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        RemoteScrubber(position: position, duration: now.duration, scares: scares) { _ = seek($0) }
                        Button { withAnimation(DS.Motion.smooth(reduceMotion)) { showsScares = true } } label: {
                            nextScare(scares, position: position).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("remote-scares")
                    }
                } else {
                    RemoteScrubber(position: position, duration: now.duration) { _ = seek($0) }
                }
            }
            .transition(.opacity)
        }
        HStack(spacing: DS.Space.s2) {
            if series { RemoteKey(symbol: "backward.end.fill", title: Text("Anterior")) { Task { await model.press(.pageleft) } } }
            RemoteKey(symbol: DS.Symbol.skipBack, title: Text("−10 s")) { Task { await model.control("skip", delta: -10) } }
            RemoteKey(symbol: now.paused ? "play.fill" : "pause.fill", title: now.paused ? Text("Continuar") : Text("Pausa")) { Task { await model.control("toggle") } }
            RemoteKey(symbol: DS.Symbol.skipForward, title: Text("+10 s")) { Task { await model.control("skip", delta: 10) } }
            if series { RemoteKey(symbol: "forward.end.fill", title: Text("Siguiente")) { Task { await model.control("next") } } }
        }
        .fixedSize(horizontal: false, vertical: true)   // las teclas de la fila, del mismo alto
        // Las pistas: si la consola las manda, se eligen aquí; si no, X (audio y subtítulos en la TV). Episodios o Fuentes
        // abre ese panel en la TV y cambia el control al pad para moverte por él.
        HStack(spacing: DS.Space.s2) {
            trackMenu(model, title: Text("Subtítulos"), symbol: "captions.bubble", action: "subtitles", tracks: now.subtitleTracks, fallback: .alt, legendKey: "alt")
            trackMenu(model, title: Text("Audio"), symbol: "waveform", action: "audio", tracks: now.audioTracks, fallback: .alt, legendKey: "alt")
            RemoteKey(symbol: series ? "list.bullet" : "square.stack", title: model.legend["options"].map { Text(verbatim: $0) } ?? (series ? Text("Episodios y versión") : Text("Versión"))) {
                Task { await model.press(.options) }
                withAnimation(DS.Motion.smooth(reduceMotion)) { showsPad = true }
            }
            .accessibilityIdentifier("remote-options")
            // Atrás hasta la última pantalla y ahí Salir (Fernando, 6 nov): lo decide la TV (cierra el panel abierto o sale).
            let exits = (model.legend["back"] ?? "Salir") == "Salir"
            RemoteKey(symbol: exits ? "xmark" : "chevron.backward", title: model.legend["back"].map { Text(verbatim: $0) } ?? Text("Salir")) {
                Task { await model.press(.back) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)   // las teclas de la fila, del mismo alto
    }

    @ViewBuilder private func trackMenu(_ model: TVNowModel, title: Text, symbol: String, action: String, tracks: [OrbitalRemote.NowPlaying.Track],
                                        fallback: OrbitalRemote.InputAction, legendKey: String) -> some View {
        if tracks.isEmpty {
            key(model, symbol, legendKey, title, fallback)
        } else {
            Menu {
                if action == "subtitles" {
                    Button { Task { await model.control(action, track: "no") } } label: {
                        if !tracks.contains(where: \.selected) { Label("Sin subtítulos", systemImage: "checkmark") } else { Text("Sin subtítulos") }
                    }
                }
                ForEach(tracks) { t in
                    Button { Task { await model.control(action, track: t.id) } } label: {
                        if t.selected { Label(t.label, systemImage: "checkmark") } else { Text(verbatim: t.label) }
                    }
                }
            } label: {
                // Como las demás teclas: el ícono a la misma altura (antes «Salir» quedaba más abajo) y solo lo primero de la
                // pista («Inglés», no «Inglés · Subtítulos · de…» cortado); el nombre completo está en el menú.
                ActionTileLabel(style: .key, title: tracks.first(where: \.selected).map { Text(verbatim: Self.shortTrack($0.label)) } ?? Text("Sin subtítulos"),
                                symbol: symbol)
                    .foregroundStyle(DS.text)
            }
            .accessibilityLabel(title)
            .accessibilityValue(tracks.first(where: \.selected).map { Text(verbatim: $0.label) } ?? Text("Sin subtítulos"))
        }
    }

    /// En vivo: canal anterior y siguiente, grandes, y silencio.
    func liveDeck(_ model: TVNowModel) -> some View {
        HStack(spacing: DS.Space.s2) {
            RemoteKey(symbol: "chevron.up", title: Text("Canal siguiente")) { Task { await model.control("channel_up") } }
            RemoteKey(symbol: "chevron.down", title: Text("Canal anterior")) { Task { await model.control("channel_down") } }
            RemoteKey(symbol: "list.bullet.rectangle", title: Text("Guía")) {
                Task { await model.control("guide") }
                withAnimation(DS.Motion.smooth(reduceMotion)) { showsPad = true }   // la guía se recorre con el pad
            }
        }
        .fixedSize(horizontal: false, vertical: true)   // las teclas de la fila, del mismo alto
    }

    /// El pad en lugar de lo de arriba (reproduciendo o en vivo): para moverte por la TV o por el panel que abriste
    /// (episodios, fuentes, la guía). Cabe en una pantalla: el pad y Atrás · Inicio · Menú · Buscar.
    @ViewBuilder private func padMode(_ model: TVNowModel) -> some View {
        // Se vuelve con el botón de arriba a la derecha (el mismo que abre el pad).
        TouchPad(selectLabel: model.legend["select"]) { action in collapse(); Task { await model.press(action) } }
            .animation(DS.Motion.base(reduceMotion), value: model.legend["select"])
            .frame(minHeight: DS.Remote.padHeightFitted, maxHeight: .infinity)   // llena el lugar de los botones (`deckOrPad`)
        HStack(spacing: DS.Space.s2) {
            key(model, "chevron.backward", "back", Text("Atrás"), .back, hold: .home)
            key(model, "house", nil, Text("Inicio"), .home)
            key(model, "line.3.horizontal", "menu", Text("Menú"), .menu)
            key(model, "magnifyingglass", "search", Text("Buscar"), .search)
        }
        .fixedSize(horizontal: false, vertical: true)   // las teclas de la fila, del mismo alto
    }

    /// Navegar la interfaz de la TV: las secciones, el pad (tocar elige) y las teclas con lo que hace cada una.
    @ViewBuilder func navigation(_ model: TVNowModel, growing: Bool = false) -> some View {
        HStack(spacing: DS.Space.s2) {
            key(model, "chevron.left.2", nil, Text("Anterior"), .prevsection)
            if let section = model.section {
                // Un renglón siempre, completo o nada (I3, 10 nov): si no cabe entero entre las teclas («Películas y se…» con
                // letra grande), se esconde; es lo secundario, las teclas ya dicen qué hacen y la TV enseña la sección.
                ViewThatFits(in: .horizontal) {
                    Text(verbatim: section).recipe(.caption, color: DS.textMuted).lineLimit(1).fixedSize()
                    EmptyView()
                }
            }
            key(model, "chevron.right.2", nil, Text("Siguiente"), .nextsection)
        }
        .fixedSize(horizontal: false, vertical: true)   // las teclas de la fila, del mismo alto
        TouchPad(selectLabel: model.legend["select"]) { action in collapse(); Task { await model.press(action) } }
            .animation(DS.Motion.base(reduceMotion), value: model.legend["select"])
            // Por el alto de la pantalla (en un SE, más bajito); en el panel del iPad crece con lo que le sobra (`growing`).
            .frame(minHeight: DS.Remote.padHeightFitted, maxHeight: growing ? .infinity : DS.Remote.padHeightFitted)
        HStack(spacing: DS.Space.s2) {
            key(model, "chevron.backward", "back", Text("Atrás"), .back, hold: .home)   // mantener: al inicio
            key(model, "bolt", "alt", Text("Atajo"), .alt)   // lo que haga en esa pantalla lo dice la leyenda
            key(model, "ellipsis", "options", Text("Opciones"), .options)
        }
        .fixedSize(horizontal: false, vertical: true)   // las teclas de la fila, del mismo alto
        HStack(spacing: DS.Space.s2) {
            // Saltan 5 en la fila de la TV (la leyenda «De 5 en 5» de la TV era igual en las dos, A16). Antes «5 atrás» sin
            // unidad y con los íconos de pista anterior/siguiente, justo bajo «Anterior / Siguiente» (revisión del 11 nov).
            key(model, DS.Symbol.rowBack, nil, Text("−5 en la fila"), .pageleft)
            key(model, "house", nil, Text("Inicio"), .home)
            key(model, "line.3.horizontal", "menu", Text("Menú"), .menu)
            key(model, "magnifyingglass", "search", Text("Buscar"), .search)
            key(model, DS.Symbol.rowForward, nil, Text("+5 en la fila"), .pageright)
        }
        .fixedSize(horizontal: false, vertical: true)   // las teclas de la fila, del mismo alto
    }

    /// Escribir en la TV: si no tiene un campo abierto, abre su búsqueda con ese texto.
    func typing(_ model: TVNowModel, autoFocus: Bool) -> some View {
        RemoteTextField(text: $text, autoFocus: autoFocus) {
            let typed = text
            sentText = text   // lo que espera mandarse ya va aquí (no reemplaza el campo después de buscar)
            Task { await model.type(typed, submit: true, replace: true) }
        }
        .task(id: text) {
            // Mientras escribes, la TV lo va enseñando: el campo de la TV se reemplaza entero con lo que hay aquí (antes se
            // mandaban letras sueltas y si la TV ya tenía algo, se pegaba: «dune» + «x» = «dunex»).
            try? await Task.sleep(nanoseconds: DS.Remote.typeDebounce)
            guard !Task.isCancelled, text != sentText else { return }
            sentText = text
            await model.type(text, submit: false, replace: true)
        }
    }
}
