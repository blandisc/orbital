import SwiftUI

/// Tus juegos en el iPhone (Ultra): el catálogo de la TV más lo que ya está aquí. Por ahora con datos de muestra
/// (`GamesCatalog.demo`): las pantallas se aprueban antes de conectar la TV y los motores
/// (`docs/producto/emulacion-iphone/plan-pantallas.html`, P1–P32).
struct GameConsole: Identifiable, Hashable, Sendable {
    let id: String
    let name: LocalizedStringResource

    static func == (a: GameConsole, b: GameConsole) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

extension GameConsole {
    static let nintendoSwitch = GameConsole(id: "switch", name: "Switch")
    static let gamecube = GameConsole(id: "gamecube", name: "GameCube")
    static let wii = GameConsole(id: "wii", name: "Wii")
    static let portables = GameConsole(id: "portables", name: "Portátiles")
    static let xbox = GameConsole(id: "xbox", name: "Xbox")
    static let xbox360 = GameConsole(id: "xbox360", name: "Xbox 360")
    static let ps4 = GameConsole(id: "ps4", name: "PS4")
    static let all: [GameConsole] = [nintendoSwitch, gamecube, wii, portables, xbox, xbox360, ps4]
}

struct GameItem: Identifiable, Hashable {
    /// Dónde está el juego: en este iPhone, en la TV o bajando.
    enum Place: Hashable { case phone, tv, downloading(Double) }
    /// Cómo corre en este iPhone (M1-A): lo que reportan otros con tu iPhone o lo que probamos.
    enum Runs: Hashable { case good, issues, notYet }
    /// Cómo va tu partida con la TV (S1-A).
    enum Save: String, Hashable { case synced, pending, failed, notShared }

    let id: String
    let title: String
    let console: GameConsole
    let year: Int
    let gigabytes: Double
    var place: Place
    let minutesPlayed: Int
    let runs: Runs
    /// Lo que se sabe de cómo corre («A veces hay que abrirlo varias veces»).
    var note: LocalizedStringKey?
    /// Pide el modo rápido de iOS (los motores con JIT).
    let needsFastMode: Bool
    var save: Save
    var favorite: Bool
    /// Días desde la última vez que se jugó (aquí o en la TV); sin jugar, nil.
    let lastPlayedDays: Int?
    let addedDays: Int
    /// Con nxnative pide una versión exacta; si tu copia es otra, corre con MeloNX (P8).
    var versionHint: LocalizedStringKey?
    /// De dónde sale «Cómo corre» cuando es un dato real (Xbox 360).
    var runsSource: LocalizedStringKey?
    /// Dos pantallas (DS): una sobre otra parado, y una en cada mitad del Duo medio abierto.
    var dualScreen = false

    static func == (a: GameItem, b: GameItem) -> Bool { a.id == b.id && a.place == b.place && a.favorite == b.favorite && a.save == b.save }
    func hash(into h: inout Hasher) { h.combine(id) }

    var playable: Bool { runs != .notYet }

    /// Cómo se juega: las consolas de TV de lado; las portátiles parado, como una Game Boy.
    enum Layout { case tv, portable, dualScreen }
    var layout: Layout { dualScreen ? .dualScreen : console == .portables ? .portable : .tv }
}

/// Los órdenes de una consola: los de la TV y, solo aquí, «En tu iPhone».
enum GameOrder: String, CaseIterable, Hashable {
    case recent, added, favorites, az, unplayed, onPhone
    var title: LocalizedStringKey {
        switch self {
        case .recent: "Recientes"; case .added: "Añadidos"; case .favorites: "Favoritos"; case .az: "A–Z"
        case .unplayed: "Sin jugar"; case .onPhone: "En tu iPhone"
        }
    }
    func apply(_ games: [GameItem]) -> [GameItem] {
        switch self {
        case .recent: games.sorted { ($0.lastPlayedDays ?? .max) < ($1.lastPlayedDays ?? .max) }
        case .added: games.sorted { $0.addedDays < $1.addedDays }
        case .favorites: games.filter(\.favorite)
        case .az: games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .unplayed: games.filter { $0.minutesPlayed == 0 }
        case .onPhone: games.filter { $0.place == .phone }
        }
    }
}

@MainActor @Observable
final class GamesCatalog {
    var games: [GameItem]
    /// La TV respondió y hay catálogo (sin ella y sin nada bajado: P3).
    var reachable: Bool

    init(games: [GameItem], reachable: Bool = true) { self.games = games; self.reachable = reachable }

    var onPhone: [GameItem] { games.filter { $0.place == .phone } }
    var recent: [GameItem] { Array(GameOrder.recent.apply(games.filter { $0.lastPlayedDays != nil }).prefix(6)) }
    var favorites: [GameItem] { games.filter(\.favorite) }
    func games(of console: GameConsole) -> [GameItem] { games.filter { $0.console == console } }
    func game(_ id: String) -> GameItem? { games.first { $0.id == id } }

