import SwiftUI

/// La ficha de un juego (P4–P9): dónde está, cómo va tu partida, cómo corre y cuánto llevas. «Jugar» si está aquí, «Bajar de
/// la TV» si no; mientras baja, cuánto falta y cancelar. Lo que no corre todavía dice por qué y deja intentarlo.
struct GameDetailView: View {
    let id: String
    @Environment(GamesCatalog.self) private var catalog
    @Environment(AppEnvironment.self) private var env
    @State private var launching = false
    @State private var problem: GameProblem?
    @State private var exitNote: GameExit?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var crashed = Demo.has("-demo-game-crash")
    @AppStorage("games.firstTimeDone") private var firstTimeDone = false
    @State private var firstTime = Demo.has("-demo-game-first")
    @State private var pads = GamePads()

    var body: some View {
        if let game = catalog.game(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                    hero(game)
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            Text(game.title).recipe(.title)
                            Text("\(Text(game.console.name)) · \(String(game.year)) · \(game.sizeText)").recipe(.secondary, color: DS.textMuted)
                        }
                        actions(game)
                        if game.place == .phone, game.playable {
                            NavigationLink(value: GameSavesRoute(id: game.id)) {
                                HStack { GameSaveLine(save: game.save); Image(systemName: "chevron.forward").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Abre tus partidas"))
                        }
                        if !game.playable {
                            GameStatusLine(symbol: "nosign", text: Text("Todavía no corre en el iPhone"))
                            if let note = game.note {
                                Text("\(Text(note)). Puedes intentarlo igual; tu partida de la TV no se toca.")
                                    .recipe(.body, color: DS.textMuted)
                            }
                        }
                        if let hint = game.versionHint { Text(hint).recipe(.footnote, color: DS.eyebrow) }
                        facts(game)
                        if game.place == .tv { Text("Se baja en casa, por wifi, aunque cierres Orbital; te avisa al terminar.").recipe(.footnote, color: DS.textMuted) }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                }
                .padding(.bottom, DS.Layout.screenBottom)
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $launching) {
                GameLaunchView(game: game) { how in
                    launching = false
                    if let how { finished(how) }
                }
                .environment(env).duoBars()
            }
            .appSheet(item: $problem) { GameProblemPrompt(problem: $0, game: game, free: catalog.freeGigabytes) { problem = nil } }
            .appSheet(isPresented: $crashed) { GameCrashPrompt(game: game) { again in crashed = false; if again { launching = true } } }
            .appSheet(isPresented: $firstTime) { GameFirstTimeGuide { firstTime = false; firstTimeDone = true; launching = true } }
            .overlay(alignment: .bottom) {
                if let exitNote { GameExitToast(exit: exitNote).padding(.bottom, DS.Space.s8).transition(.opacity) }
            }
            .onAppear {
                if let raw = Demo.value(after: "-demo-game-toast") { finished(.saved(GameItem.Save(rawValue: raw) ?? .synced)) }
                if let raw = Demo.value(after: "-demo-game-sheet") { problem = GameProblem(rawValue: raw) }
                if Demo.has("-demo-game-downloading") { catalog.downloadSample(game.id) }
                if Demo.has("-demo-game-launch") { launching = true }   // con -demo-game-hold o -demo-game-play
            }
        } else {
            DSEmptyState(symbol: "questionmark.square.dashed", title: Text("Ese juego ya no está en la TV")) { EmptyView() }
        }
    }

    /// La primera vez, antes del primer juego, qué pasa con tus partidas y el mando (P10); después, directo.
    private func play() { if firstTimeDone { launching = true } else { firstTime = true } }

    /// Al salir de un juego se regresa a su ficha (S1-A) con cómo quedó tu partida (P23), o la hoja de «se cerró» (P24).
    private func finished(_ how: GameExit) {
        if how == .crashed { crashed = true; return }
        if case .saved(let save) = how { catalog.setSave(id, save) }
        withAnimation(DS.Motion.base(reduceMotion)) { exitNote = how }
        guard !Demo.has("-demo-game-toast") else { return }   // en la captura se queda
        Task {
            try? await Task.sleep(for: DS.Games.exitNoteFor)
            withAnimation(DS.Motion.base(reduceMotion)) { exitNote = nil }
        }
    }

    private func hero(_ game: GameItem) -> some View {
        GameArt(title: game.title, showsTitle: false)
            .frame(height: min(WindowMetrics.column.width * DS.Games.heroShare, DS.Games.heroMax))
            .overlay { LinearGradient(colors: [.clear, DS.bg], startPoint: .center, endPoint: .bottom) }
            .opacity(game.playable ? 1 : DS.Games.unavailable)
    }

    @ViewBuilder private func actions(_ game: GameItem) -> some View {
        HStack(spacing: DS.Space.s2) {
            switch game.place {
            case .phone:
                if game.playable {
                    Button(action: play) { Label("Jugar", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .dsPrimaryButton().dsControlSize(.large)
                } else {
                    Button(action: play) { Text("Intentar de todos modos").frame(maxWidth: .infinity) }
                        .dsGlassButton().dsControlSize(.large)
                }
            case .tv:
                if game.playable {
                    Button { download(game) } label: { Label("Bajar de la TV", systemImage: "arrow.down").frame(maxWidth: .infinity) }
                        .dsPrimaryButton().dsControlSize(.large)
                } else {
                    // E6-A: lo que no corre se puede intentar, pero no se ofrece como la acción principal.
                    Button { download(game) } label: { Label("Bajar para intentarlo", systemImage: "arrow.down").frame(maxWidth: .infinity) }
                        .dsGlassButton().dsControlSize(.large)
                }
            case .downloading(let done):
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ProgressView(value: done).tint(DS.text)
                    Text("\(GameItem.sizeText(game.gigabytes * done)) de \(game.sizeText) · faltan \(max(1, Int((1 - done) * 8))) min")
                        .recipe(.data, color: DS.textMuted)
                    Button("Cancelar") { catalog.cancelDownload(game.id) }.dsSecondaryButton().dsControlSize(.regular)
                }
            }
            if case .downloading = game.place {} else {
                DSIconButton(symbol: game.favorite ? "heart.fill" : "heart", label: game.favorite ? "Quitar de Favoritos" : "Agregar a Favoritos") {
                    catalog.toggleFavorite(game.id)
                }
                DSMoreMenu {
                    if game.place == .phone { Button("Quitar del iPhone", systemImage: "trash", role: .destructive) { catalog.cancelDownload(game.id) } }
                    if game.playable { NavigationLink(value: GameSavesRoute(id: game.id)) { Label("Partidas", systemImage: "clock.arrow.circlepath") } }
                    NavigationLink(value: GamesSettingsRoute.buttons) { Label("Botones en pantalla", systemImage: "circle.grid.cross") }
                }
            }
        }
    }

    /// Lo que conviene saber antes de jugar, en renglones.
    private func facts(_ game: GameItem) -> some View {
        VStack(spacing: 0) {
            GameFact(label: "Dónde", value: game.place == .phone ? Text("En tu iPhone") : Text("En la TV"))
            if game.place == .tv {
                GameFact(label: "Necesita", value: Text("\(Int(game.gigabytes.rounded(.up))) GB · tienes \(Int(catalog.freeGigabytes)) libres"))
            }
            if game.minutesPlayed > 0 {
                GameFact(label: "Jugado", value: game.place == .phone ? game.playedText : Text("\(game.playedText) en la TV"))
            }
            if game.playable {
                GameFact(label: "Cómo corre", value: game.runsText)
                if let note = game.note { GameFact(label: "Qué se sabe", value: Text(note)) }
            }
            if game.needsFastMode { GameFact(label: "Al abrir", value: Text("Pide el modo rápido")) }
            if game.place == .phone {
                GameFact(label: "Mando", value: pads.connected ? Text("\(Text(verbatim: pads.name ?? "")) · conectado") : Text("Botones en pantalla"))
            }
        }
    }

    private func download(_ game: GameItem) {
        if game.gigabytes > Double(catalog.freeGigabytes) { problem = .noSpace; return }
        catalog.download(game.id)
    }
}

