import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Tus vistas» y «Tu nota» de la ficha (gestor ola 3, O3-B, Fernando, 10 nov 2026: «Vamos con todo y tus sugerencias»):
/// cuántas veces la viste y cuándo (cambiar una fecha, borrar una vista repetida, «La vi otra vez») y una nota privada que
/// vive en tu Trakt si eres VIP o, si no, en este iPhone (y lo dice). docs/producto/live-activity-2026-11-08/gestor-ola3.html
struct ViewingsTarget: Identifiable, Hashable {
    var kind: String
    var metaID: String
    var videoID: String
    var title: String
    var id: String { videoID }
}

extension TitleView {
    /// «La viste 2 veces · la última, el 14 mar 2025 ›» bajo tu calificación (películas vistas, con Trakt).
    @ViewBuilder func yourViewings(_ model: TitleModel) -> some View {
        if model.canFavorite, model.kind == "movie", model.isWatched(.movie) {
            ViewingsLine(kind: model.kind, videoID: model.metaID, version: viewingsFor == nil ? 0 : 1) {
                viewingsFor = ViewingsTarget(kind: model.kind, metaID: model.metaID, videoID: model.metaID, title: model.title)
            }
        }
    }

    /// «Tu nota ›»: lo que escribiste (o «Escribe una nota») bajo tu calificación.
    @ViewBuilder func yourNote(_ model: TitleModel) -> some View {
        if model.canFavorite {
            let notes = env.notes
            let text = notes.note(model.metaID)
            Button { noting = true } label: {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "note.text").foregroundStyle(DS.textMuted)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text("Tu nota").recipe(.secondary, color: DS.textMuted)
                        if !text.isEmpty { Text(verbatim: text).recipe(.footnote, color: DS.text).lineLimit(2).multilineTextAlignment(.leading) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: text.isEmpty ? "plus" : "chevron.right").font(DS.TextRecipe.label.font).foregroundStyle(DS.textFaint)
                }
                .frame(minHeight: DS.Size.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("title-your-note")
        }
    }

    /// «Tus vistas» de un capítulo visto (mantener el dedo › «Tus vistas…»): cambiar su fecha o borrar una vista.
    func viewings(_ model: TitleModel, _ row: EpisodeRow) -> (() -> Void)? {
        guard model.canFavorite, row.watched else { return nil }
        return { viewingsFor = ViewingsTarget(kind: model.kind, metaID: model.metaID, videoID: row.id, title: model.title) }
    }

