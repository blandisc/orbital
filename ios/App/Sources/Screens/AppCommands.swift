import SwiftUI
import OrbitalModels

/// La barra de menús (iPad con teclado desde iPadOS 26 y la Mac): cada atajo de teclado tiene aquí su camino visible, como
/// en la app de escritorio. Sin teclado no se ve y no cambia nada. Las acciones son las mismas que tocan los botones.
struct AppCommands: Commands {
    @FocusedValue(\.playerCommands) private var player
    @FocusedValue(\.titleCommands) private var title

    var body: some Commands {
        CommandMenu("Ir") {
            Button("Inicio") { open(tab: 0) }.keyboardShortcut("1")
            Button("Explorar") { open(tab: 1) }.keyboardShortcut("2")
            Button("Biblioteca") { open(tab: AppEnvironment.downloadsTab) }.keyboardShortcut("3")   // donde la dejaste
            Button("Buscar") { open(tab: 2); AppEnvironment.shared.ui.focusSearch = true }.keyboardShortcut("f")
            Divider()
            Button("Atrás") { AppEnvironment.shared.ui.goBack = true }.keyboardShortcut("[")
            // La Mac no controla tu Orbital (29 oct 2026): sin «Control de la TV» ni ⌘R. iPad con teclado, igual que antes.
            if ThisDevice.capabilities.console {
                Divider()
                Button("Control de la TV") { AppEnvironment.shared.ui.openRemote = true }.keyboardShortcut("r")
            }
        }
        // «Ajustes…» con ⌘, en el menú de la app, donde todo usuario de Mac lo busca.
        CommandGroup(replacing: .appSettings) {
            Button("Ajustes…") { AppEnvironment.shared.ui.openSettings = true }.keyboardShortcut(",")
        }
        // La ficha abierta: lo mismo que sus tres botones principales, con teclado y desde el menú (iPad y Mac).
        CommandMenu("Título") {
            Group {
                Button("Ver o continuar") { title?.play() }.keyboardShortcut(.return, modifiers: .command)
                Button("Guardar en una lista…") { title?.save() }.keyboardShortcut("d")
                Button("Elegir versión…") { title?.versions() }.keyboardShortcut("v", modifiers: [.command, .option])
            }
            .disabled(title == nil || player != nil)   // solo con una ficha a la vista (con el video abierto, manda el reproductor)
        }
        CommandMenu("Reproducción") {
            Group {
                Button("Reproducir o pausar") { player?.togglePlay() }.keyboardShortcut(.space, modifiers: [])
                Button("Atrás 10 segundos") { player?.skip(false) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Adelante 10 segundos") { player?.skip(true) }.keyboardShortcut(.rightArrow, modifiers: [])
                Divider()
                Button("Audio y subtítulos") { player?.openDock() }.keyboardShortcut("l")
            }
            .disabled(player == nil)   // solo con el reproductor abierto (si no, la barra espaciadora es de quien escribe)
            // Esc solo existe con el video abierto: aunque estuviera apagado, el menú se quedaba con la tecla y Esc ya no
            // cerraba ninguna hoja («Guardar en…», «Versión») en el iPad con teclado ni en la Mac (10 nov 2026).
            if let player {
                Button("Cerrar el reproductor") { player.close() }.keyboardShortcut(.escape, modifiers: [])
            } else {
                Button("Cerrar el reproductor") {}.disabled(true)
            }
        }
    }

    private func open(tab: Int) {
        let ui = AppEnvironment.shared.ui
        if ui.playing != nil { return }   // con el reproductor abierto, primero se cierra (Esc)
        ui.openTab = tab
    }
}

/// Lo que el reproductor abierto deja hacer desde el menú y el teclado (lo publica `PlayerScreen`).
struct PlayerCommands: Equatable {
    var togglePlay: () -> Void
    var skip: (_ forward: Bool) -> Void
    var openDock: () -> Void
    var close: () -> Void
    /// Siempre «igual»: un valor enfocado que no es Equatable cuenta como cambiado en cada pasada del reproductor, y SwiftUI
    /// volvía a pintar Inicio, la ruleta y el reproductor sin parar (la ruleta de Los Simpson se quedaba en la imagen, al 100 %
    /// de CPU, iOS 27). Las funciones leen el estado por `@State`, así que un valor viejo sigue actuando bien.
    static func == (_: Self, _: Self) -> Bool { true }
}

// Lo que la ficha abierta deja hacer desde el menú y el teclado: `TitleCommands` (OrbitalModels), igual mientras es la misma
// ficha y distinto en cuanto cambia el título (revisión del 11 nov 2026; antes, siempre «igual»).

extension FocusedValues {
    @Entry var playerCommands: PlayerCommands?
    @Entry var titleCommands: TitleCommands?
}
