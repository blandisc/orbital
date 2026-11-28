import SwiftUI

/// Lo que puede salir mal al bajar un juego (P7: la TV no responde, no cabe) o al abrirlo (P26: sin la wifi de casa, o se
/// está jugando en la TV).
enum GameProblem: String, Identifiable {
    case tvDown = "tvdown", noSpace = "nospace", offline, tvPlaying = "tvplaying"
    var id: String { rawValue }
}

struct GameProblemPrompt: View {
    let problem: GameProblem
    let game: GameItem
    var free = 61
    let close: () -> Void

    var body: some View {
        DSSheet(title: title) {
            message.recipe(.body, color: DS.textMuted)
            Button(action: close) { Text(action).frame(maxWidth: .infinity) }.dsPrimaryButton().dsControlSize(.large)
            if problem == .offline || problem == .tvPlaying {
                Button(action: close) { Text("Ahora no").frame(maxWidth: .infinity) }.dsSecondaryButton().dsControlSize(.large)
            }
        }
        .dsSheetContent()
        .fittedSheet()
    }

    private var title: Text {
        switch problem {
        case .tvDown: Text("La TV no responde")
        case .noSpace: Text("No cabe")
        case .offline: Text("Estás fuera de casa")
        case .tvPlaying: Text("Se está jugando en la TV")
        }
    }
    private var message: Text {
        switch problem {
        case .tvDown: Text("Lo que ya bajó se queda. Prende Orbital en la TV y sigue donde iba.")
        case .noSpace: Text("\(game.title) necesita \(Int(game.gigabytes.rounded(.up))) GB y tienes \(Int(free)) libres. Quita juegos que ya no juegas; tus partidas se quedan en la TV.")
        case .offline: Text("Juegas con tu última partida de este iPhone. Si avanzaste en la TV desde entonces, eso no está aquí todavía.")
        case .tvPlaying: Text("Alguien juega \(game.title) en la TV. Si sigues aquí, al final te preguntamos con cuál partida te quedas.")
        }
    }
    private var action: LocalizedStringKey {
        switch problem {
        case .tvDown: "Reintentar"
        case .noSpace: "Ver qué quitar"
        case .offline, .tvPlaying: "Jugar aquí"
        }
    }
}

/// Al salir de un juego (P23): si tu partida ya está en la TV, si espera la wifi de casa o si no se pudo mandar.
struct GameExitToast: View {
    let exit: GameExit

    var body: some View {
        DSToastPill(text: text)
    }

    private var text: LocalizedStringKey {
        switch exit {
        case .saved(.synced): "Tu partida ya está en la TV"
        case .saved(.pending): "Tu partida se manda al llegar a casa"
        case .saved(.failed): "No se pudo mandar tu partida; sigue aquí"
        case .saved(.notShared): "Guardado en este iPhone"
        case .crashed: "El juego se cerró"
        }
    }
}

/// Si el juego se cierra solo (P24): tu partida está a salvo hasta el último guardado y se puede volver a abrir.
struct GameCrashPrompt: View {
    let game: GameItem
    let done: (_ again: Bool) -> Void

    var body: some View {
        DSSheet(title: Text("\(game.title) se cerró")) {
            Text("Tu partida está a salvo hasta tu último guardado. Si vuelve a pasar, revisa «Qué se sabe» en la ficha.")
                .recipe(.body, color: DS.textMuted)
            Button { done(true) } label: { Text("Volver a abrir").frame(maxWidth: .infinity) }.dsPrimaryButton().dsControlSize(.large)
            Button { done(false) } label: { Text("Ahora no").frame(maxWidth: .infinity) }.dsSecondaryButton().dsControlSize(.large)
        }
        .dsSheetContent()
        .fittedSheet()
    }
}

/// La primera vez que juegas en el iPhone (P10): tres cosas y listo. No se vuelve a mostrar.
struct GameFirstTimeGuide: View {
    let done: () -> Void

    var body: some View {
        DSSheet(title: Text("Antes de tu primer juego")) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                point("arrow.left.arrow.right", "Tu partida viaja sola", "Al abrir trae la de la TV; al salir la manda de regreso.")
                point("gamecontroller", "Con tu mando o en la pantalla", "Si conectas un mando, los botones en pantalla se esconden.")
                point("wifi", "Fuera de casa también", "Juegas igual; tu partida se manda cuando vuelvas a la wifi de casa.")
            }
            Button(action: done) { Text("Entendido").frame(maxWidth: .infinity) }.dsPrimaryButton().dsControlSize(.large)
        }
        .dsSheetContent()
        .fittedSheet()
    }

    private func point(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            Image(systemName: symbol).font(DS.TextRecipe.label.font).foregroundStyle(DS.primary).frame(width: DS.Space.s6)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).recipe(.labelLarge)
                Text(text).recipe(.secondary, color: DS.textMuted)
            }
        }
    }
}
