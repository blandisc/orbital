import SwiftUI
import OrbitalCore

/// Modo acompañante: el juego que corre en la consola. Su arte, cuánto llevas, si está en pausa (congelado al ir al
/// Inicio de Orbital) y tres acciones: volver al juego, ir al Inicio y cerrarlo (este pide confirmación).
struct GameNowCard: View {
    let game: OrbitalRemote.Game
    let busy: Bool
    let onResume: () -> Void
    let onHome: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterView(url: game.hero ?? game.cover, title: game.title, aspect: nil, bleed: true, maxPoints: DS.Image.bleed)
            LinearGradient(stops: [.init(color: .clear, location: DS.Deck.veilStart), .init(color: DS.scrimStrong, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s1) {
                    Circle().fill(game.paused ? DS.warning : DS.live).frame(width: DS.Companion.dot, height: DS.Companion.dot)
                    (game.paused ? Text("En pausa en la consola") : Text("Jugando en la consola")).recipe(.eyebrow, color: DS.onArtSecondary)
                }
                TitleLogo(url: game.logo, title: game.title).frame(maxHeight: DS.Size.captionLogo, alignment: .leading)
                if let started = game.started {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text("Llevas \(Strings.duration(Int(context.date.timeIntervalSince(started) / 60)))").recipe(.footnote, color: DS.onArtSecondary)
                    }
                }
                HStack(spacing: DS.Space.s2) {
                    Button(action: onResume) { Label("Volver al juego", systemImage: "play.fill").lineLimit(1).minimumScaleFactor(DS.Size.statScale).frame(maxWidth: .infinity) }
                        .dsPrimaryButton().controlSize(.large).disabled(busy)
                    DSIconButton(symbol: "house", label: "Ir al inicio", action: onHome).disabled(busy)
                    ConfirmIconButton(symbol: "xmark", prompt: "¿Cerrar el juego?", label: "Cerrar el juego", action: onClose)
                }
            }
            .onArt()
            .padding(DS.Space.s4)
        }
        .frame(height: DS.Companion.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Una tarjeta del carrusel del acompañante: su título con glifo y su contenido, todas del mismo alto.
struct CompanionPanel<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            // Sin ícono: las secciones de la app no llevan (la regla de `DSSectionHead`).
            Text(title).recipe(.cardTitle)
            content()
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s4)
        .frame(width: DS.Companion.panelWidth, height: DS.Companion.panelHeight, alignment: .topLeading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }
}

/// La consola mientras juegas: batería (y cuánto le queda), controles, Wi‑Fi, memoria (con «Cerrar» para la app que más
/// gasta) y el modo de energía.
struct ConsoleStatePanel: View {
    let state: OrbitalRemote.ConsoleState?
    let setPower: (String) -> Void
    let closeApp: (String) -> Void
    private var language: String { AppEnvironment.shared.services.appSettings.uiLanguage }

    var body: some View {
        CompanionPanel(title: "La consola") {
            if let s = state {
                if let percent = s.batteryPercent {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        HStack {
                            Text(verbatim: "\(percent) %").recipe(.section)
                            Spacer()
                            if s.plugged { Text("Cargando").recipe(.caption) }
                            else if let minutes = s.minutesLeft {
                                Text(verbatim: String(format: Strings.tr("%@ de batería", language: language), Strings.duration(minutes))).recipe(.caption)
                            }
                        }
                        ProgressView(value: Double(percent), total: 100).tint(percent <= DS.Companion.lowBattery ? DS.danger : DS.live)
                    }
                }
                HStack(spacing: DS.Space.s3) {
                    ForEach(Array(s.controllers.enumerated()), id: \.offset) { _, c in
                        Label { Text(verbatim: controllerName(c.kind)) } icon: { Image(systemName: batteryGlyph(c.battery)) }.recipe(.caption)
                    }
                    if let ssid = s.wifiSSID { Label { Text(verbatim: ssid) } icon: { Image(systemName: "wifi") }.recipe(.caption) }
                }
                if let free = s.freeGB {
                    HStack {
                        // El decimal en el idioma de la app («1,5» / «1.5»).
                        Text(verbatim: String(format: Strings.tr("%@ GB libres", language: language), free.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: language))))).recipe(.caption)
                        Spacer()
                        if let app = s.apps.first(where: \.closable) {
                            Button { closeApp(app.name) } label: { Text("Cerrar \(app.name)") }
                                .font(DS.TextRecipe.caption.font.weight(.semibold)).buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                }
                DSSegmented(options: [("efficiency", "Ahorro"), ("balanced", "Equilibrado"), ("performance", "Rendimiento")],
                            selection: Binding(get: { s.powerMode ?? "balanced" }, set: { setPower($0) }))
            } else {
                Text("Actualiza tu Orbital para ver la batería, los controles y la memoria.").recipe(.footnote)
            }
        }
    }

    private func controllerName(_ kind: String) -> String {
        switch kind { case "legion": "Legion"; case "xbox": "Xbox"; case "gamesir": "GameSir"; default: "Control" }
    }

    private func batteryGlyph(_ level: String) -> String {
        switch level { case "wired": "cable.connector"; case "full": "battery.100"; case "medium": "battery.50"; case "low": "battery.25"; default: "battery.0" }
    }
}

