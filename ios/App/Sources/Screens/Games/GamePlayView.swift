import SwiftUI

/// Jugando (P13–P22). Lo dibuja cada app de motor con esta misma pieza (etapa 1) y, más adelante, «Orbital Juegos». Aquí, sin
/// motores, el juego es su portada. Cómo se acomoda:
/// - Consolas de TV de lado: el juego a todo lo alto; sin mando, botones medio transparentes encima (E2-A).
/// - Portátiles parado (y cualquiera con el Duo medio abierto, E1-A): el juego arriba y los botones abajo; el DS con sus dos
///   pantallas, una sobre otra o una en cada mitad.
/// - Duo cerrado: se puede, con el aviso de que se ve mejor abierto, una vez por partida (E5-A).
/// La pausa es de Orbital, igual en todas las consolas: el botón de inicio del mando o ☰ en la pantalla.
struct GamePlayView: View {
    let game: GameItem
    let exit: (GameExit) -> Void
    @State private var pads = GamePads()
    @State private var halfOpen = false
    @State private var paused = Demo.has("-demo-game-paused")
    @State private var outerNotice = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { box in
            let landscape = box.size.width > box.size.height
            ZStack {
                DS.video
                if halfOpen {
                    halves(box.size)
                } else if landscape {
                    sideways
                } else {
                    upright(box.size)
                }
                if paused { pause }
            }
            // De lado, arriba al centro (en las esquinas van los gatillos); parado, arriba a la derecha (al centro, la isla).
            .overlay(alignment: landscape ? .top : .topTrailing) {
                if !paused {
                    DSIconButton(symbol: "line.3.horizontal", label: "Pausa", size: .regular) { paused = true }
                        .opacity(pads.connected ? DS.Opacity.faint : 1)
                        .padding(DS.Space.s4)
                }
            }
            .overlay(alignment: .top) {
                if outerNotice { DSToastPill(text: "Se ve mejor con el Duo abierto").padding(.top, DS.Space.s4).transition(.opacity) }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .tracksDuoHalfOpen($halfOpen)
        // El iPhone vive en vertical; un juego gira libre. Las consolas de la TV abren de lado (como el reproductor) y las
        // portátiles parado; al salir, vuelve a vertical. En iPad, la Mac y el Duo abierto decide el sistema.
        .onAppear { Orientation.rotate(allowed: .allButUpsideDown, to: game.layout == .tv ? .landscape : .portrait) }
        .onDisappear { Orientation.rotate(allowed: .portrait, to: .portrait) }
        .task {
            guard WindowMetrics.duoOuter else { return }
            withAnimation(DS.Motion.base(reduceMotion)) { outerNotice = true }
            try? await Task.sleep(for: DS.Games.outerNoticeFor)
            withAnimation(DS.Motion.base(reduceMotion)) { outerNotice = false }
        }
    }

    /// De lado: el juego a lo alto y, sin mando, los botones encima.
    private var sideways: some View {
        GameScreen(game: game, aspect: game.layout == .tv ? DS.Games.tvAspect : DS.Games.gbaAspect)
            .overlay { if !pads.connected { GameTouchPad(layout: game.layout, over: true) } }
    }

    /// Parado: el juego arriba y los botones abajo (el iPhone es una Game Boy).
    private func upright(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            if game.layout == .dualScreen {
                // Las dos pantallas del DS, sin quitarle a los botones más de lo que les toca.
                let each = min(size.width / DS.Games.dsAspect, size.height * DS.Games.uprightGameShare / 2)
                GameScreen(game: game, aspect: DS.Games.dsAspect, label: "Pantalla de arriba").frame(height: each)
                GameScreen(game: game, aspect: DS.Games.dsAspect, label: "Pantalla táctil").frame(height: each)
            } else {
                // Parado, también las de la TV: el juego arriba y los botones abajo, sin taparlo; de lado, a todo lo ancho.
                let aspect = game.layout == .tv ? DS.Games.tvAspect : DS.Games.gbaAspect
                GameScreen(game: game, aspect: aspect).frame(height: size.width / aspect)
            }
            if pads.connected { Spacer(minLength: 0) } else { GameTouchPad(layout: game.layout, over: false) }
        }
        .padding(.top, DS.Space.s16)
    }

