import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Historial» (G5-B, gestor ola 3, Fernando, 10 nov 2026: «Vamos con todo y tus sugerencias»): todo lo que viste, por mes y
/// con su hora. Las repetidas (el mismo título o capítulo con menos de una hora de otra) salen marcadas y se borran juntas;
/// tocar uno cambia su fecha, el bote lo borra y «Agregar» busca algo que viste fuera de Orbital. Se abre desde Guardado ›
/// Vistas. docs/producto/live-activity-2026-11-08/gestor-ola3.html
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

    private var language: String { env.services.appSettings.uiLanguage }
    private var repeats: Set<Int> { Trakt.repeats(entries) }

    var body: some View {
        List {
            if !repeats.isEmpty {
                Section {
                    Button { confirmRepeats = true } label: {
                        Label { Text(repeats.count == 1 ? "Borrar 1 vista repetida" : "Borrar \(repeats.count) vistas repetidas") } icon: { Image(systemName: "trash") }
                    }
                    .foregroundStyle(DS.warning)
                    .accessibilityIdentifier("history-clean-repeats")
                } footer: { Text("Repetida: el mismo título o capítulo con menos de una hora de otra vista. Se queda la primera.") }
            }
            ForEach(months, id: \.0) { month, group in
                Section {
                    ForEach(group) { e in row(e) }
                } header: { Text(verbatim: month) }
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
                Button("Ver más") { Task { await loadMore() } }.accessibilityIdentifier("history-more")
            }
        }
        .navigationTitle(Text("Historial")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Label("Agregar", systemImage: "plus") }
                    .accessibilityIdentifier("history-add")
            }
        }
        .refreshable { await reload() }
        .task { if entries.isEmpty { await loadMore() } }
        .sheet(item: $editing) { e in
            ViewingDatePicker(title: Text("¿Cuándo la viste?"), initial: e.at) { date in move(e, to: date) }
        }
        .sheet(isPresented: $adding, onDismiss: { if picked != nil { pickedReady = true } }) {
            AddToListSheet(listName: Text("Historial"), search: { await env.titles.searchTitles($0) }, contains: { _ in false }) { r in
                picked = r
                adding = false
            }
        }
        .sheet(isPresented: $pickedReady, onDismiss: { picked = nil }) {
            if let r = picked {
                if r.kind == "movie" {
                    ViewingDatePicker(title: Text(verbatim: r.title), initial: Date()) { date in add(r, at: date) }
                } else {
                    // Una serie se marca capítulo por capítulo: su ficha.
                    NavigationStack { TitleView(route: TitleRoute(kind: r.kind, metaID: r.metaID, title: r.title, poster: r.poster)) }
                }
            }
        }
        .confirmationDialog(Text("¿Borrar las vistas repetidas?"), isPresented: $confirmRepeats, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { cleanRepeats() }
        } message: { Text("De cada título se queda la primera vista.") }
    }

    @State private var pickedReady = false

    private func row(_ e: TraktHistoryEntry) -> some View {
        let repeated = repeats.contains(e.id)
        return HStack(spacing: DS.Space.s3) {
            Button { editing = e } label: {
                HStack(spacing: DS.Space.s3) {
                    PosterView(url: String(format: ForYou.metahubPoster, e.target.imdb), title: e.title).frame(width: DS.Collections.stackPoster).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(verbatim: name(e)).recipe(.cardTitle, color: repeated ? DS.warning : DS.text).lineLimit(1)
                        (Text(verbatim: ViewingsSheet.stamp(e.at, language: language)) + (repeated ? Text(verbatim: " · ") + Text("Repetida") : Text(verbatim: "")))
                            .recipe(.footnote, color: DS.textMuted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Cambiar la fecha"))
            Button(role: .destructive) { remove(e) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Borrar esta vista"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(repeated ? "history-row-repeat" : "history-row")
    }

    private func name(_ e: TraktHistoryEntry) -> String {
        guard let s = e.target.season, let n = e.target.episode else { return e.title }
        return "\(e.title) · T\(s) E\(n)"
    }

    /// Por mes, lo más nuevo primero: «Noviembre 2026».
    private var months: [(String, [TraktHistoryEntry])] {
        var order: [String] = []
        var groups: [String: [TraktHistoryEntry]] = [:]
        for e in entries {
            let raw = Strings.date(e.at, .monthYear, language: language), key = raw.prefix(1).uppercased() + raw.dropFirst()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(e)
        }
        return order.map { ($0, groups[$0]!) }
    }

    private func reload() async { entries = []; page = 1; more = true; await loadMore() }

    private func loadMore() async {
        guard !loading else { return }
        loading = true; failed = false
        do {
            let found = try await env.services.watch.history(page: page)
            entries += found.filter { f in !entries.contains { $0.id == f.id } }
            more = found.count >= 100
            page += 1
        } catch { failed = true }
        loading = false
    }

    private func remove(_ e: TraktHistoryEntry) {
        let watch = env.services.watch, env = env
        let left = entries.filter { $0.target == e.target && $0.id != e.id }.count
        withAnimation(DS.Motion.base(reduceMotion)) { entries.removeAll { $0.id == e.id } }
        Task {
            await watch.removeViewing(TraktViewing(id: e.id, at: e.at), kind: e.kind, metaID: e.target.imdb, videoID: videoID(e), remaining: left)
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
