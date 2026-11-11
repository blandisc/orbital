import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Historial» (G5-B, gestor ola 3, Fernando, 10 nov 2026: «Vamos con todo y tus sugerencias»): todo lo que viste, por mes y
/// con su hora. Las repetidas (el mismo título o capítulo con menos de una hora de otra) salen marcadas y se borran juntas;
/// tocar uno cambia su fecha, deslizarlo (o «Editar») lo borra y «Agregar» busca algo que viste fuera de Orbital. Es la
/// quinta pila de Guardado (D7-A). docs/producto/live-activity-2026-11-08/gestor-ola3.html
struct HistoryRoute: Hashable {}

struct HistoryScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var env
    @State private var entries: [TraktHistoryEntry] = []
    @State private var page = 1
    @State private var more = true
    @State private var loading = false
    @State private var failed = false
    @State private var editing: TraktHistoryEntry?
    @State private var adding = false
    @State private var picked: SearchResult?
    @State private var confirmRepeats = false
    // Las repetidas y los meses se calculan una vez por cambio de `entries`, no en cada pintado (A13, 10 nov 2026).
    @State private var repeats: Set<Int> = []
    @State private var months: [(String, [TraktHistoryEntry])] = []

    private var language: String { env.services.appSettings.uiLanguage }

    var body: some View {
        List {
            ForEach(months, id: \.0) { month, group in
                Section {
                    // Borrar deslizando el renglón o con «Editar» (D7-A, 10 nov): sin un bote rojo en cada uno.
                    ForEach(group) { e in row(e).listRowBackground(Color.clear) }
                        .onDelete { offsets in for i in offsets { remove(group[i]) } }
                } header: {
                    // El mismo encabezado de mes que Vistas (I5).
                    DSSectionHead(title: Text(verbatim: month), count: group.count, level: .subsection).textCase(nil)
                }
            }
            if failed {
                DSEmptyState(symbol: "wifi.slash", title: Text("No pude traer tu historial"), message: Text("Revisa tu conexión e inténtalo otra vez.")) {
                    Button("Reintentar") { Task { await loadMore() } }
                }
                .listRowBackground(Color.clear)
            } else if loading {
                DSLoadingState().listRowBackground(Color.clear)
            } else if entries.isEmpty {
                DSEmptyState(symbol: "clock", title: Text("Nada en tu historial"), message: Text("Lo que veas o marques como visto aparece aquí."))
                    .listRowBackground(Color.clear)
            } else if more {
                Button("Ver más") { Task { await loadMore() } }.accessibilityIdentifier("history-more").listRowBackground(Color.clear)
            }
            // Las repetidas, al final y sin alarma (D7-A): es limpieza, no un error.
            if !repeats.isEmpty {
                Section {
                    Button { confirmRepeats = true } label: {
                        Label { Text(repeats.count == 1 ? "Quitar 1 vista repetida" : "Quitar \(repeats.count) vistas repetidas") } icon: { Image(systemName: "square.on.square") }
                            .recipe(.label, color: DS.text)
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("history-clean-repeats")
                } footer: { Text("Repetida: el mismo título o capítulo con menos de una hora de otra vista. Se queda la primera.") }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Backdrop())   // el cielo del resto de la app (I5)
        .navigationTitle(Text("Historial")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Label("Agregar", systemImage: "plus") }
                    .accessibilityIdentifier("history-add")
            }
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton().accessibilityIdentifier("history-edit") }
            }
        }
        .refreshable { await reload() }
        .task { if entries.isEmpty { await loadMore() } }
        .onChange(of: entries.map(\.id), initial: true) { regroup() }
        .onChange(of: language) { regroup() }
        .sheet(item: $editing) { e in
            ViewingDatePicker(title: Text("¿Cuándo la viste?"), initial: e.at) { date in move(e, to: date) }
        }
        .sheet(isPresented: $adding, onDismiss: { pickedReady = picked; picked = nil }) {
            AddToListSheet(listName: Text("Historial"), search: { await env.titles.searchTitles($0) }, contains: { _ in false }) { r in
                picked = r
                adding = false
            }
        }
        // Con `item` (no `isPresented`): la hoja nace con su título; con `isPresented` llegaba en blanco (la pasada del 10 nov).
        .sheet(item: $pickedReady) { r in
            if r.kind == "movie" {
                ViewingDatePicker(title: Text(verbatim: r.title), initial: Date()) { date in add(r, at: date) }
            } else {
                // Una serie se marca capítulo por capítulo: su ficha.
                NavigationStack { TitleView(route: TitleRoute(kind: r.kind, metaID: r.metaID, title: r.title, poster: r.poster)) }
            }
        }
        .confirmationDialog(Text("¿Quitar las vistas repetidas?"), isPresented: $confirmRepeats, titleVisibility: .visible) {
            Button("Quitar", role: .destructive) { cleanRepeats() }
        } message: { Text("De cada título se queda la primera vista.") }
    }

    @State private var pickedReady: SearchResult?

    private func row(_ e: TraktHistoryEntry) -> some View {
        let repeated = repeats.contains(e.id)
        return Button { editing = e } label: {
            HStack(spacing: DS.Space.s3) {
                PosterView(url: String(format: ForYou.metahubPoster, e.target.imdb), title: e.title).frame(width: DS.Collections.stackPoster).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(verbatim: name(e)).recipe(.cardTitle, color: DS.text).lineLimit(2)
                    (Self.when(e.at, locale: env.uiLocale) + (repeated ? Text(verbatim: " · ") + Text("Repetida") : Text(verbatim: "")))
                        .recipe(.footnote, color: DS.textMuted)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Cambiar la fecha"))
        .accessibilityIdentifier(repeated ? "history-row-repeat" : "history-row")
    }

    /// «Hoy · 21:30», «Ayer · 21:30», «Lunes · 21:30» en la última semana; antes, la fecha («3 nov 2026 · 21:30») (I5).
    static func when(_ date: Date, locale: Locale, now: Date = Date(), calendar: Calendar = .current) -> Text {
        let time = Text(verbatim: " · " + date.formatted(date: .omitted, time: .shortened))
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        switch days {
        case 0: return Text("Hoy") + time
        case 1: return Text("Ayer") + time
        case 2...6: return dayName(date, locale: locale, calendar: calendar) + time
        default: return Text(verbatim: ViewingsSheet.stamp(date, language: locale.identifier))
        }
    }

    private func name(_ e: TraktHistoryEntry) -> String {
        guard let s = e.target.season, let n = e.target.episode else { return e.title }
        return "\(e.title) · " + Strings.episode(season: s, episode: n, language: language)   // «T2 E5» / «S2 E5» según el idioma
    }

    private func regroup() {
        repeats = Trakt.repeats(entries)
        months = Self.months(entries, language: language)
    }

    /// Por mes, lo más nuevo primero: «Noviembre», «Octubre 2025».
    private static func months(_ entries: [TraktHistoryEntry], language: String) -> [(String, [TraktHistoryEntry])] {
        var order: [String] = []
        var groups: [String: [TraktHistoryEntry]] = [:]
        for e in entries {
            let key = SavedStateScreen.month(e.at, language: language)   // «Noviembre»; con el año si no es este (como Vistas)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(e)
        }
        return order.map { ($0, groups[$0]!) }
    }

    private func reload() async {
        guard !loading else { return }   // con una página en camino, reiniciar la dejaría caer en una lista vacía
        entries = []; page = 1; more = true; await loadMore()
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true; failed = false
        do {
            let found = try await env.services.watch.history(page: page)
            entries += found.entries.filter { f in !entries.contains { $0.id == f.id } }
            more = found.full
            page += 1
        } catch { failed = true }
        loading = false
    }

    private func remove(_ e: TraktHistoryEntry) {
        let watch = env.services.watch, env = env
        let left = entries.filter { $0.target == e.target && $0.id != e.id }.count
        withAnimation(DS.Motion.base(reduceMotion)) { entries.removeAll { $0.id == e.id } }
        Task {
            await watch.removeViewing(TraktViewing(id: e.id, at: e.at), kind: e.kind, metaID: e.target.imdb, videoID: videoID(e), remaining: left, sure: false)
            env.collections.forgetWatched()
            env.notify("Vista borrada", detail: name(e), tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {
                Task { await watch.addViewing(kind: e.kind, metaID: e.target.imdb, videoID: videoID(e), name: e.title, at: e.at); await reload() }
            }
        }
    }

    private func move(_ e: TraktHistoryEntry, to date: Date) {
        let watch = env.services.watch
        Task { await watch.moveViewing(TraktViewing(id: e.id, at: e.at), kind: e.kind, videoID: videoID(e), to: date); await reload() }
    }

    private func add(_ r: SearchResult, at date: Date) {
        let watch = env.services.watch, env = env
        Task {
            await watch.addViewing(kind: "movie", metaID: r.metaID, videoID: r.metaID, name: r.title, at: date)
            env.collections.forgetWatched()
            await reload()
        }
    }

    private func cleanRepeats() {
        let ids = Array(repeats), watch = env.services.watch, env = env
        withAnimation(DS.Motion.base(reduceMotion)) { entries.removeAll { ids.contains($0.id) } }
        Task {
            await watch.removeViewings(ids)
            if ids.count == 1 { env.notify("Borré 1 vista repetida", tone: .success) }
            else { env.notify(format: "Borré %lld vistas repetidas", ids.count, tone: .success) }
        }
    }

    private func videoID(_ e: TraktHistoryEntry) -> String {
        guard let s = e.target.season, let n = e.target.episode else { return e.target.imdb }
        return "\(e.target.imdb):\(s):\(n)"
    }
}