    /// G7-A: tus estrellas de la temporada elegida, bajo «3 de 22 vistos» (con Trakt y algo visto de ella).
    @ViewBuilder func seasonRating(_ model: TitleModel, _ progress: (watched: Int, total: Int)) -> some View {
        if model.canFavorite, progress.watched > 0, model.seasons.first(where: { $0.season == model.selectedSeason })?.isSpecials != true {
            let key = RatingKey.season(show: model.metaID, season: model.selectedSeason)
            let ratings = env.ratings
            HStack(spacing: DS.Space.s2) {
                Text("La temporada").recipe(.footnote, color: DS.textMuted)
                    .accessibilityLabel(Text("Tu calificación de la temporada"))
                RatingStars(value: ratings.stars(key), size: DS.Rating.starEpisode) { stars in
                    Task { await ratings.rate(imdb: key, kind: "series", stars: stars) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("season-rating")
        }
    }
}

/// Las hojas de «Tus vistas» y «Tu nota».
struct TitleViewingsAndNote: ViewModifier {
    let model: TitleModel
    @Binding var viewingsFor: ViewingsTarget?
    @Binding var noting: Bool
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content
            .sheet(item: $viewingsFor) { target in
                ViewingsSheet(target: target) { await model.refreshState() }
                    .fittedScrollSheet()
            }
            .sheet(isPresented: $noting) {
                NoteSheet(title: model.title, text: env.notes.note(model.metaID), inTrakt: env.notes.savesInTrakt) { text in
                    let notes = env.notes, id = model.metaID, series = model.kind == "series"
                    Task { await notes.save(id, series: series, text: text) }
                }
                .presentationDetents([.large])
            }
            .task(id: model.metaID) { await env.notes.load() }
    }
}

/// El renglón de la ficha: cuántas veces y la última.
struct ViewingsLine: View {
    let kind: String
    let videoID: String
    /// Cambia cuando cambia lo visto: se vuelve a preguntar.
    let version: Int
    let open: () -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var found: [TraktViewing]?

    var body: some View {
        Button(action: open) {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "calendar").foregroundStyle(DS.textMuted)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    count.recipe(.secondary, color: DS.textMuted)
                    if let last = found?.first { Text("La última, el \(Strings.date(last.at, .dayMonthYear, language: env.services.appSettings.uiLanguage))").recipe(.footnote, color: DS.text) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(DS.TextRecipe.label.font).foregroundStyle(DS.textFaint)
            }
            .frame(minHeight: DS.Size.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("title-your-viewings")
        .task(id: version) { found = try? await env.services.watch.viewings(kind: kind, videoID: videoID) }
    }

    private var count: Text {
        guard let n = found?.count, n > 0 else { return Text("Tus vistas") }
        return n == 1 ? Text("La viste 1 vez") : Text("La viste \(n) veces")
    }
}

/// Cada vez que la viste: tocar la fecha la cambia, el bote la borra (con «Deshacer») y «La vi otra vez…» suma una.
struct ViewingsSheet: View {
    let target: ViewingsTarget
    let changed: () async -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var viewings: [TraktViewing] = []
    @State private var loading = true
    @State private var failed = false
    @State private var editing: TraktViewing?
    @State private var adding = false

    private var language: String { env.services.appSettings.uiLanguage }

    var body: some View {
        NavigationStack {
            List {
                if loading { DSLoadingState().listRowBackground(Color.clear) }
                else if failed {
                    DSEmptyState(symbol: "wifi.slash", title: Text("No pude traer tus vistas"), message: Text("Revisa tu conexión e inténtalo otra vez.")) {
                        Button("Reintentar") { Task { await load() } }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewings, id: \.at) { v in
                        HStack(spacing: DS.Space.s3) {
                            Button { editing = v } label: {
                                HStack(spacing: DS.Space.s3) {
                                    Image(systemName: "calendar").foregroundStyle(DS.textMuted)
                                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                                        Text(verbatim: Self.stamp(v.at, language: language)).recipe(.body, color: DS.text)
                                        if v.id == 0 { Text("Espera a que haya internet").recipe(.caption, color: DS.textMuted) }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Cambiar la fecha"))
                            Button(role: .destructive) { remove(v) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(Text("Borrar esta vista"))
                                .accessibilityIdentifier("viewing-delete")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("viewing-row")
                    }
                    Button { adding = true } label: { Label("La vi otra vez…", systemImage: "arrow.trianglehead.2.clockwise") }
                        .accessibilityIdentifier("viewing-add")
                }
            }
            .navigationTitle(Text("Tus vistas")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .sheet(item: $editing) { v in
                ViewingDatePicker(title: Text("¿Cuándo la viste?"), initial: v.at) { date in move(v, to: date) }
            }
            .sheet(isPresented: $adding) {
                ViewingDatePicker(title: Text("La vi otra vez"), initial: Date()) { date in add(at: date) }
            }
        }
        .task { await load() }
        .accessibilityIdentifier("viewings-sheet")
    }

    static func stamp(_ date: Date, language: String) -> String {
        "\(Strings.date(date, .dayMonthYear, language: language)) · \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func load() async {
        loading = true; failed = false
        do { viewings = try await env.services.watch.viewings(kind: target.kind, videoID: target.videoID) }
        catch { failed = true }
        loading = false
    }

    private func remove(_ v: TraktViewing) {
        let watch = env.services.watch, t = target, env = env, changed = changed
        let left = viewings.count - 1
        withAnimation(DS.Motion.base(reduceMotion)) { viewings.removeAll { $0 == v } }
        Task {
            await watch.removeViewing(v, kind: t.kind, metaID: t.metaID, videoID: t.videoID, remaining: left)
            await changed()
            env.notify("Vista borrada", detail: Self.stamp(v.at, language: language), tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {
                Task { await watch.addViewing(kind: t.kind, metaID: t.metaID, videoID: t.videoID, at: v.at); await changed() }
            }
        }
    }

    private func move(_ v: TraktViewing, to date: Date) {
        let watch = env.services.watch, t = target
        Task {
            await watch.moveViewing(v, kind: t.kind, videoID: t.videoID, to: date)
            await load(); await changed()
        }
    }

    private func add(at date: Date) {
        let watch = env.services.watch, t = target
        Task {
            await watch.addViewing(kind: t.kind, metaID: t.metaID, videoID: t.videoID, name: t.title, at: date)
            await load(); await changed()
        }
    }
}

/// El calendario con la hora para una vista (cambiarla o sumar una).
struct ViewingDatePicker: View {
    let title: Text
    let initial: Date
    let save: (Date) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(title: Text, initial: Date, save: @escaping (Date) -> Void) {
        self.title = title; self.initial = initial; self.save = save; _date = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            DatePicker(selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute]) { title }
                .datePickerStyle(.graphical)
                .padding(.horizontal, DS.Space.gutter)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save(date); dismiss() }.accessibilityIdentifier("viewing-date-save") }
                }
        }
        .presentationDetents([.large])
    }
}

/// «Tu nota»: privada; con Trakt VIP vive en tu Trakt (hasta 500 letras); sin VIP, solo en este iPhone, y lo dice.
struct NoteSheet: View {
    let title: String
    let inTrakt: Bool
    let save: (String) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(title: String, text: String, inTrakt: Bool, save: @escaping (String) -> Void) {
        self.title = title; self.inTrakt = inTrakt; self.save = save; _text = State(initialValue: text)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(DS.Space.s2)
                    .dsCard(.row)
                    .frame(minHeight: DS.Size.noteEditor)
                    .onChange(of: text) { _, new in if inTrakt, new.count > Trakt.noteLimit { text = String(new.prefix(Trakt.noteLimit)) } }
                    .accessibilityIdentifier("note-editor")
                HStack(alignment: .top, spacing: DS.Space.s2) {
                    Image(systemName: inTrakt ? "lock" : "iphone").foregroundStyle(DS.textMuted)
                    Text(inTrakt ? "Privada, en tu Trakt (VIP). Nadie más la ve." : "Privada. Sin Trakt VIP se guarda solo en este iPhone; si un día tienes VIP, pasa sola a tu Trakt.")
                        .recipe(.footnote, color: DS.textMuted)
                        .accessibilityIdentifier("note-where")
                    Spacer(minLength: 0)
                    if inTrakt { Text(verbatim: "\(text.count)/\(Trakt.noteLimit)").recipe(.caption, color: DS.textFaint).monospacedDigit() }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.gutter)
            .navigationTitle(Text("Tu nota")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { save(text); dismiss() }.accessibilityIdentifier("note-save") }
            }
            .onAppear { focused = text.isEmpty }
        }
    }
}