/// La guía: búsquedas listas para el juego que corre (YouTube, la web y, en Steam, las guías de su comunidad).
struct GuidePanel: View {
    let game: OrbitalRemote.Game
    @Environment(\.openURL) private var openURL

    var body: some View {
        CompanionPanel(title: "Guía") {
            Text("Para el jefe que te atoró o el objeto que no encuentras.").recipe(.footnote)
            link("Guías en YouTube", "play.rectangle", "https://www.youtube.com/results?search_query=" + query("guía"))
            link("Buscar en la web", "magnifyingglass", "https://www.google.com/search?q=" + query("guía"))
            if game.id.hasPrefix("steam:") {
                link("Guías de la comunidad de Steam", "person.3", "https://steamcommunity.com/app/\(game.id.dropFirst(6))/guides/")
            }
        }
    }

    private func query(_ extra: String) -> String {
        "\(game.title) \(extra)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? game.title
    }

    private func link(_ title: LocalizedStringKey, _ symbol: String, _ url: String) -> some View {
        Button { if let u = URL(string: url) { openURL(u) } } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered).controlSize(.small)
    }
}

/// Notas por juego («me quedé en el castillo, falta la llave»): se guardan en el iPhone y vuelven la próxima vez.
struct NotesPanel: View {
    @Binding var text: String
    var body: some View {
        CompanionPanel(title: "Notas") {
            TextField("Dónde te quedaste, qué te falta…", text: $text, axis: .vertical)
                .lineLimit(DS.Companion.noteLines, reservesSpace: true)
                .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.text)
                .padding(DS.Space.s2)
                .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
    }
}

/// Un temporizador de juego: avisa en el iPhone cuando se cumple (no cierra nada).
struct TimerPanel: View {
    let endsAt: Date?
    let start: (Int) -> Void
    let cancel: () -> Void

    var body: some View {
        CompanionPanel(title: "Temporizador") {
            if let endsAt, endsAt > .now {
                Text(timerInterval: Date.now...endsAt, countsDown: true).recipe(.title).monospacedDigit()
                Text("Te aviso al terminar; no cierro nada.").recipe(.caption)
                Button("Quitar", role: .destructive, action: cancel).buttonStyle(.bordered).controlSize(.small)
            } else {
                Text("¿Cuánto quieres jugar?").recipe(.footnote)
                FlowChips {
                    ForEach(DS.Companion.timerSteps, id: \.self) { m in PanelChip(title: Text(verbatim: Strings.duration(m)), selected: false) { start(m) } }
                }
            }
        }
    }
}