extension GameItem {
    /// «Va bien», «Con MeloNX · Con fallas», con de dónde sale si es un dato real.
    var runsText: Text {
        let base: Text = switch runs { case .good: Text("Va bien"); case .issues: Text("Con fallas"); case .notYet: Text("No corre todavía") }
        if let runsSource { return Text("\(base) (\(Text(runsSource)))") }
        return base
    }
}

/// Un renglón de datos: el nombre a la izquierda y el valor a la derecha.
private struct GameFact: View {
    let label: LocalizedStringKey
    let value: Text

    var body: some View {
        LabeledContent {
            value.recipe(.labelLarge, color: DS.text).multilineTextAlignment(.trailing)
        } label: {
            Text(label).recipe(.secondary, color: DS.textMuted)
        }
        .padding(.vertical, DS.Space.s2)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: DS.Stroke.hairline) }
    }
}

/// Una línea de estado con su ícono (P4).
struct GameStatusLine: View {
    let symbol: String
    let text: Text

    var body: some View {
        Label { text.recipe(.label, color: DS.textMuted) } icon: { Image(systemName: symbol).font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted) }
    }
}

/// Cómo va tu partida con la TV (P25): un punto y una frase.
struct GameSaveLine: View {
    let save: GameItem.Save

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Circle().fill(dot).frame(width: DS.Games.statusDot, height: DS.Games.statusDot)
                .overlay { if save == .notShared || save == .failed { Circle().strokeBorder(ring, lineWidth: DS.Stroke.regular) } }
            text.recipe(.label, color: DS.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private var text: Text {
        switch save {
        case .synced: Text("Partida al día con la TV")
        case .pending: Text("Va a la TV cuando vuelvas a casa")
        case .failed: Text("No se pudo mandar · se reintenta solo")
        case .notShared: Text("Esta consola todavía no comparte partidas")
        }
    }
    private var dot: Color { switch save { case .synced: DS.text; case .pending: DS.warning; case .failed, .notShared: .clear } }
    private var ring: Color { save == .failed ? DS.warning : DS.textMuted }
}