    /// Medio abierto: el juego en la mitad de arriba y, abajo, los botones (o la pantalla táctil del DS).
    private func halves(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            GameScreen(game: game, aspect: game.layout == .tv ? DS.Games.tvAspect : DS.Games.dsAspect,
                       label: game.layout == .dualScreen ? "Pantalla de arriba" : nil)
                .frame(height: size.height / 2)
            ZStack {
                if game.layout == .dualScreen {
                    GameScreen(game: game, aspect: DS.Games.dsAspect, label: "Pantalla táctil")
                    if !pads.connected { GameTouchPad(layout: .dualScreen, over: true, compact: true) }
                } else if !pads.connected {
                    GameTouchPad(layout: game.layout, over: false)
                }
            }
            .frame(height: size.height / 2)
        }
    }

    /// La pausa de Orbital: qué viaja a la TV y qué no. Con el Duo medio abierto, en la mitad de abajo; si no, al centro.
    private var pause: some View {
        ZStack(alignment: halfOpen ? .bottom : .center) {
            DS.scrim.ignoresSafeArea().onTapGesture { paused = false }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("\(game.title) · en pausa").recipe(.cardTitle)
                DSRow(title: Text("Seguir"), symbol: "play.fill") { paused = false }
                DSRow(title: Text("Guardar y salir"), detail: Text("Va a la TV"), symbol: "arrow.up.forward.app") { exit(.saved(game.save)) }
                DSRow(title: Text("Guardado rápido"), detail: Text("Solo este iPhone"), symbol: "bookmark") { paused = false }
                DSRow(title: Text("Ajustes del juego"), symbol: "slider.horizontal.3") {}
                DSRow(title: Text("Botones en pantalla"), detail: pads.connected ? Text("Apagados con mando") : Text("Prendidos"),
                      symbol: "circle.grid.cross") {}
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: DS.Games.pauseWidth)
            .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.xl, style: .continuous))
            .padding(DS.Space.s4)
        }
    }
}

/// Cómo se salió de un juego: guardando (con cómo quedó la partida) o porque se cerró solo.
enum GameExit: Hashable { case saved(GameItem.Save), crashed }

/// La imagen del juego. Sin motores todavía, su portada a la proporción de la consola.
private struct GameScreen: View {
    let game: GameItem
    let aspect: CGFloat
    var label: LocalizedStringKey?

    var body: some View {
        GameArt(title: game.title, showsTitle: false)
            .overlay { Text(label ?? LocalizedStringKey(game.title)).recipe(.title, color: DS.paper) }
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Los botones en pantalla, según la consola: palancas y gatillos en las de TV; cruceta, A, B, L, R, Select y Start en las
/// portátiles. `over`: encima del juego (medio transparentes); si no, en su propio espacio abajo.
private struct GameTouchPad: View {
    let layout: GameItem.Layout
    let over: Bool
    var compact = false

    var body: some View {
        VStack(spacing: DS.Space.s4) {
            HStack {
                shoulder(layout == .tv ? "L · ZL" : "L")
                Spacer()
                shoulder(layout == .tv ? "R · ZR" : "R")
            }
            HStack(alignment: .center) {
                VStack(spacing: DS.Space.s4) {
                    if layout == .tv { stick }
                    dpad
                }
                Spacer()
                VStack(spacing: DS.Space.s4) {
                    faces
                    if layout == .tv { stick }
                }
            }
            if !compact {
                HStack(spacing: DS.Space.s4) {
                    pill(layout == .tv ? "−" : "Select")
                    pill(layout == .tv ? "+" : "Start")
                }
            }
        }
        .padding(.horizontal, DS.Space.s6)
        .padding(.vertical, over ? DS.Space.s4 : DS.Space.s6)
        .frame(maxHeight: .infinity, alignment: over ? .bottom : .center)
        .opacity(over ? DS.Games.padSeeThrough : 1)
        .accessibilityHidden(true)   // son controles del juego; VoiceOver no juega
    }

    private var stick: some View {
        Circle().fill(DS.fillStrong).frame(width: DS.Games.padStick, height: DS.Games.padStick)
            .overlay { Circle().fill(DS.fill).padding(DS.Space.s6) }
    }

    private var dpad: some View {
        let arm = DS.Games.padDpad / 3
        return ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(DS.fillStrong).frame(width: arm, height: DS.Games.padDpad)
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(DS.fillStrong).frame(width: DS.Games.padDpad, height: arm)
        }
    }

    /// Cuatro botones (X, Y, A, B) en las de la TV y el DS; la Game Boy solo tiene B y A, en diagonal como la de verdad.
    @ViewBuilder private var faces: some View {
        let b = DS.Games.padButton
        if layout == .portable {
            ZStack {
                face("B").offset(x: -b / 2, y: b / 3)
                face("A").offset(x: b / 2 + DS.Space.s2, y: -b / 3)
            }
            .frame(width: b * 3, height: b * 2)
        } else {
            ZStack {
                face("X").offset(y: -b)
                face("Y").offset(x: -b)
                face("A").offset(x: b)
                face("B").offset(y: b)
            }
            .frame(width: b * 3, height: b * 3)
        }
    }

    private func face(_ letter: String) -> some View {
        Circle().fill(DS.fillStrong).frame(width: DS.Games.padButton, height: DS.Games.padButton)
            .overlay { Text(verbatim: letter).recipe(.labelLarge, color: DS.paper) }
    }

    private func shoulder(_ text: String) -> some View {
        Text(verbatim: text).recipe(.label, color: DS.paper)
            .frame(width: DS.Games.padShoulder.width, height: DS.Games.padShoulder.height)
            .background(DS.fillStrong, in: .rect(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private func pill(_ text: String) -> some View {
        Text(verbatim: text).recipe(.label, color: DS.paper)
            .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s1)
            .background(DS.fillStrong, in: .capsule)
    }
}