/// Los controles de un juego de emulador: qué botón de tu control es cada uno del sistema original (la distribución
/// habitual del emulador; si la cambiaste, manda la tuya).
struct ControlsPanel: View {
    let system: String
    var body: some View {
        CompanionPanel(title: "Controles") {
            if let map = Self.maps[system] {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    ForEach(map, id: \.0) { original, yours in
                        HStack { Text(verbatim: original).recipe(.footnote, color: DS.text); Spacer(); Text(verbatim: yours).recipe(.footnote) }
                    }
                }
                Text("La distribución habitual del emulador.").recipe(.caption, color: DS.textFaint)
            }
        }
    }

    static func supports(_ system: String) -> Bool { maps[system] != nil }

    /// Original → tu control (posición de Xbox / Legion Go: A abajo, B derecha, X izquierda, Y arriba).
    static let maps: [String: [(String, String)]] = [
        "gamecube": [("A", "A"), ("B", "X"), ("X", "B"), ("Y", "Y"), ("Z", "RB"), ("L · R", "LT · RT"), ("Start", "☰"), ("Stick C", "Stick derecho")],
        "switch": [("A", "B"), ("B", "A"), ("X", "Y"), ("Y", "X"), ("L · R", "LB · RB"), ("ZL · ZR", "LT · RT"), ("+ · −", "☰ · ⧉")],
        "ps2": [("✕", "A"), ("○", "B"), ("□", "X"), ("△", "Y"), ("L1 · R1", "LB · RB"), ("L2 · R2", "LT · RT"), ("Start · Select", "☰ · ⧉")],
        "psx": [("✕", "A"), ("○", "B"), ("□", "X"), ("△", "Y"), ("L1 · R1", "LB · RB"), ("L2 · R2", "LT · RT"), ("Start · Select", "☰ · ⧉")],
        "psp": [("✕", "A"), ("○", "B"), ("□", "X"), ("△", "Y"), ("L · R", "LB · RB"), ("Start · Select", "☰ · ⧉")],
        "gba": [("A", "B"), ("B", "A"), ("L · R", "LB · RB"), ("Start · Select", "☰ · ⧉")],
        "nds": [("A", "B"), ("B", "A"), ("X", "Y"), ("Y", "X"), ("L · R", "LB · RB"), ("Start · Select", "☰ · ⧉"), ("Pantalla táctil", "Stick derecho")],
    ]
}

/// El juego abierto en la consola, en el accesorio de la barra de pestañas (como lo que suena en la TV): su portada,
/// su nombre y cuánto llevas; tocarlo abre el acompañante.
struct GameAccessory: View {
    let game: OrbitalRemote.Game
    let open: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button(action: open) {
            HStack(spacing: DS.Space.s3) {
                PosterView(url: game.cover ?? game.hero, title: game.title, aspect: DS.Poster.aspect)
                    .frame(height: DS.Size.accessoryArt).clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: game.title).recipe(.cardTitle).lineLimit(1)
                    if placement != .inline {
                        (game.paused ? Text("En pausa en la consola") : Text("Jugando en la consola")).recipe(.footnote, color: game.paused ? DS.warning : DS.live).lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "gamecontroller").foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Abre el acompañante del juego"))
        .accessibilityIdentifier("game-accessory")
    }
}

/// Al cerrar un juego en la consola: el resumen de la sesión. El arte, cuánto jugaste esta vez y en total, las capturas y, si
/// se cerró solo o por falta de memoria, el aviso (para que sepas que no fuiste tú).
struct GameSessionSummary: View {
    let item: OrbitalRemote.InboxItem
    let done: () -> Void

    var body: some View {
        let session = item.played ?? .init(seconds: 0)
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            ZStack(alignment: .bottomLeading) {
                PosterView(url: session.art, title: "", aspect: DS.Poster.stillAspect)   // sin arte, liso (el nombre ya va encima)
                LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Eyebrow(text: Text("Sesión terminada"), accent: true, onArt: true)
                    Text(verbatim: item.title).recipe(.title, color: DS.paper).lineLimit(2)
                }
                .padding(DS.Space.s4)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            // En renglón; con letra grande, uno debajo del otro (las cifras no se parten).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s5) { stats(session) }
                VStack(alignment: .leading, spacing: DS.Space.s2) { stats(session) }
            }
            if session.crashed { DSNotice(text: "El juego se cerró solo: no fuiste tú. Si se repite, revisa sus ajustes en la consola.", tone: .warn) }
            else if session.lowMemory { DSNotice(text: "Se cerró por falta de memoria: cierra otras apps de la consola antes de volver a jugar.", tone: .warn) }
            Button(action: done) { Text("Listo").frame(maxWidth: .infinity) }.dsPrimaryButton().controlSize(.large)
        }
        .padding(DS.Space.s5)
    }

    @ViewBuilder private func stats(_ session: OrbitalRemote.InboxItem.Session) -> some View {
        stat(Text(verbatim: Strings.duration(Int(session.seconds / 60))), Text("esta vez"))
        if let total = session.totalSeconds, total > session.seconds {
            stat(Text(verbatim: Strings.duration(Int(total / 60))), Text("en total"))
        }
        if session.captures > 0 { stat(Text(verbatim: "\(session.captures)"), Text("capturas")) }
    }

    private func stat(_ value: Text, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            value.recipe(.title).monospacedDigit().fixedSize()
            label.recipe(.caption, color: DS.textMuted)
        }
        .accessibilityElement(children: .combine)
    }
}
