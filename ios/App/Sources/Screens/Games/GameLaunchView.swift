import SwiftUI

/// Al tocar «Jugar» (P12): la portada con la ruedita mientras trae tu partida de la TV; luego el juego (`GamePlayView`).
/// `close(nil)` si lo cierras antes; si no, cómo saliste. `-demo-game-hold` se queda en la ruedita para la captura.
struct GameLaunchView: View {
    let game: GameItem
    let close: (GameExit?) -> Void
    @State private var ready = Demo.has("-demo-game-play")

    var body: some View {
        if ready {
            GamePlayView(game: game) { close($0) }
        } else {
            ZStack {
                GameArt(title: game.title, showsTitle: false).opacity(DS.Opacity.faint).ignoresSafeArea()
                VStack(spacing: DS.Space.s4) {
                    ProgressView().dsControlSize(.large).tint(DS.paper)   // ds-exception: la carga de un juego va a pantalla completa sobre su portada, como la del reproductor
                    Text(game.title).recipe(.title, color: DS.paper)
                    Text(game.save == .notShared ? "Abriendo el juego…" : "Trayendo tu partida de la TV…").recipe(.secondary, color: DS.onArtSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(DS.Space.gutter)
            }
            .background(DS.backdropDeep)
            .overlay(alignment: .topLeading) {
                DSIconButton(symbol: "xmark", label: "Cerrar", size: .regular) { close(nil) }.padding(DS.Space.gutter)
            }
            .task {
                guard !Demo.has("-demo-game-hold") else { return }
                try? await Task.sleep(for: DS.Games.demoLaunch)
                ready = true
            }
        }
    }
}

