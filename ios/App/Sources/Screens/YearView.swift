import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Tu año» (Ajustes, bajo tu perfil): lo que viste este año según tu historial de Trakt — horas, racha más larga, tu
/// género, el mapa de calor día por día (películas, series o las dos) y lo que más viste.
struct YearView: View {
    /// «Miércoles, 28 de octubre» / «Wednesday, October 28»: solo la primera letra en mayúscula (`capitalized` ponía «De Octubre»).
    static func dayTitle(_ day: Date, _ locale: Locale) -> String {
        let text = day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        return text.prefix(1).uppercased(with: locale) + text.dropFirst()
    }
    @Environment(AppEnvironment.self) private var env
    @State private var review: YearInReview?
    @State private var loading = true
    /// El día que tocaste en el mapa (al abrir: el último con algo visto).
    @State private var selectedDay: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                if let r = review {
                    HStack(spacing: DS.Space.s3) {
                        stat(Text(verbatim: "\(r.hours) h"), Text("vistas"))
                        stat(Text("\(r.longestStreak) días"), Text("racha más larga"))
                        stat(Text(verbatim: genreName(r.topGenre)), Text("tu género"))
                    }
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        DSSectionHead(title: Text("Día por día"), trailing: Text("\(r.movies) películas · \(r.episodes) episodios"), level: .section)
                        ScrollView(.horizontal, showsIndicators: false) { heatMap(r) }
                            .defaultScrollAnchor(.trailing)   // lo reciente a la vista
                        HStack(spacing: DS.Space.s4) {
                            legend(DS.YearMap.movies, Text("Películas")); legend(DS.YearMap.series, Text("Series")); legend(DS.YearMap.both, Text("Las dos"))
                        }
                        dayDetail(r)
                    }
                    .padding(DS.Space.s4)
                    .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                    if !r.top.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.s3) {
                            DSSectionHead(title: "Lo que más viste", level: .section)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                                    ForEach(r.top) { t in
                                        TitleLink(route: TitleRoute(kind: t.kind, metaID: t.imdb, title: t.title, poster: String(format: ForYou.metahubPoster, t.imdb)),
                                                  detail: t.kind == "movie" ? Text("Película") : Text("\(t.plays) episodios"))
                                    }
                                }
                            }
                            .padding(.horizontal, -DS.Space.gutter).contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
                        }
                    }
                } else if loading {
                    DSLoadingState()
                } else {
                    DSEmptyState(symbol: "calendar", title: Text("Conecta Trakt"), message: Text("Conecta Trakt (en tu Orbital o en Ajustes) para ver tu año."))
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s4).padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop())
        .navigationTitle(Text("Tu \(String(review?.year ?? Calendar.current.component(.year, from: Date())))")).navigationBarTitleDisplayMode(.inline)
        .task {
            #if DEBUG
            if Demo.isOn { review = Demo.yearInReview; loading = false; selectedDay = review?.plays.keys.max(); return }
            #endif
            review = await env.services.forYou.yearInReview()
            loading = false
            selectedDay = review?.plays.keys.max()
        }
    }

    private func stat(_ value: Text, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            value.recipe(.section).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            label.recipe(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s3)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    private func legend(_ color: Color, _ text: Text) -> some View {
        HStack(spacing: DS.Space.s1) {
            RoundedRectangle(cornerRadius: DS.YearMap.radius).fill(color).frame(width: DS.YearMap.cell, height: DS.YearMap.cell)
            text.recipe(.caption)
        }
    }

    /// Una columna por semana (de lunes a domingo), del 1 de enero a hoy.
    private func heatMap(_ r: YearInReview) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(from: DateComponents(year: r.year, month: 1, day: 1)) ?? today
        let firstWeekday = (cal.component(.weekday, from: start) + 5) % 7   // lunes = 0
        let days = (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        let weeks = (firstWeekday + days + 6) / 7
        return HStack(alignment: .top, spacing: DS.YearMap.gap) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: DS.YearMap.gap) {
                    ForEach(0..<7, id: \.self) { d in
                        let offset = w * 7 + d - firstWeekday
                        let day = cal.date(byAdding: .day, value: offset, to: start) ?? start
                        RoundedRectangle(cornerRadius: DS.YearMap.radius)
                            .fill(offset < 0 || day > today ? Color.clear : color(r.days[day]))
                            .frame(width: DS.YearMap.cell, height: DS.YearMap.cell)
                            .overlay {
                                if let selectedDay, cal.isDate(day, inSameDayAs: selectedDay), offset >= 0 {
                                    RoundedRectangle(cornerRadius: DS.YearMap.radius).strokeBorder(DS.text, lineWidth: DS.YearMap.ring)
                                        .padding(-DS.YearMap.ring)
                                }
                            }
                    }
                }
            }
        }
        // Las casillas son chicas: el toque elige la más cercana (no hace falta atinarle exacta).
        .contentShape(Rectangle())
        .onTapGesture { point in
            let pitch = DS.YearMap.cell + DS.YearMap.gap
            let w = Int(point.x / pitch), d = min(6, max(0, Int(point.y / pitch)))
            let offset = w * 7 + d - firstWeekday
            guard offset >= 0, let day = cal.date(byAdding: .day, value: offset, to: start), day <= today else { return }
            selectedDay = day
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(r.days.count) días con algo visto"))
        .accessibilityHint(Text("Desliza hacia arriba o abajo para ir de un día con algo visto a otro"))
        .accessibilityAdjustableAction { direction in step(r, forward: direction == .increment) }
    }

    /// Al día con algo visto anterior o siguiente.
    private func step(_ r: YearInReview, forward: Bool) {
        let days = r.plays.keys.sorted()
        guard !days.isEmpty else { return }
        guard let current = selectedDay else { selectedDay = days.last; return }
        selectedDay = forward ? days.first { $0 > current } ?? current : days.last { $0 < current } ?? current
    }

    /// Lo que viste el día elegido: cada título una vez (con sus episodios de ese día), y flechas para ir al día anterior o
    /// siguiente con algo visto.
    @ViewBuilder private func dayDetail(_ r: YearInReview) -> some View {
        if let day = selectedDay {
            let plays = r.plays[Calendar.current.startOfDay(for: day)] ?? []
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack {
                    Text(verbatim: Self.dayTitle(day, env.uiLocale)).recipe(.cardTitle)   // en el idioma de la app
                    Spacer()
                    Button { step(r, forward: false) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(Text("Día anterior con algo visto"))
                    Button { step(r, forward: true) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel(Text("Día siguiente con algo visto"))
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                if plays.isEmpty {
                    Text("Ese día no viste nada.").recipe(.footnote)
                } else {
                    ForEach(WatchingDay.groups(plays), id: \.imdb) { g in
                        TitleNavigationLink(route: TitleRoute(kind: g.kind, metaID: g.imdb, title: g.title, poster: String(format: ForYou.metahubPoster, g.imdb))) {
                            HStack(spacing: DS.Space.s3) {
                                PosterView(url: String(format: ForYou.metahubPoster, g.imdb), title: g.title).frame(width: DS.YearMap.dayPoster)
                                VStack(alignment: .leading, spacing: DS.Space.s1) {
                                    Text(verbatim: g.title).recipe(.cardTitle).lineLimit(1)
                                    Text(verbatim: g.detail).recipe(.footnote).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(DS.textMuted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, DS.Space.s2)
            .animation(nil, value: selectedDay)
        }
    }

    private func color(_ day: YearInReview.Day?) -> Color {
        switch day { case .movies?: DS.YearMap.movies; case .series?: DS.YearMap.series; case .both?: DS.YearMap.both; case nil: DS.fill }
    }

    private func genreName(_ trakt: String?) -> String {
        guard let trakt else { return "—" }
        let map = ["science-fiction": "Sci-Fi", "drama": "Drama", "comedy": "Comedy", "action": "Action", "thriller": "Thriller", "horror": "Horror",
                   "romance": "Romance", "animation": "Animation", "crime": "Crime", "documentary": "Documentary", "fantasy": "Fantasy", "adventure": "Adventure"]
        let english = map[trakt] ?? trakt.capitalized
        return Vocabulary.genres([english], language: env.services.appSettings.uiLanguage).first ?? english
    }
}
