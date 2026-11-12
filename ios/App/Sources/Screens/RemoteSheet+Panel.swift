import SwiftUI
import OrbitalCore
import OrbitalModels

/// El control de la TV como panel fijo a la derecha (solo el iPad con ventana ancha; la Mac no tiene control de la TV): «Arriba lo que suena, abajo el control»
/// (CT2, Fernando, 11 nov 2026: «no tiene caso tener todo ese espacio vacío abajo»). Antes el panel acomodaba todo desde
/// arriba y dejaba vacío el tercio de abajo. Ahora:
/// - **Arriba** lo que hay en la tele: con algo sonando, su arte, su nombre, «T1 E3 · quedan 27 min» y lo de su reproductor
///   (la barra, ±10, pausa, subtítulos, audio, «Seguir aquí»); en reposo, tus «Seguir viendo» para mandarlos a la tele.
/// - **Abajo**, junto al pulgar, el control de siempre en el mismo orden (voz, volumen, secciones, el pad, las teclas y
///   «Escribir en la TV») hasta el borde de abajo. El pad crece con el alto que sobra; si no cabe (iPad chico acostado,
///   letra grande), el panel se desliza.
/// La hoja del iPhone no cambia (`RemoteSheet.body`). Regla en `docs/ios-interfaz.md` § «Un panel alto no deja el fondo vacío».
extension RemoteSheet {
    func panel(_ model: TVNowModel, close: @escaping () -> Void) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                DSSheetHeader(title: Text("Control de la TV")) {
                    DSIconButton(symbol: "xmark", label: "Cerrar", size: .regular, action: close).accessibilityIdentifier("remote-panel-close")
                }
                VStack(alignment: .leading, spacing: DS.Remote.blockGap) {
                    panelTop(model)
                    panelControl(model)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .dsSheetContent()
            // Al menos el alto del panel: lo que sobra se lo queda el pad y el control llega al borde de abajo.
            .frame(minHeight: panelHeight, alignment: .top)
        }
        // La columna del panel no llega abajo (iOS le guarda el lugar de la barra de abajo): el panel sí, hasta el margen seguro.
        .ignoresSafeArea(.container, edges: .bottom)
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height - $0.contentInsets.top - $0.contentInsets.bottom } action: { _, height in
            panelHeight = max(0, height)
        }
        // De reposo a sonando (y al revés) solo cambia lo de arriba, con un fundido; el control de abajo no se mueve.
        .animation(DS.Motion.smooth(reduceMotion), value: model.now == nil)
        .animation(DS.Motion.smooth(reduceMotion), value: model.context)
    }

    /// Lo que hay en la tele: lo que suena con su reproductor, o tus «Seguir viendo» si está en reposo.
    @ViewBuilder private func panelTop(_ model: TVNowModel) -> some View {
        if let now = model.now {
            VStack(alignment: .leading, spacing: DS.Remote.groupGap) {
                switch model.context {
                case .player:
                    RemoteNowHeader(now: now, fetchedAt: model.fetchedAt, language: env.language, continueHere: { onContinueHere(now) })
                    playerDeck(model, now)
                case .live:
                    RemoteNowHeader(now: now, fetchedAt: model.fetchedAt, language: env.language)
                    liveDeck(model)
                case .browse, .typing:
                    // Algo en pausa detrás de un menú de la TV: la tarjeta de siempre (pausa, ±10 y «Seguir aquí» en «Más»).
                    NowPlayingCard(now: now, fetchedAt: model.fetchedAt, busy: model.busy,
                                   onAction: { action, delta in Task { await model.control(action, delta: delta) } },
                                   onContinueHere: { onContinueHere(now) }, framed: false, scares: model.scares ?? [])
                }
            }
            .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: DS.Remote.groupGap) {
                RemoteStatusCard(tvNow: tvNow)
                if model.answered, !model.unreachable, !model.tokenProblem {
                    RemotePanelIdle(hints: model.hints, say: { say(model, $0) })
                }
            }
            .transition(.opacity)
        }
    }

    /// El control, en el orden de siempre y anclado abajo: el pad (`navigation(growing:)`) se estira con lo que sobra.
    private func panelControl(_ model: TVNowModel) -> some View {
        VStack(spacing: DS.Remote.groupGap) {
            if model.remoteOutdated { DSNotice(text: "Actualiza tu Orbital para usar el control completo.", tone: .warn) }
            voice(model)
            volume(model)
            navigation(model, growing: true)
            typing(model, autoFocus: model.context == .typing || model.textField == true)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// «0:53 para el siguiente susto» (o que ya no quedan).
    func nextScare(_ scares: [JumpScare], position: Double) -> some View {
        let next = scares.first { $0.time > position }
        let text = next.map { Text("\(Duration.seconds(Int($0.time - position)).formatted(.time(pattern: .minuteSecond))) para el siguiente susto") }
            ?? Text("Ya no quedan sustos")
        return HStack(spacing: DS.Space.s1) {
            text.recipe(.footnote, color: DS.textMuted).monospacedDigit().lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Image(systemName: "chevron.down").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textFaint)
        }
    }

    /// Lo primero del nombre de una pista («Inglés · Subtítulos · de Netflix» → «Inglés»).
    static func shortTrack(_ label: String) -> String {
        label.components(separatedBy: " · ").first.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } ?? label
    }
}

/// La tele en reposo, en el panel: tus «Seguir viendo» (los mismos de Inicio) para mandarlos con un toque («Ver en la TV»).
/// Sin nada a medias, las frases de la voz del momento, que se tocan como si las dijeras.
struct RemotePanelIdle: View {
    let hints: [String]
    let say: (String) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.titleName) private var titleName
    @State private var home = ModelObserver(HomeModel(AppEnvironment.shared.services))

    var body: some View {
        let items = Array(home.model.continueWatching.prefix(DS.Remote.panelContinueCount))
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !items.isEmpty {
                DSSectionHead(title: Text("Seguir viendo"), eyebrow: Text("Un toque y empieza en la TV"))
                ForEach(items) { item in
                    let name = titleName(item.title, id: item.metaID, kind: item.kind)
                    Button { Task { await env.playOnTV(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title) } } label: {
                        RemoteSendRow(title: name, art: item.background ?? item.poster,
                                      detail: progressFact(season: item.season, episode: item.episode, leftMinutes: item.leftMinutes, language: env.language),
                                      progress: item.progress, sending: env.isSendingToTV(item.metaID))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Ver en la TV: \(name)"))
                    .accessibilityIdentifier("remote-send-\(item.metaID)")
                }
            } else if !hints.isEmpty {
                DSSectionHead(title: Text("Nada en la TV"), eyebrow: Text("Prueba a decirle"))
                ForEach(hints, id: \.self) { phrase in
                    Button { say(phrase) } label: { RemoteHintRow(phrase: phrase) }
                        .buttonStyle(.plain)
                }
            }
        }
        .task { await home.model.showLibrary() }   // lo del teléfono, sin esperar a la red
    }
}
