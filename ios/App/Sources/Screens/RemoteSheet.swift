import SwiftUI
import OrbitalCore
import OrbitalModels

/// El control de tu Orbital, en una hoja con dos alturas (como el reproductor de Música): corta, el control de lo que se
/// ve en la TV (pausa, ±10, siguiente…); estirada hacia arriba, además el control completo de la consola: el pad
/// (`TouchPad`), sus teclas (`RemoteKey`) y «Escribir» cuando la TV tiene dónde.
struct RemoteSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject var tvNow: ModelObserver<TVNowModel>
    @Binding var large: Bool
    let onContinueHere: (OrbitalRemote.NowPlaying) -> Void
    @State private var compactHeight: CGFloat = DS.Remote.padHeight
    /// El alto del control completo, medido: la hoja estirada mide eso (sin hueco abajo) y, como no llega a la altura
    /// completa de la pantalla, iOS la deja de vidrio translúcido como la corta (a la altura completa la vuelve opaca).
    @State private var fullHeight: CGFloat = DS.Remote.padHeight * 4
    @State private var text = ""
    /// Lo que ya tiene la TV de lo que escribiste (para mandar solo la diferencia).
    @State private var sentText = ""
    @StateObject private var speech = SpeechInput()
    @State private var reply: OrbitalRemote.VoiceReply?
    @State private var asking = false
    @State private var showsGuide = false
    @State private var showsScares = false
    /// En el reproductor o la TV en vivo, el pad va plegado (lo de arriba es lo que se usa); se abre a mano.
    @State private var showsPad = false
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        let model = tvNow.model
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                header(model)
                    // El alto de la hoja corta: el de la tarjeta completa (estirada se vuelve compacta y no cuenta).
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if !large { compactHeight = min($0 + DS.Space.s6 + DS.Space.s10, UIScreen.main.bounds.height * DS.Remote.maxShareFitted) } }
                if large { full(model).transition(.opacity.combined(with: .move(edge: .bottom))) }
                else {
                    Label("Estira hacia arriba para el control completo", systemImage: "chevron.compact.up")
                        .recipe(.caption, color: DS.textFaint).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s6).padding(.bottom, DS.Space.s4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if large { fullHeight = min($0, UIScreen.main.bounds.height * DS.Remote.maxShareFitted) } }
        }
        .scrollDisabled(!large && compactHeight < UIScreen.main.bounds.height * DS.Remote.maxShareFitted)   // corta y sin caber (letra grande): se desliza
        .scrollBounceBehavior(.basedOnSize)
        // Sin nada en la TV la hoja corta no tiene qué enseñar (quedaba «Tu Orbital» y un hueco, y bajarla se atoraba ahí):
        // solo la altura completa, y bajarla la cierra.
        .presentationDetents(model.now == nil ? [.height(fullHeight)] : [.height(compactHeight), .height(fullHeight)], selection: Binding(
            get: { large || model.now == nil ? .height(fullHeight) : .height(compactHeight) },
            set: { large = $0 == .height(fullHeight) }))
        .onChange(of: model.now == nil) { _, idle in if idle { large = true } }
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.disabled)
        // Vidrio en las dos alturas (la estirada no llega a la altura completa, que iOS volvería opaca).
        .presentationBackground { Rectangle().fill(.clear).glassEffect(.regular, in: Rectangle()) }
        .animation(DS.Motion.base(reduceMotion), value: large)
        .onDisappear { speech.cancel(); model.setRemoteOpen(false) }
        .onAppear { model.setRemoteOpen(true) }   // con el control abierto, la TV se consulta más seguido
        .task(id: model.now?.metaID) { await model.loadScares() }   // el mapa de sustos de la película que suena
        .background { if let scares = model.scares, let now = model.now { ScareWatcher(now: now, fetchedAt: model.fetchedAt, scares: scares) } }
        // Los botones de volumen del iPhone suben y bajan la TV mientras el control está abierto (como el del Apple TV).
        .background { if model.isConfigured { HardwareVolumeButtons { up in Task { await model.changeVolume(by: up ? 5 : -5) } } } }
        #if DEBUG
        .task { if Demo.isOn, Demo.open == "voice-guide" { showsGuide = true }; if Demo.isOn, Demo.open == "remote-pad" { showsPad = true } }   // -demo-open voice-guide: la guía, para capturas
        #endif
        .sheet(isPresented: $showsGuide) {
            NavigationStack {
                VoiceGuideView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { showsGuide = false } } }
            }
        }
    }

    /// La voz: lo que dices lo atiende el iPhone (descargar, seguir aquí, las teclas) o tu Orbital (`VoiceAssistant`); la
    /// respuesta se enseña y se dice en voz alta, en el idioma de la app.
    private func listen(_ model: TVNowModel) {
        if speech.listening { speech.finish(); return }
        guard !asking else { return }
        let language = env.services.appSettings.uiLanguage
        // El nombre de lo que se ve en la TV, para que el dictado lo escriba bien («descarga Shōgun»).
        let hints = ["Orbital"] + [model.now?.title, model.now?.channel].compactMap { $0 }
        Task {
            await speech.start(language: language, hints: hints) { said in answer(model) { await $0.handle(said) } }
        }
    }

    /// Lo que contestó (a lo que dijiste o a la opción que tocaste): se enseña, se dice y, si es «sigue aquí», se hace.
    private func answer(_ model: TVNowModel, _ ask: @escaping @MainActor (VoiceAssistant) async -> VoiceAssistant.Outcome) {
        guard !asking else { return }
        let language = env.services.appSettings.uiLanguage
        Task {
            asking = true; reply = nil
            let outcome = await ask(VoiceAssistant(services: env.services, tvNow: model))
            asking = false
            var shown = outcome.reply
            shown.speech = Strings.message(outcome.speech, language: language)
            withAnimation(DS.Motion.base(reduceMotion)) { reply = shown }
            speech.speak(shown.speech, language: language)
            if outcome.continueHere, let now = model.now { onContinueHere(now) }
        }
    }

    /// Una tecla del mando: su nombre es el de la leyenda de la TV para esa tecla si la consola la manda (lo que dice el pie de
    /// la pantalla); si no, el de siempre. Que no salga en el pie no quiere decir que no haga nada (en Inicio A, X y Y están en
    /// los botones del destacado), así que nunca se atenúa.
    private func key(_ model: TVNowModel, _ symbol: String, _ glyph: String?, _ legendKey: String?, _ fallback: Text,
                     _ action: OrbitalRemote.InputAction, hold: OrbitalRemote.InputAction? = nil) -> some View {
        let named = legendKey.flatMap { model.legend[$0] }
        return RemoteKey(symbol: symbol, title: named.map { Text(verbatim: $0) } ?? fallback, glyph: glyph,
                         longPress: hold.map { held in { Task { await model.press(held) } } }) {
            Task { await model.press(action) }
        }
        .accessibilityIdentifier("remote-\(action.rawValue)")   // fijo aunque el nombre cambie con la leyenda
    }

    /// Lo que se ve en la TV (el control de siempre) o, si nada se reproduce, solo el nombre de tu Orbital.
    @ViewBuilder private func header(_ model: TVNowModel) -> some View {
        if large, let now = model.now {
            // Estirada: lo que se ve en la TV en un renglón (póster, nombre y pausa); el resto del alto es para el control.
            HStack(spacing: DS.Space.s3) {
                PosterView(url: now.art, title: now.title, aspect: DS.Poster.aspect, whole: true).frame(width: DS.Size.thumbSmall)
                VStack(alignment: .leading, spacing: 0) {
                    Text(now.live ? (now.channel ?? now.title) : now.title).recipe(.cardTitle).lineLimit(1)
                    Text(now.live ? "En la TV · En vivo" : "En la TV").recipe(.footnote, color: now.live ? DS.live : DS.textMuted).lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                if model.context == .player || model.context == .live {
                    // Reproduciendo o en vivo (la pausa ya está en sus teclas): el pad, para moverte por la TV cuando quieras.
                    DSIconButton(symbol: showsPad ? "play.rectangle" : "hand.point.up.left", label: showsPad ? (model.context == .live ? LocalizedStringKey("Volver a los canales") : LocalizedStringKey("Volver al reproductor")) : LocalizedStringKey("Moverte por la TV"),
                                 prominent: !showsPad) {
                        withAnimation(DS.Motion.base(reduceMotion)) { showsPad.toggle() }
                    }
                    .accessibilityIdentifier("remote-pad-button")
                } else if !now.live {
                    DSIconButton(symbol: now.paused ? "play.fill" : "pause.fill", label: now.paused ? "Continuar" : "Pausa", prominent: true) {
                        Task { await model.control("toggle") }
                    }
                }
            }
        } else if let now = model.now {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                NowPlayingCard(now: now, fetchedAt: model.fetchedAt, busy: model.busy,
                               onAction: { action, delta in Task { await model.control(action, delta: delta) } },
                               onContinueHere: { onContinueHere(now) }, framed: false, scares: model.scares ?? [])
                // Una película con mapa de sustos: un toque lo abre aquí mismo (la línea de tiempo, el siguiente y el aviso).
                if let scares = model.scares {
                    if showsScares { ScarePanel(now: now, fetchedAt: model.fetchedAt, scares: scares).transition(.opacity.combined(with: .move(edge: .top))) }
                    Button { withAnimation(DS.Motion.base(reduceMotion)) { showsScares.toggle() } } label: {
                        Label(showsScares ? "Ocultar los sustos" : "Mapa de sustos · \(scares.count)", systemImage: showsScares ? "chevron.up" : "bolt.heart")
                            .recipe(.footnote, color: DS.text).fontWeight(.semibold)
                            .padding(.horizontal, DS.Space.s4).frame(minHeight: DS.Size.touchTarget)
                            .background(DS.fill, in: Capsule())
                    }
                    .buttonStyle(.plain).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("remote-scares")
                }
            }
        } else if model.tokenProblem {
            // La TV ya no reconoce este iPhone (cambió su token): sin esto el control quedaba muerto sin decir por qué.
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Label("Tu Orbital ya no reconoce este iPhone", systemImage: "lock.trianglebadge.exclamationmark").recipe(.cardTitle)
                Text("Vuelve a conectarlos: en tu TV abre Ajustes › iPhone y escanea el código.").recipe(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.unreachable && !model.answered || model.unreachable && model.now == nil {
            // Apagada u otra red: lo dice y deja reintentar (antes «Conectando…» se quedaba girando para siempre).
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Label("Tu Orbital no contesta", systemImage: "tv.slash").recipe(.cardTitle)
                    Text("Revisa que la consola esté prendida y en la misma red que tu iPhone.").recipe(.footnote)
                }
                Button { Task { await model.retryNow() } } label: {
                    Text("Intentar de nuevo").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.text)
                        .padding(.horizontal, DS.Space.s4).frame(minHeight: DS.Size.touchTarget)
                        .background(DS.fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("remote-retry")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !model.answered {
            // La TV todavía no contesta (recién abierta la app): no se dice «nada sonando» antes de saberlo.
            HStack(spacing: DS.Space.s3) {
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(DS.fill)
                    .frame(width: DS.Size.thumbSmall, height: DS.Size.thumbSmall / DS.Poster.aspect)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Conectando con tu Orbital…").recipe(.cardTitle)
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: DS.Space.s2) {
                OrbitalMark(size: DS.Size.markSmall).foregroundStyle(DS.text)
                Text("Tu Orbital").recipe(.section)
            }
        }
    }

    /// El control completo, según lo que hay al frente en la TV:
    /// - **Reproduciendo**: la línea de tiempo (con sus sustos), ±10, pausa, siguiente, subtítulos y audio; el pad plegado.
    /// - **En vivo**: canal anterior y siguiente; el pad plegado.
    /// - **Escribiendo** (la búsqueda o la cuenta de la TV): el campo primero, con el teclado; luego el pad.
    /// - **Navegando**: el pad, las secciones y las teclas con lo que hace cada una en esa pantalla.
    /// Arriba siempre la voz; el volumen en todas.
    @ViewBuilder private func full(_ model: TVNowModel) -> some View {
        VStack(spacing: DS.Space.s4) {
            if model.remoteOutdated { DSNotice(text: "Actualiza tu Orbital para usar el control completo.", tone: .warn) }
            voice(model)
            if let choices = reply?.choices, !choices.isEmpty {
                VoiceChoices(choices: choices) { choice in answer(model) { await $0.choose(choice) } }
                    .transition(.opacity)
            }
            switch model.context {
            // Reproduciendo o en vivo, el pad no se suma abajo (no cabía y repetía pausa, ±10, volumen, pistas y salir):
            // reemplaza lo de arriba cuando hace falta moverse por un panel de la TV (episodios, fuentes, la guía).
            case .player:
                if showsPad { padMode(model) }
                else {
                    if let now = model.now { playerDeck(model, now) }
                    volume(model)
                }
            case .live:
                if showsPad { padMode(model) }
                else {
                    liveDeck(model)
                    volume(model)
                }
            case .typing:
                typing(model, autoFocus: true)
                navigation(model)
                volume(model)
            case .browse:
                volume(model)
                navigation(model)
                typing(model, autoFocus: model.textField == true)
            }
        }
        .animation(DS.Motion.base(reduceMotion), value: model.context)
        .animation(DS.Motion.base(reduceMotion), value: showsPad)
        .onChange(of: model.context) { _, _ in showsPad = false }   // otra pantalla en la TV: vuelve a lo suyo
    }

    private func voice(_ model: TVNowModel) -> some View {
        // La voz, como Alexa: lo mismo que «Oye Siri, dile a Orbital…».
        HStack(spacing: DS.Space.s2) {
            VoiceCommandBar(listening: speech.listening, transcript: speech.transcript, reply: reply, denied: speech.denied,
                            heardNothing: speech.heardNothing, asking: asking) { listen(model) }
            // Lo que puedes decir: donde surge la duda (como el resto de las teclas).
            // Del mismo alto que «Dile a Orbital» (que crece con su texto): antes quedaba más bajito a su lado.
            Button { showsGuide = true } label: {
                Image(systemName: "questionmark").font(DS.TextRecipe.cardTitle.font.weight(.semibold)).foregroundStyle(DS.text)
                    .frame(width: DS.Remote.keyHeightFitted).frame(maxHeight: .infinity)
                    .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Lo que puedes decir"))
            .accessibilityIdentifier("remote-voice-guide")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func volume(_ model: TVNowModel) -> some View {
        // El volumen de la TV (el de Windows, como Alexa): − · barra · +, y silencio.
        VolumeControl(level: model.volume?.level, muted: model.volume?.muted ?? false,
                      down: { Task { await model.changeVolume(by: -5) } }, up: { Task { await model.changeVolume(by: 5) } },
                      mute: { Task { await model.toggleMute() } })
        if model.volumeOutdated { DSNotice(text: "Actualiza tu Orbital para cambiar el volumen desde aquí.", tone: .warn) }
    }

    /// Reproduciendo: la línea de tiempo (o el mapa de sustos), los botones del reproductor y sus pistas.
    @ViewBuilder private func playerDeck(_ model: TVNowModel, _ now: OrbitalRemote.NowPlaying) -> some View {
        let series = now.kind == "series"
        TimelineView(.periodic(from: model.fetchedAt, by: DS.NowPlaying.progressTick)) { context in
            let position = now.position(at: context.date, since: model.fetchedAt)
            if let scares = model.scares, showsScares {
                VStack(spacing: DS.Space.s2) {
                    ScarePanel(now: now, fetchedAt: model.fetchedAt, scares: scares)
                    Button { withAnimation(DS.Motion.base(reduceMotion)) { showsScares = false } } label: {
                        Label("Ocultar los sustos", systemImage: "chevron.up").recipe(.footnote, color: DS.textMuted).frame(minHeight: DS.Size.touchTarget)
                    }
                    .buttonStyle(.plain)
                }
            } else if let scares = model.scares {
                // Los sustos en un renglón (la barra y cuánto falta para el siguiente); un toque abre el detalle.
                Button { withAnimation(DS.Motion.base(reduceMotion)) { showsScares = true } } label: {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        ScareTimeline(position: position, duration: now.duration, scares: scares)
                        nextScare(scares, position: position)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("remote-scares")
            } else {
                ScareTimeline(position: position, duration: now.duration)
            }
        }
        HStack(spacing: DS.Space.s2) {
            if series { RemoteKey(symbol: "backward.end.fill", title: Text("Anterior")) { Task { await model.press(.pageleft) } } }
            RemoteKey(symbol: "gobackward.10", title: Text("−10 s")) { Task { await model.control("skip", delta: -10) } }
            RemoteKey(symbol: now.paused ? "play.fill" : "pause.fill", title: now.paused ? Text("Continuar") : Text("Pausa")) { Task { await model.control("toggle") } }
            RemoteKey(symbol: "goforward.10", title: Text("+10 s")) { Task { await model.control("skip", delta: 10) } }
            if series { RemoteKey(symbol: "forward.end.fill", title: Text("Siguiente")) { Task { await model.control("next") } } }
        }
        // Las pistas: si la consola las manda, se eligen aquí; si no, X (audio y subtítulos en la TV). Episodios o Fuentes
        // abre ese panel en la TV y cambia el control al pad para moverte por él.
        HStack(spacing: DS.Space.s2) {
            trackMenu(model, title: Text("Subtítulos"), symbol: "captions.bubble", action: "subtitles", tracks: now.subtitleTracks, fallback: .alt, legendKey: "alt")
            trackMenu(model, title: Text("Audio"), symbol: "waveform", action: "audio", tracks: now.audioTracks, fallback: .alt, legendKey: "alt")
            RemoteKey(symbol: series ? "list.bullet" : "square.stack", title: model.legend["options"].map { Text(verbatim: $0) } ?? (series ? Text("Episodios") : Text("Versión"))) {
                Task { await model.press(.options) }
                withAnimation(DS.Motion.base(reduceMotion)) { showsPad = true }
            }
            .accessibilityIdentifier("remote-options")
            RemoteKey(symbol: "xmark", title: Text("Salir")) { Task { await model.control("stop") } }
        }
    }

    /// «0:53 para el siguiente susto» (o que ya no quedan).
    private func nextScare(_ scares: [JumpScare], position: Double) -> some View {
        let next = scares.first { $0.time > position }
        let text = next.map { Text("\(Duration.seconds(Int($0.time - position)).formatted(.time(pattern: .minuteSecond))) para el siguiente susto") }
            ?? Text("Ya no quedan sustos")
        return HStack(spacing: DS.Space.s1) {
            text.recipe(.footnote, color: DS.textMuted).monospacedDigit().lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Image(systemName: "chevron.down").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textFaint)
        }
    }

    @ViewBuilder private func trackMenu(_ model: TVNowModel, title: Text, symbol: String, action: String, tracks: [OrbitalRemote.NowPlaying.Track],
                                        fallback: OrbitalRemote.InputAction, legendKey: String) -> some View {
        if tracks.isEmpty {
            key(model, symbol, nil, legendKey, title, fallback)
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
                VStack(spacing: DS.Space.s1) {
                    Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).frame(height: DS.Remote.keyIcon)
                    (tracks.first(where: \.selected).map { Text(verbatim: Self.shortTrack($0.label)) } ?? Text("Sin subtítulos"))
                        .recipe(.caption, color: DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                }
                .foregroundStyle(DS.text)
                .frame(maxWidth: .infinity, minHeight: DS.Remote.keyHeightFitted)
                .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            }
            .accessibilityLabel(title)
            .accessibilityValue(tracks.first(where: \.selected).map { Text(verbatim: $0.label) } ?? Text("Sin subtítulos"))
        }
    }

    /// Lo primero del nombre de una pista («Inglés · Subtítulos · de Netflix» → «Inglés»).
    static func shortTrack(_ label: String) -> String {
        label.components(separatedBy: " · ").first.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } ?? label
    }

    /// En vivo: canal anterior y siguiente, grandes, y silencio.
    private func liveDeck(_ model: TVNowModel) -> some View {
        HStack(spacing: DS.Space.s2) {
            RemoteKey(symbol: "chevron.up", title: Text("Canal siguiente")) { Task { await model.control("channel_up") } }
            RemoteKey(symbol: "chevron.down", title: Text("Canal anterior")) { Task { await model.control("channel_down") } }
            RemoteKey(symbol: "list.bullet.rectangle", title: Text("Guía")) {
                Task { await model.control("guide") }
                withAnimation(DS.Motion.base(reduceMotion)) { showsPad = true }   // la guía se recorre con el pad
            }
        }
    }

    /// El pad en lugar de lo de arriba (reproduciendo o en vivo): para moverte por la TV o por el panel que abriste
    /// (episodios, fuentes, la guía). Cabe en una pantalla: el pad y Atrás · Inicio · Menú · Buscar.
    @ViewBuilder private func padMode(_ model: TVNowModel) -> some View {
        // Se vuelve con el botón de arriba a la derecha (el mismo que abre el pad).
        TouchPad(selectLabel: model.legend["select"]) { action in Task { await model.press(action) } }
            .animation(DS.Motion.base(reduceMotion), value: model.legend["select"])
            .frame(height: DS.Remote.padHeightFitted)
        HStack(spacing: DS.Space.s2) {
            key(model, "chevron.backward", "B", "back", Text("Atrás"), .back, hold: .home)
            key(model, "house", nil, nil, Text("Inicio"), .home)
            key(model, "line.3.horizontal", nil, "menu", Text("Menú"), .menu)
            key(model, "magnifyingglass", nil, "search", Text("Buscar"), .search)
        }
    }

    /// Navegar la interfaz de la TV: las secciones (LB / RB), el pad (A al tocar) y las teclas con lo que hace cada una.
    @ViewBuilder private func navigation(_ model: TVNowModel) -> some View {
        HStack(spacing: DS.Space.s2) {
            key(model, "chevron.left.2", "LB", nil, Text("Anterior"), .prevsection)
            if let section = model.section {
                // Un renglón siempre: con letra grande se achica (antes se partía en «Pelícu-las y s…» entre las teclas).
                Text(verbatim: section).recipe(.caption, color: DS.textMuted).lineLimit(1)
                    .minimumScaleFactor(DS.Size.statScale).multilineTextAlignment(.center)
                    .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)   // con letra grande cede: «Ante…» no cabía
            }
            key(model, "chevron.right.2", "RB", nil, Text("Siguiente"), .nextsection)
        }
        TouchPad(selectLabel: model.legend["select"]) { action in Task { await model.press(action) } }
            .animation(DS.Motion.base(reduceMotion), value: model.legend["select"])
            // Por el alto de la pantalla (no de la hoja: la hoja mide lo que mide el control).
            .frame(height: DS.Remote.padHeightFitted)   // en un SE, más bajito: las teclas de abajo y «Escribir» caben
        HStack(spacing: DS.Space.s2) {
            key(model, "chevron.backward", "B", "back", Text("Atrás"), .back, hold: .home)   // mantener: al inicio
            key(model, "bolt", "X", "alt", Text("Atajo"), .alt)   // lo que haga X en esa pantalla lo dice la leyenda
            key(model, "ellipsis", "Y", "options", Text("Opciones"), .options)
        }
        HStack(spacing: DS.Space.s2) {
            key(model, "backward.end", narrowGlyph("LT"), "page", Text("−5"), .pageleft)
            key(model, "house", nil, nil, Text("Inicio"), .home)
            key(model, "line.3.horizontal", nil, "menu", Text("Menú"), .menu)
            key(model, "magnifyingglass", nil, "search", Text("Buscar"), .search)
            key(model, "forward.end", narrowGlyph("RT"), "page", Text("+5"), .pageright)
        }
    }

    /// En la fila de cinco teclas de un teléfono bajito no cabe la letra del mando junto al ícono: se quita.
    private func narrowGlyph(_ glyph: String) -> String? { DS.Remote.isShortScreen ? nil : glyph }

    /// Escribir en la TV: si no tiene un campo abierto, abre su búsqueda con ese texto.
    private func typing(_ model: TVNowModel, autoFocus: Bool) -> some View {
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
