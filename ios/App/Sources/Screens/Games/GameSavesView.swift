import SwiftUI

/// Las partidas de un juego (P27): las últimas 10 que guardaste aquí o en la TV (E4-A) y tus guardados rápidos, que se
/// quedan en este iPhone (E3-A). Se puede regresar a cualquiera (P29). En el Duo abierto, la TV y el iPhone lado a lado.
struct GameSavesView: View {
    let id: String
    @Environment(GamesCatalog.self) private var catalog
    @State private var restoring: GameSnapshot?
    @State private var conflict = Demo.has("-demo-game-conflict")

    var body: some View {
        if let game = catalog.game(id) {
            let shots = GameSnapshot.demo(for: game)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                    GameSaveLine(save: game.save)
                    if WindowMetrics.roomy {
                        HStack(alignment: .top, spacing: DS.Space.s6) {
                            column(Text("Las que viajan"), shots.filter { !$0.quick })
                            column(Text("Rápidos, solo este iPhone"), shots.filter(\.quick))
                        }
                    } else {
                        column(Text("Las que viajan"), shots.filter { !$0.quick })
                        column(Text("Rápidos, solo este iPhone"), shots.filter(\.quick))
                    }
                    Text("Se guardan las últimas 10. Regresar a una no borra las demás.").recipe(.footnote, color: DS.textMuted)
                }
                .padding(.horizontal, DS.Space.gutter)
                .padding(.top, DS.Layout.screenTop)
                .padding(.bottom, DS.Layout.screenBottom)
            }
            .dsNavigationTitle("Partidas")
            .navigationSubtitle(Text(game.title))
            .appSheet(item: $restoring) { shot in GameRestorePrompt(game: game, shot: shot) { restoring = nil } }
            .appSheet(isPresented: $conflict) { GameConflictChoice(game: game) { conflict = false } }
            .onAppear { if Demo.has("-demo-game-restore") { restoring = shots.first } }
        }
    }

    private func column(_ title: Text, _ shots: [GameSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            DSSectionHead(title: title)
            if shots.isEmpty {
                Text("Todavía no hay. En la pausa, «Guardado rápido».").recipe(.footnote, color: DS.textMuted)
            }
            VStack(spacing: DS.Space.s1) {
                ForEach(shots) { shot in
                    DSRow(title: Text("\(shot.whenText) · \(shot.placeText)"),
                          detail: shot.current ? Text("\(shot.playedText) · la que juegas") : shot.playedText,
                          symbol: shot.place == .phone ? "iphone" : "tv", accessory: .chevron) { restoring = shot }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Un guardado: dónde se hizo, cuándo y cuánto llevabas. Se compara por lo jugado, no por la hora de cada aparato.
struct GameSavesRoute: Hashable { let id: String }

struct GameSnapshot: Identifiable, Hashable {
    enum Place: Hashable { case phone, tv }
    let id: Int
    let place: Place
    let hoursAgo: Int
    let minutesPlayed: Int
    var quick = false
    var current = false

    static func demo(for game: GameItem) -> [GameSnapshot] {
        let m = max(game.minutesPlayed, 90)
        return [
            .init(id: 0, place: .phone, hoursAgo: 2, minutesPlayed: m, current: true),
            .init(id: 1, place: .tv, hoursAgo: 26, minutesPlayed: m - 45),
            .init(id: 2, place: .phone, hoursAgo: 50, minutesPlayed: m - 80),
            .init(id: 3, place: .tv, hoursAgo: 120, minutesPlayed: max(5, m - 140)),
            .init(id: 4, place: .phone, hoursAgo: 1, minutesPlayed: m + 12, quick: true),
            .init(id: 5, place: .phone, hoursAgo: 3, minutesPlayed: m - 5, quick: true),
        ]
    }

    var whenText: Text {
        if hoursAgo < 24 { return Text("Hace \(Int(hoursAgo)) h") }
        let days = hoursAgo / 24
        return days == 1 ? Text("Ayer") : Text("Hace \(Int(days)) días")
    }

    var placeText: Text { place == .phone ? Text("En tu iPhone") : Text("En la TV") }

    var playedText: Text {
        let h = minutesPlayed / 60, m = minutesPlayed % 60
        return h == 0 ? Text("\(m) min jugados") : Text("\(h) h \(m) min jugados")
    }
}

/// Regresar a un guardado (P29): lo que llevas ahora no se pierde, queda en la lista.
private struct GameRestorePrompt: View {
    let game: GameItem
    let shot: GameSnapshot
    let close: () -> Void

    var body: some View {
        DSSheet(title: Text("¿Regresar a esta partida?"), subtitle: Text("\(shot.whenText) · \(shot.playedText)")) {
            Text("Lo que llevas ahora no se pierde: queda en la lista y puedes volver a él.").recipe(.body, color: DS.textMuted)
            Button(action: close) { Text("Regresar y jugar").frame(maxWidth: .infinity) }.dsPrimaryButton().dsControlSize(.large)
            Button(action: close) { Text("Ahora no").frame(maxWidth: .infinity) }.dsSecondaryButton().dsControlSize(.large)
        }
        .dsSheetContent()
        .fittedSheet()
    }
}

/// Cuando el iPhone y la TV avanzaron por separado (P28, S2-A: se pregunta). Primero lo jugado, luego dónde y cuándo.
struct GameConflictChoice: View {
    let game: GameItem
    let close: () -> Void

    var body: some View {
        DSSheet(title: Text("¿Con cuál sigues?"), subtitle: Text("Jugaste \(game.title) aquí y en la TV")) {
            HStack(alignment: .top, spacing: DS.Space.s2) {   // las dos opciones miden lo mismo
                option(symbol: "iphone", played: Text("9 h 40 min"), place: Text("En tu iPhone"), when: Text("Hoy"), primary: true)
                option(symbol: "tv", played: Text("9 h 5 min"), place: Text("En la TV"), when: Text("Ayer"), primary: false)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("La otra no se borra: queda en Partidas.").recipe(.footnote, color: DS.textMuted)
        }
        .dsSheetContent()
        .fittedSheet()
    }

    private func option(symbol: String, played: Text, place: Text, when: Text, primary: Bool) -> some View {
        Button(action: close) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Image(systemName: symbol).font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted)
                played.recipe(.cardTitle).lineLimit(1)
                Text("\(place) · \(when)").recipe(.secondary, color: DS.textMuted)
                if primary { Text("La más avanzada").recipe(.caption, color: DS.eyebrow) }
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dsCard(.row)
            .overlay {   // la más avanzada, marcada: es la que sugerimos
                if primary { RoundedRectangle(cornerRadius: DSCardLevel.row.radius, style: .continuous).strokeBorder(DS.accent, lineWidth: DS.Stroke.regular) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
