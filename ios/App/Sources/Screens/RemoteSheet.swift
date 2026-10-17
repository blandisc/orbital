import SwiftUI
import OrbitalCore
import OrbitalModels

/// El control de tu Orbital, en una hoja con dos alturas (como el reproductor de Música): corta, el control de lo que se
/// ve en la TV (pausa, ±10, siguiente…); estirada hacia arriba, además el control completo de la consola: el pad
/// (`TouchPad`), sus teclas (`RemoteKey`) y «Escribir» cuando la TV tiene dónde.
struct RemoteSheet: View {
    @ObservedObject var tvNow: ModelObserver<TVNowModel>
    @Binding var large: Bool
    let onContinueHere: (OrbitalRemote.NowPlaying) -> Void
    @State private var compactHeight: CGFloat = DS.Remote.padHeight
    @State private var text = ""
    @StateObject private var speech = SpeechInput()
    @State private var reply: OrbitalRemote.VoiceReply?
    @State private var asking = false
    @State private var showsGuide = false
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        let model = tvNow.model
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                header(model)
                    // El alto de la hoja corta: el de la tarjeta completa (estirada se vuelve compacta y no cuenta).
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if !large { compactHeight = $0 + DS.Space.s6 + DS.Space.s10 } }
                if large { full(model).transition(.opacity.combined(with: .move(edge: .bottom))) }
                else {
                    Label("Estira hacia arriba para el control completo", systemImage: "chevron.compact.up")
                        .recipe(.caption, color: DS.textFaint).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s6).padding(.bottom, DS.Space.s4)
        }
        .scrollDisabled(!large)
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(compactHeight), .large], selection: Binding(
            get: { large ? .large : .height(compactHeight) },
            set: { large = $0 == .large }))
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.disabled)
        .animation(DS.Motion.base(false), value: large)
        .onDisappear { speech.cancel() }
        .task { if Demo.isOn, Demo.open == "voice-guide" { showsGuide = true } }   // -demo-open voice-guide: la guía, para capturas
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
            withAnimation(DS.Motion.base(false)) { reply = shown }
            speech.speak(shown.speech, language: language)
            if outcome.continueHere, let now = model.now { onContinueHere(now) }
        }
    }

    /// Una tecla del mando: su nombre es el de la leyenda de la TV para esa tecla si la consola la manda (lo que dice el pie de
    /// la pantalla); si no, el de siempre. Que no salga en el pie no quiere decir que no haga nada (en Inicio A, X y Y están en
    /// los botones del destacado), así que nunca se atenúa.
    private func key(_ model: TVNowModel, _ symbol: String, _ glyph: String?, _ legendKey: String?, _ fallback: Text,
                     _ action: OrbitalRemote.InputAction) -> some View {
        let named = legendKey.flatMap { model.legend[$0] }
        return RemoteKey(symbol: symbol, title: named.map { Text(verbatim: $0) } ?? fallback, glyph: glyph) {
            Task { await model.press(action) }
        }
        .accessibilityIdentifier("remote-\(action.rawValue)")   // fijo aunque el nombre cambie con la leyenda
    }

    /// Lo que se ve en la TV (el control de siempre) o, si nada se reproduce, solo el nombre de tu Orbital.
    @ViewBuilder private func header(_ model: TVNowModel) -> some View {
        if large, let now = model.now {
            // Estirada: lo que se ve en la TV en un renglón (póster, nombre y pausa); el resto del alto es para el control.
            HStack(spacing: DS.Space.s3) {
                PosterView(url: now.poster, title: now.title, aspect: DS.Poster.aspect).frame(width: DS.Size.thumbSmall)
                VStack(alignment: .leading, spacing: 0) {
                    Text(now.live ? (now.channel ?? now.title) : now.title).recipe(.cardTitle).lineLimit(1)
                    Text(now.live ? "En la TV · En vivo" : "En la TV").recipe(.footnote, color: now.live ? DS.live : DS.textMuted).lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                if !now.live {
                    DSIconButton(symbol: now.paused ? "play.fill" : "pause.fill", label: now.paused ? "Reanudar" : "Pausa", prominent: true) {
                        Task { await model.control("toggle") }
                    }
                }
            }
        } else if let now = model.now {
            NowPlayingCard(now: now, fetchedAt: model.fetchedAt, busy: model.busy,
                           onAction: { action, delta in Task { await model.control(action, delta: delta) } },
                           onContinueHere: { onContinueHere(now) }, framed: false)
        } else {
            HStack(spacing: DS.Space.s2) {
                OrbitalMark(size: DS.Size.markSmall).foregroundStyle(DS.text)
                Text("Tu Orbital").recipe(.section)
            }
        }
    }

    /// El control completo: el pad, las teclas de la consola y escribir.
    @ViewBuilder private func full(_ model: TVNowModel) -> some View {
        VStack(spacing: DS.Space.s4) {
            if model.remoteOutdated { DSNotice(text: "Actualiza tu Orbital para usar el control completo.", tone: .warn) }
            // La voz, como Alexa: lo mismo que «Oye Siri, dile a Orbital…».
            HStack(spacing: DS.Space.s2) {
                VoiceCommandBar(listening: speech.listening, transcript: speech.transcript, reply: reply, denied: speech.denied,
                                heardNothing: speech.heardNothing, asking: asking) { listen(model) }
                // Lo que puedes decir: donde surge la duda.
                DSIconButton(symbol: "questionmark", label: "Lo que puedes decir") { showsGuide = true }
                    .accessibilityIdentifier("remote-voice-guide")
            }
            if let choices = reply?.choices, !choices.isEmpty {
                VoiceChoices(choices: choices) { choice in answer(model) { await $0.choose(choice) } }
                    .transition(.opacity)
            }
            // Como el mando: arriba los gatillos de sección (LB / RB), al centro el pad (A al tocar), luego B · X · Y y abajo
            // LT / RT, Inicio, ☰ y ⧉. Cada tecla dice lo que hace en la pantalla de la TV (su leyenda), si la consola lo dice.
            HStack(spacing: DS.Space.s2) {
                key(model, "chevron.left.2", "LB", nil, Text("Anterior"), .prevsection)
                if let section = model.section {
                    Text(verbatim: section).recipe(.caption, color: DS.textMuted).lineLimit(1).fixedSize()
                }
                key(model, "chevron.right.2", "RB", nil, Text("Siguiente"), .nextsection)
            }
            TouchPad(selectLabel: model.legend["select"]) { action in Task { await model.press(action) } }
                .animation(DS.Motion.base(false), value: model.legend["select"])
                .containerRelativeFrame(.vertical) { length, _ in max(DS.Remote.padHeight, length * DS.Remote.padShare) }
            HStack(spacing: DS.Space.s2) {
                key(model, "chevron.backward", "B", "back", Text("Atrás"), .back)
                key(model, "square.on.square", "X", "alt", Text("Acción X"), .alt)
                key(model, "ellipsis", "Y", "options", Text("Opciones"), .options)
            }
            HStack(spacing: DS.Space.s2) {
                key(model, "backward.end", "LT", "page", Text("−5"), .pageleft)
                key(model, "house", nil, nil, Text("Inicio"), .home)
                key(model, "line.3.horizontal", "☰", "menu", Text("Menú"), .menu)
                key(model, "magnifyingglass", "⧉", "search", Text("Buscar"), .search)
                key(model, "forward.end", "RT", "page", Text("+5"), .pageright)
            }
            // Siempre: si la TV no tiene un campo abierto, escribir abre su búsqueda con ese texto.
            RemoteTextField(text: $text) { let typed = text; Task { await model.type(typed, submit: true) } }
                .task(id: text) {
                    // Mientras escribes, la TV lo va enseñando (sin mandar cada letra por separado).
                    guard !text.isEmpty else { return }
                    try? await Task.sleep(nanoseconds: DS.Remote.typeDebounce)
                    guard !Task.isCancelled else { return }
                    await model.type(text, submit: false)
                }
        }
    }
}
