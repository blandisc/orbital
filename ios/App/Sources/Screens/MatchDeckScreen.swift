import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Una por una», el mazo de «Decide por mí» (DE2: antes «¿Qué vemos hoy?», su propia pantalla): en medio el mazo (con los
/// datos de la de arriba debajo de su carta) y abajo Paso · Para hoy · Guardar · Ver. `pool`: lo que deja pasar «Afinar».
/// Tocar una carta abre su ficha (`onOpenTitle`); «Ver» avisa con `onPlay` para que la pantalla de afuera la reproduzca. Vive dentro de la hoja de «Decide por mí», que pone el encabezado,
/// la ✕ y los filtros (los mismos de «Tres que caben»).
struct MatchDeckScreen: View {
    /// El mazo lo guarda la hoja (vive mientras la hoja está abierta, aunque cambies de pestaña).
    @Binding var model: MatchDeckModel?
    /// La que va arriba (el cartel elegido en «Tres que caben»), si está en el mazo.
    var lead: String?
    /// Cartel → carta: la de arriba comparte su lugar con el cartel del mismo título (`DecideView.heroKey`).
    var hero: Namespace.ID?
    let pool: [Suggestion]
    /// Cambia cuando cambian los filtros: el mazo se vuelve a barajar con `pool`.
    var poolKey = ""
    /// Hay filtros puestos en «Afinar»: sin cartas, se dice que es por ellos.
    var filtered = false
    /// «Reintentar» sin red: lo que se sugiere, pedido otra vez (F2/F8).
    var reload: (() async -> [Suggestion])?
    /// Cuántas cartas quedan de verdad (sin lo visto, guardado ni pasado): la cuenta junto al título dice esto, no el montón.
    var onCount: ((Int) -> Void)?
    let onOpenTitle: (TitleRoute) -> Void
    let onPlay: (TitleRoute) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lo que pidió un botón (la carta sale volando igual que al arrastrarla).
    @State private var command: MatchCommand?
    /// Lo que trajo «Reintentar» (si no, `pool`).
    @State private var reloaded: [Suggestion]?
    /// Hacia dónde va la carta de arriba: los botones se encienden de su color.
    @State private var pull = MatchPull()
    /// El saltito del símbolo de cada botón cuando la carta sale por él (con el botón o con el dedo).
    @State private var kicks: [MatchCommand: Int] = [:]
    private var items: [Suggestion] { reloaded ?? pool }

    var body: some View {
        // La cuenta se lee aquí, no dentro del encabezado: en iOS 27 el encabezado no se volvía a pintar al guardar (su
        // cierre leía el modelo sin seguirlo) y la cuenta nunca aparecía.
        let savedCount = model.map { $0.track(); return $0.saved.count } ?? 0
        let savesToTrakt = model?.savesToTrakt ?? false
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            if savedCount > 0 { savedBadge(savedCount, savesToTrakt) }
            if let model {
                let _ = model.track()
                if !model.loaded {
                    skeleton   // mientras llega lo visto: la forma de la carta, no una pantalla en blanco
                } else if model.cards.isEmpty {
                    emptyState(model).frame(maxHeight: .infinity).overlay(alignment: .bottom) { deckNotices }   // la última que guardaste
                } else {
                    // La carta cede (Fernando, 13 nov 2026: «los botones se comen, se cortan con la tarjeta»): los botones y sus
                    // nombres apartan su alto primero, los datos de la carta el suyo (`MatchDeckLayout`) y la carta toma lo que
                    // sobra, con la forma de su póster. Igual con letra grande (antes ahí el mazo se deslizaba a un alto fijo y
                    // los botones quedaban fuera de la pantalla). Regla «En una hoja, lo que crece cede ante los controles».
                    deck(model).frame(maxHeight: .infinity).layoutPriority(-1).overlay(alignment: .bottom) { deckNotices }
                    actions(model)
                }
            } else {
                skeleton
            }
        }
        // «Guardada en Tu match perfecto · Deshacer» al momento (el mazo tapa la raíz, que es donde van los avisos, y antes
        // salía hasta cerrarlo); va abajo, encima de Paso · Para hoy · Guardar · Ver (`deckNotices`).
        .animation(DS.Motion.enter(reduceMotion), value: env.notices.current?.serial)
        .onChange(of: lead) { model?.lead = lead }
        .onChange(of: poolKey) { reloaded = nil; Task { await model?.replacePool(pool) } }
        .onChange(of: model.map { $0.loaded ? $0.cards.count : -1 }, initial: true) { _, count in if let count, count >= 0 { onCount?(count) } }
        .task {
            if model == nil {
                let m = MatchDeckModel(env.services, pool: items, titles: env.titles, watched: { [env] in await env.collections.watchedIDs() })
                m.lead = lead
                model = m
                await m.load()
            }
        }
        // Las cartas que siguen, pedidas de antemano: al aventar una, la de abajo ya trae su póster (antes llegaba en blanco).
        .task(id: model?.cards.prefix(DS.Match.prefetch).map(\.imdb)) {
            guard let model else { return }
            ImagePipeline.shared.prefetchPosters(model.cards.prefix(DS.Match.prefetch).map(\.poster))
        }
        .accessibilityElement(children: .contain)   // cada botón conserva su identificador
        .accessibilityIdentifier("match-deck")
    }

    private func deck(_ model: MatchDeckModel) -> some View {
        MatchDeck(cards: model.cards,
                  genres: { Vocabulary.genres($0.genres, language: env.services.appSettings.uiLanguage) },
                  command: $command,
                  pull: pull,
                  hero: hero,
                  onSave: { s in save(s, model) },
                  onDiscard: { s in discard(s, model) },
                  onTonight: { s in tonight(s, model) },
                  onOpen: { s in onOpenTitle(s.route) })
    }

    /// Cuántas llevas guardadas en esta vuelta (en «Tu match perfecto» de Trakt, o en Mi lista).
    private func savedBadge(_ savedCount: Int, _ savesToTrakt: Bool) -> some View {
        Label { Text(verbatim: "\(savedCount)").monospacedDigit() } icon: { Image(systemName: "bookmark.fill") }
            .recipe(.label, color: DS.text).tint(DS.brandMoon)
            .padding(.horizontal, DS.Space.s3).frame(minHeight: DS.Size.touchTarget)
            .background(DS.fill, in: Capsule())
            .contentTransition(.numericText())
            .accessibilityLabel(savesToTrakt ? Text("\(savedCount) guardadas en Tu match perfecto") : Text("\(savedCount) guardadas en Mi lista"))
            .accessibilityIdentifier("match-saved-count")
    }

    /// La carta en gris mientras carga.
    private var skeleton: some View {
        RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous).fill(DS.fill)   // ds-exception: esqueleto con la forma de la carta, no una caja
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text("Cargando"))
    }

    /// Sin cartas, con el porqué: sin red («Reintentar»), por los filtros de «Afinar», o porque ya las recorriste (como el
    /// aviso de Tinder cuando se acaban los matches, Fernando, 3 nov 2026).
    @ViewBuilder private func emptyState(_ model: MatchDeckModel) -> some View {
        if filtered, env.isOnline, items.isEmpty || model.saved.isEmpty {
            // Con filtros: no hay ninguna (o las que cumplen ya las viste, las guardaste o las pasaste). Antes decía «Se
            // acabaron tus matches» con «27 opciones» arriba sin haber visto ninguna.
            DSEmptyState(symbol: DS.Symbol.decide, title: Text("Ninguna con estos filtros"), message: Text("Prueba quitando un filtro."))
                .accessibilityIdentifier("match-filtered")
        } else if items.isEmpty {
            // Sin red lo dice así, con «Reintentar» (F2/F8: antes «Aún no hay propuestas», como si no tuvieras sugerencias).
            let offline = !env.isOnline
            DSEmptyState(symbol: offline ? DS.Symbol.offline : "rectangle.stack", title: offline ? Text("Sin conexión") : Text("Aún no hay propuestas"),
                         message: offline ? Text("Cuando vuelva el internet, aquí salen tus cartas.") : Text("Cuando Para ti cargue sus listas, aquí salen.")) {
                if let reload {
                    Button { Task { let fresh = await reload(); reloaded = fresh; await model.replacePool(fresh) } } label: { Label("Reintentar", systemImage: "arrow.clockwise") }
                        .accessibilityIdentifier("match-retry")
                }
            }
        } else {
            let saved: Text? = model.saved.isEmpty ? nil : (model.savesToTrakt ? Text("Guardaste \(model.saved.count) en tu lista de Trakt «Tu match perfecto».") : Text("Guardaste \(model.saved.count) en Mi lista."))
            let hint = Text("Si quieres ver más, cambia tus filtros o vuelve mañana: el mazo cambia cada día.")
            DSEmptyState(symbol: "rectangle.stack", title: Text("Se acabaron tus matches"), message: saved.map { $0 + Text(verbatim: " ") + hint } ?? hint)
                .accessibilityIdentifier("match-empty")
        }
    }

    /// Guarda (en «Tu match perfecto» de Trakt o en Mi lista) y lo dice, con «Deshacer» (antes el «+» la guardaba sin avisar y no se sabía qué había pasado).
    private func save(_ s: Suggestion, _ model: MatchDeckModel) {
        kicks[.save, default: 0] += 1
        Task { await model.save(s) }
        env.notify(model.savesToTrakt ? "Guardada en Tu match perfecto" : "Guardada en Mi lista", detail: s.title, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {
            Task { await model.undo(s) }
        }
    }

    /// «Para hoy» (arriba o la ★): guardada y primero en Mi lista hoy; el aviso ofrece verla ya y deshacerlo (F5).
    private func tonight(_ s: Suggestion, _ model: MatchDeckModel) {
        kicks[.tonight, default: 0] += 1
        Task { await model.saveForTonight(s) }
        env.notify("Para hoy", detail: s.title, tone: .success, actionTitle: "Ver ya", actionSymbol: "play.fill", perform: {
            onPlay(s.route)
        }, secondTitle: "Deshacer", secondSymbol: "arrow.uturn.backward", second: { Task { await model.undo(s) } })
    }

    /// «Paso» (izquierda o ✕): no vuelve en un mes, y se puede deshacer (F5: antes no tenía vuelta).
    private func discard(_ s: Suggestion, _ model: MatchDeckModel) {
        kicks[.discard, default: 0] += 1
        model.discard(s)
        env.notify("Paso", detail: s.title, tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") { model.undoDiscard(s) }
    }

    /// Los avisos del mazo, abajo, justo encima de los botones: al alcance del pulgar. Se quitan deslizándolos hacia arriba.
    private var deckNotices: some View {
        BannerView().padding(.horizontal, -DS.Space.gutter).padding(.bottom, DS.Space.s2)
    }

    /// Paso · Para hoy · Guardar · Ver (✕ · ★ · ♥ · ▶): cuatro círculos iguales (`MatchActionButton`), repartidos de margen
    /// a margen, cada uno con su nombre debajo. Los tres primeros hacen salir volando la carta y llevan el color de su sello
    /// (lo único con color: dice hacia dónde se va); se encienden mientras arrastras hacia su lado y su símbolo salta cuando la
    /// carta sale por ellos. «Ver» reproduce la de arriba (pulido de DE2: antes ▶ flotaba sobre el arte).
    private func actions(_ model: MatchDeckModel) -> some View {
        // Repartidos con el mismo hueco entre ellos y los de las puntas en los márgenes.
        HStack(alignment: .top, spacing: 0) {
            action(Text("Paso"), id: "match-discard") {
                MatchActionButton(command: .discard, symbol: DS.Symbol.matchPass, label: "Paso", tint: DS.Match.pass, pull: pull, kick: kicks[.discard] ?? 0) { command = .discard }
            }
            Spacer(minLength: DS.Space.s2)
            action(Text("Para hoy"), id: "match-tonight") {
                MatchActionButton(command: .tonight, symbol: DS.Symbol.matchTonight, label: "Para hoy", tint: DS.Match.tonight, pull: pull, kick: kicks[.tonight] ?? 0) { command = .tonight }
            }
            Spacer(minLength: DS.Space.s2)
            action(Text("Guardar"), id: "match-save") {
                MatchActionButton(command: .save, symbol: DS.Symbol.matchKeep, label: "Guardar", tint: DS.Match.keep, pull: pull, kick: kicks[.save] ?? 0) { command = .save }
            }
            Spacer(minLength: DS.Space.s2)
            action(Text("Ver"), id: "match-play") {
                MatchActionButton(command: nil, symbol: "play.fill", label: "Ver", tint: DS.text, pull: pull) { if let s = model.cards.first { onPlay(s.route) } }
            }
        }
        .frame(maxWidth: DS.Match.cardMax)   // en el iPad, del ancho de la carta: no se van a las orillas de la hoja
        .frame(maxWidth: .infinity)
        .dsFeedback(.impact(flexibility: .soft), trigger: model.cards.first?.imdb)
    }

    private func action(_ name: Text, id: String, @ViewBuilder button: () -> some View) -> some View {
        VStack(spacing: DS.Match.actionLabelGap) {
            button().accessibilityLabel(name).accessibilityIdentifier(id)
            // En un renglón aunque la letra sea grande (antes «Guar-dar» en dos).
            name.recipe(.badge, color: DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale).accessibilityHidden(true)
        }
    }
}