    func toggleFavorite(_ id: String) {
        guard let i = games.firstIndex(where: { $0.id == id }) else { return }
        games[i].favorite.toggle()
    }

    /// Bajar de la TV: en la muestra avanza solo hasta quedar en el iPhone.
    func download(_ id: String) {
        guard let i = games.firstIndex(where: { $0.id == id }) else { return }
        games[i].place = .downloading(0)
        Task { @MainActor [weak self] in
            for step in 1...20 {
                try? await Task.sleep(for: DS.Games.demoDownloadStep)
                guard let self, let j = self.games.firstIndex(where: { $0.id == id }), case .downloading = self.games[j].place else { return }
                self.games[j].place = step == 20 ? .phone : .downloading(Double(step) / 20)
            }
        }
    }

    func cancelDownload(_ id: String) {
        guard let i = games.firstIndex(where: { $0.id == id }) else { return }
        games[i].place = .tv
    }
}

extension GamesCatalog {
    /// La muestra de las pantallas: tus juegos de Switch, God of War III, tus dos de Xbox 360 y algunos más (ejemplos).
    static func demo() -> GamesCatalog {
        func game(_ id: String, _ title: String, _ console: GameConsole, _ year: Int, _ gb: Double, _ place: GameItem.Place,
                  played: Int, runs: GameItem.Runs = .good, fast: Bool = false, save: GameItem.Save = .synced,
                  favorite: Bool = false, last: Int? = nil, added: Int = 30, note: LocalizedStringKey? = nil,
                  version: LocalizedStringKey? = nil, source: LocalizedStringKey? = nil) -> GameItem {
            GameItem(id: id, title: title, console: console, year: year, gigabytes: gb, place: place, minutesPlayed: played,
                     runs: runs, note: note, needsFastMode: fast, save: save, favorite: favorite, lastPlayedDays: last,
                     addedDays: added, versionHint: version, runsSource: source)
        }
        func withTwoScreens(_ g: GameItem) -> GameItem { var g = g; g.dualScreen = true; return g }
        let s = GameConsole.nintendoSwitch
        return GamesCatalog(games: [
            game("lm3", "Luigi's Mansion 3", s, 2019, 7.1, .phone, played: 580, favorite: true, last: 0, added: 40),
            game("mk8", "Mario Kart 8 Deluxe", s, 2017, 13.4, .phone, played: 1210, favorite: true, last: 3, added: 90),
            game("smo", "Super Mario Odyssey", s, 2017, 5.7, .phone, played: 0, runs: .issues, fast: true, added: 2,
                 version: "Tu copia es la 1.3.0. Con la 1.4.1 correría preparado en la Mac: más rápido y más fresco."),
            game("spl3", "Splatoon 3", s, 2022, 6.2, .tv, played: 95, runs: .issues, fast: true, last: 12, added: 60,
                 note: "Baja de velocidad en las partidas grandes"),
            game("kf2", "Kirby Fighters 2", s, 2020, 1.4, .tv, played: 0, runs: .notYet, fast: true, added: 70,
                 note: "Abre, pero se cierra en el primer combate"),
            game("gow3", "God of War III Remastered", .ps4, 2015, 34.6, .tv, played: 342, fast: true, favorite: true, last: 3, added: 9),
            game("bo2", "Call of Duty: Black Ops II", .xbox360, 2012, 8.0, .tv, played: 210, fast: true, last: 19, added: 25,
                 note: "A veces hay que abrirlo varias veces", source: "Un reporte en iPhone"),
            game("dante", "Dante's Inferno", .xbox360, 2010, 6.8, .tv, played: 0, fast: true, added: 25, source: "Un reporte en iPhone"),
            game("ww", "The Wind Waker", .gamecube, 2002, 1.4, .phone, played: 800, fast: true, favorite: true, last: 0, added: 120),
            game("mp", "Metroid Prime", .gamecube, 2002, 1.4, .tv, played: 0, fast: true, added: 15),
            game("halo", "Halo 2", .xbox, 2004, 4.2, .tv, played: 60, fast: true, save: .notShared, last: 40, added: 200),
            game("mkwii", "Mario Kart Wii", .wii, 2008, 2.8, .tv, played: 300, fast: true, last: 30, added: 300),
            game("emerald", "Pokémon Esmeralda", .portables, 2004, 0.016, .phone, played: 1500, favorite: true, last: 5, added: 400),
            withTwoScreens(game("mkds", "Mario Kart DS", .portables, 2005, 0.032, .phone, played: 120, last: 8, added: 400)),
        ])
    }
}
