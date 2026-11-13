import SwiftUI
import OrbitalCore
import OrbitalModels

/// Las dos preguntas del reproductor son tarjetas de la app, no diálogos del sistema (Fernando, 13 nov 2026: «Sí, también
/// conviértelos en la tarjeta, los otros tres diálogos»). Es la misma tarjeta de «Ya lo viste» (`ChoiceCard`), pero flotando
/// sobre el video como los paneles del reproductor (`ChoiceSheet(floating:)`) y no como hoja: en horizontal la hoja de iOS
/// sube a todo el alto y tapa el video, y el reproductor ya pone sus paneles y avisos en su propio escenario. Sin vibrar.
/// (Parte de `PlayerScreen`, separada por responsabilidad.)
extension PlayerScreen {
    /// La pregunta a la vista, si hay. «¿Sigues viendo?» va primero: llega al terminar el episodio, con el video en pausa.
    func playerQuestion(_ model: PlayerModel) -> ChoiceCard? {
        if model.stillWatchingPrompt {
            // Tres episodios seguidos sin tocar la pantalla: el siguiente espera aquí, en pausa, hasta que contestes (como
            // antes, no se cierra sin elegir). «Seguir» a secas es seguir una serie (Follow): por eso «Seguir viendo».
            return ChoiceCard(title: Text("¿Sigues viendo?"), detail: Text("Llevas tres episodios seguidos."),
                              primary: ChoiceAction(id: "still-watching-yes", title: Text("Seguir viendo"), symbol: "play.fill") {
                                  Task { await model.confirmStillWatching() }
                              },
                              options: [ChoiceAction(id: "still-watching-leave", title: Text("Salir"), symbol: DS.Symbol.leavePlayer) {
                                  Task { await close() }
                              }],
                              id: "still-watching-card")
        }
        if let index = dockState.slowPick {
            // Cerrarla es «Mejor no»: sigue la que ves.
            return ChoiceCard(title: Text("Real-Debrid aún no tiene esta versión"),   // edición: solo al elegir una por pedir (instantStreams)
                              detail: Text("Empieza a bajarla y puede tardar minutos u horas. Si manda su aviso de «descargando», vuelves a la que ves en el mismo punto."),
                              primary: ChoiceAction(id: "slow-pick-open", title: Text("Abrirla de todos modos"), symbol: DS.Symbol.cloud) {
                                  dockState.slowPick = nil
                                  withAnimation(DS.Motion.base(reduceMotion)) { dockState.subtitleDock = false; dockState.dockPage = .media }
                                  Task { await model.switchSource(to: index) }
                              },
                              id: "slow-pick-card")
        }
        return nil
    }

    /// Cerrar la pregunta sin elegir (tocar fuera, Esc, el gesto de escape de VoiceOver): solo la de la versión, que es «Mejor
    /// no». «¿Sigues viendo?» no se cierra sola; con Esc es «Salir», como lo era la del sistema.
    func dismissPlayerQuestion() -> Bool {
        guard dockState.slowPick != nil else { return false }
        withAnimation(DS.Motion.base(reduceMotion)) { dockState.slowPick = nil }
        return true
    }

    /// Encima de todo (también del candado: «¿Sigues viendo?» llega aunque esté bloqueado). El video se oscurece detrás; en
    /// vertical la tarjeta va abajo, en el lugar de los controles, y en horizontal al centro. Siempre dentro del área segura y,
    /// si no cabe (SE en horizontal, letra grande), se desplaza por dentro: nunca cortada.
    func questionLayer(_ model: PlayerModel) -> some View {
        let card = playerQuestion(model)
        return ZStack(alignment: landscape ? .center : .bottom) {
            if let card {
                DS.scrim.ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { _ = dismissPlayerQuestion() }
                    .accessibilityHidden(true)
                ViewThatFits(in: .vertical) {
                    floatingCard(card)
                    ScrollView { floatingCard(card) }.scrollBounceBehavior(.basedOnSize)
                }
                .frame(maxWidth: landscape ? DS.PlayerPanel.width : DS.PlayerPanel.dockWidth)
                .padding(DS.Space.gutter)
                .accessibilityAction(.escape) { if !dismissPlayerQuestion() { Task { await close() } } }
                .transition(landscape ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.Motion.base(reduceMotion), value: card?.id)
    }

    private func floatingCard(_ card: ChoiceCard) -> some View {
        ChoiceSheet(card: card, floating: true) { action in action.run() }
    }

    #if DEBUG
    /// `-demo-player-state slow-pick`: la pregunta de una versión que Real-Debrid aún no tiene (la que no suena); la de
    /// «¿Sigues viendo?» la pone el modelo (`still-watching`).
    func demoQuestion(_ state: String, _ model: PlayerModel) -> Bool {
        guard state == "slow-pick" else { return false }
        dockState.slowPick = model.sourceChoices.first { $0.index != model.source?.index }?.index ?? 0
        return true
    }
    #endif
}
