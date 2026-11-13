import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Historial» (G5-B, gestor ola 3, Fernando, 10 nov 2026: «Vamos con todo y tus sugerencias»): todo lo que viste, por mes y
/// con su hora. Las repetidas (el mismo título o capítulo con menos de una hora de otra) salen marcadas y se borran juntas;
/// tocar uno cambia su fecha, deslizarlo (o «Editar») lo borra y «Agregar» busca algo que viste fuera de Orbital. Es la
/// quinta pila de Guardado (D7-A). docs/producto/live-activity-2026-11-08/gestor-ola3.html
struct HistoryRoute: Hashable {}

struct HistoryScreen: View {
    @Environment(\.titleName) var titleName
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var env
    /// Lo que se carga, se borra y se deshace vive en `HistoryModel` (F5): la pantalla solo pinta.
    @State private var history: ModelObserver<HistoryModel>
    @State private var editing: TraktHistoryEntry?
    @State private var adding = false
    @State private var picked: SearchResult?
    @State private var confirmRepeats = false

    private var language: String { env.services.appSettings.uiLanguage }

    init() {
        let services = AppEnvironment.shared.services
        _history = State(wrappedValue: ModelObserver(HistoryModel(services, monthName: Self.monthName(services))))
    }

    /// «Noviembre», «Octubre 2025», en el idioma de la app de ahora (el mismo encabezado de mes que Vistas, I5).
    private static func monthName(_ services: Services) -> @MainActor (Date) -> String {
        { SavedStateScreen.month($0, language: services.appSettings.uiLanguage) }
    }

    var body: some View {
        let model = history.model
        List {
            ForEach(model.months) { month in
                Section {
                    // Borrar deslizando el renglón o con «Editar» (D7-A, 10 nov): sin un bote rojo en cada uno.
                    ForEach(month.entries) { e in row(e, repeated: model.repeats.contains(e.id)).listRowBackground(Color.clear) }
                        .onDelete { offsets in for i in offsets { remove(month.entries[i]) } }
                } header: {
                    // El mismo encabezado de mes que Vistas (I5).
                    DSSectionHead(title: Text(verbatim: month.id), count: month.entries.count, level: .subsection).textCase(nil)
                }
            }
            if model.failed {
                DSEmptyState(symbol: "wifi.slash", title: Text("No pude traer tu historial"), message: Text("Revisa tu conexión e inténtalo otra vez.")) {
                    Button("Reintentar") { Task { await model.loadMore() } }
                }
                .listRowBackground(Color.clear)
            } else if model.loading {
                DSLoadingState().listRowBackground(Color.clear)
            } else if model.entries.isEmpty {
                DSEmptyState(symbol: "clock", title: Text("Nada en tu historial"), message: Text("Lo que veas o marques como visto aparece aquí."))
                    .listRowBackground(Color.clear)
            } else if model.more {
                Button("Ver más") { Task { await model.loadMore() } }.accessibilityIdentifier("history-more").listRowBackground(Color.clear)
            }
            // Las repetidas, al final y sin alarma (D7-A): es limpieza, no un error.
            if !model.repeats.isEmpty {
                let repeats = model.repeats
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
            if !model.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton().accessibilityIdentifier("history-edit") }
            }
        }
        .refreshable { await model.reload() }
        .task { await model.loadIfNeeded() }
        .onChange(of: language) { model.monthName = Self.monthName(env.services) }   // los meses en el idioma nuevo
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
                ViewingDatePicker(title: Text(verbatim: titleName(r.title, id: r.metaID, kind: r.kind)), initial: Date()) { date in add(r, at: date) }
            } else {
                // Una serie se marca capítulo por capítulo: su ficha.
                NavigationStack { TitleView(route: TitleRoute(kind: r.kind, metaID: r.metaID, title: r.title, poster: r.poster)) }
            }
        }
        .confirmationDialog(Text("¿Quitar las vistas repetidas?"), isPresented: $confirmRepeats, titleVisibility: .visible) {   // ds-exception: confirmación destructiva corta
            Button("Quitar", role: .destructive) { cleanRepeats() }
        } message: { Text("De cada título se queda la primera vista.") }
    }

    @State private var pickedReady: SearchResult?

    /// «Ayer · 21:30 · Repetida» en un renglón; si no cabe (letra grande), «Repetida» en el suyo: un renglón nunca empieza
    /// con «·» (revisión del 11 nov).
    private func whenLine(_ e: TraktHistoryEntry, repeated: Bool) -> some View {
        let when = Self.when(e.at, locale: env.uiLocale)
        return ViewThatFits(in: .horizontal) {
            (repeated ? Text("\(when) · \(Text("Repetida"))") : when).lineLimit(1)
            VStack(alignment: .leading, spacing: 0) {
                when
                if repeated { Text("Repetida") }
            }
        }
        .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
    }

    private func row(_ e: TraktHistoryEntry, repeated: Bool) -> some View {
        Button { editing = e } label: {
            HStack(spacing: DS.Space.s3) {
                PosterView(url: String(format: ForYou.metahubPoster, e.target.imdb), title: titleName(e.title, id: e.target.imdb, kind: e.target.isEpisode ? "series" : "movie")).frame(width: DS.Collections.stackPoster).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(verbatim: name(e)).recipe(.cardTitle, color: DS.text).lineLimit(2)
                    whenLine(e, repeated: repeated)
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
        let time = Text(verbatim: " · " + Strings.date(date, .time, language: locale.identifier))   // la misma hora que Inicio (revisión del 11 nov)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        switch days {
        case 0: return Text("Hoy") + time
        case 1: return Text("Ayer") + time
        case 2...6: return dayName(date, locale: locale, calendar: calendar) + time
        default: return Text(verbatim: ViewingsSheet.stamp(date, language: locale.identifier))
        }
    }

    private func name(_ e: TraktHistoryEntry) -> String {
        guard let s = e.target.season, let n = e.target.episode else { return titleName(e.title, id: e.target.imdb, kind: "movie") }
        return "\(titleName(e.title, id: e.target.imdb, kind: "series")) · " + Strings.episode(season: s, episode: n, language: language)   // «T2 E5» / «S2 E5» según el idioma
    }

    private func remove(_ e: TraktHistoryEntry) {
        let model = history.model, env = env
        let send = withAnimation(DS.Motion.base(reduceMotion)) { model.remove(e) }
        Task {
            await send()
            env.collections.forgetWatched()
            env.notify("Vista borrada", detail: name(e), tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {
                Task { await model.undoRemove(e) }
            }
        }
    }

    private func move(_ e: TraktHistoryEntry, to date: Date) {
        let model = history.model
        Task { await model.move(e, to: date) }
    }

    private func add(_ r: SearchResult, at date: Date) {
        let model = history.model, env = env
        Task {
            await model.addMovie(metaID: r.metaID, title: r.title, at: date)
            env.collections.forgetWatched()
        }
    }

    private func cleanRepeats() {
        let model = history.model, env = env
        let (count, send) = withAnimation(DS.Motion.base(reduceMotion)) { model.removeRepeats() }
        Task {
            await send()
            if count == 1 { env.notify("Borré 1 vista repetida", tone: .success) }
            else { env.notify(format: "Borré %lld vistas repetidas", count, tone: .success) }
        }
    }
}
