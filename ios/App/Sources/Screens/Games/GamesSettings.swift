import SwiftUI

/// Las páginas de Ajustes de juegos: la principal (P30), lo que ocupa cada juego en el iPhone (P31) y los botones en
/// pantalla (P32). `-demo-games-settings main|phone|buttons` abre una para la captura.
enum GamesSettingsRoute: String, Hashable {
    case main, phone, buttons

    @MainActor @ViewBuilder static func view(_ route: GamesSettingsRoute) -> some View {
        switch route {
        case .main: GamesSettingsView()
        case .phone: GamesOnPhoneView()
        case .buttons: GameButtonsSettings()
        }
    }
}

/// Ajustes › Juegos (P30): tu mando, cómo viajan tus partidas y cuánto ocupan los juegos.
struct GamesSettingsView: View {
    @Environment(GamesCatalog.self) private var catalog
    @State private var pads = GamePads()
    @AppStorage("games.autoSync") private var autoSync = true
    @AppStorage("games.cellular") private var cellular = false
    @AppStorage("games.autoRemove") private var autoRemove = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    (pads.connected ? Text(verbatim: pads.name ?? "") : Text("Ninguno")).foregroundStyle(DS.textMuted)
                } label: { Label("Mando", systemImage: "gamecontroller") }
                NavigationLink(value: GamesSettingsRoute.buttons) { Label("Botones en pantalla", systemImage: "circle.grid.cross") }
            } header: { Text("Cómo juegas") } footer: {
                Text("Con un mando conectado, los botones en pantalla se esconden solos.")
            }
            Section {
                Toggle("Llevar y traer tus partidas", isOn: $autoSync)
                Toggle("También con datos del celular", isOn: $cellular).disabled(!autoSync)
            } header: { Text("Tus partidas") } footer: {
                Text("Al abrir un juego se trae la de la TV y al salir se manda. Se guardan las últimas 10 de cada juego.")
            }
            Section {
                NavigationLink(value: GamesSettingsRoute.phone) {
                    LabeledContent("En tu iPhone") { Text(totalText).foregroundStyle(DS.textMuted) }
                }
                Toggle("Quitar los que no juegas en un mes", isOn: $autoRemove)
            } header: { Text("Espacio") } footer: {
                Text("Quitar un juego del iPhone no toca tus partidas: siguen en la TV.")
            }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .dsInlineTitle("Ajustes de juegos")
        .readableListWidth()
    }

    private var totalText: String {
        let bytes = Int64(catalog.onPhone.reduce(0) { $0 + $1.gigabytes } * 1_000_000_000)
        return bytes.formatted(.byteCount(style: .file))
    }
}

/// En tu iPhone (P31): cada juego que bajaste, cuánto ocupa y cuándo lo jugaste; deslizar para quitarlo.
struct GamesOnPhoneView: View {
    @Environment(GamesCatalog.self) private var catalog

    var body: some View {
        List {
            Section {
                ForEach(catalog.onPhone.sorted { $0.gigabytes > $1.gigabytes }) { game in
                    LabeledContent {
                        Text(game.sizeText).foregroundStyle(DS.textMuted)
                    } label: {
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            Text(game.title).foregroundStyle(DS.text)
                            Text("\(Text(game.console.name)) · \(game.lastPlayedText)").recipe(.caption, color: DS.textMuted)
                        }
                    }
                    .swipeActions {
                        Button("Quitar", systemImage: "trash", role: .destructive) { catalog.cancelDownload(game.id) }
                    }
                }
            } footer: { Text("Tus partidas se quedan en la TV aunque quites el juego.") }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .dsInlineTitle("En tu iPhone")
        .readableListWidth()
    }
}

/// Botones en pantalla (P32): qué tan transparentes, si vibran al tocarlos y si se esconden con mando.
struct GameButtonsSettings: View {
    @AppStorage("games.buttons.seeThrough") private var seeThrough = DS.Games.padSeeThrough
    @AppStorage("games.buttons.haptics") private var haptics = true
    @AppStorage("games.buttons.hideWithPad") private var hideWithPad = true

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("Qué tanto se ven")
                    Slider(value: $seeThrough, in: DS.Opacity.faint...1) {
                        Text("Qué tanto se ven")
                    } minimumValueLabel: { Image(systemName: "circle.dotted") } maximumValueLabel: { Image(systemName: "circle.fill") }
                }
                Toggle("Vibrar al tocarlos", isOn: $haptics)
                Toggle("Esconderlos con mando", isOn: $hideWithPad)
            } footer: {
                Text("Cada consola trae sus botones: palancas y gatillos en las de la TV; cruceta, A y B en las portátiles.")
            }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .dsInlineTitle("Botones en pantalla")
        .readableListWidth()
    }
}
