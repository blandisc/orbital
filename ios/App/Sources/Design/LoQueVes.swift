import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas de «Lo que ves» (docs/producto/muvy-busqueda-premios/prototipo-wrapped.html): la tarjeta de Para ti, un dato
// grande, las barras del periodo, el mapa día por día y los géneros. Los colores de película, serie y las dos son los del
// mapa de «Tu año» (`DS.YearMap`).

/// La puerta de «Lo que ves» arriba de Para ti (Fernando, 30 oct 2026, opción E2): el mismo renglón de «Tuyo» (`ListRow`):
/// lo que más viste esta semana en pila, «Lo que ves» y «4 h esta semana · sobre todo drama».
struct WatchingCard: View {
    /// nil: aún cargando.
    let stats: WatchingStats?
    /// «Lo que ves» en el idioma de la app (lo pone quien la usa: el del sistema no siempre es el de la app).
    let name: String
    /// Los géneros del periodo ya en el idioma de la app (los pone quien la usa).
    var genres: [String] = []
    /// El periodo que cuenta: el primero con algo (si la semana va vacía, el mes; si no, el año…).
    var period: WatchingStats.Period = .week
    /// Lo último que viste, para cuando no hay nada en ningún periodo cargado.
    var lastTitle: String?
    /// nil: solo el renglón (dentro de un `NavigationLink`, que recibe el toque; ver `CollectionsShowcase`).
    var action: (() -> Void)?

    var body: some View {
        if let action { Button(action: action) { row }.buttonStyle(.plain).accessibilityIdentifier("watching-card") }
        else { row.accessibilityIdentifier("watching-card") }
    }

    private var row: some View {
        ListRow(name: name, detail: detail, posters: (stats?.top ?? []).prefix(DS.ParaTiB.matchFan).map(\.poster))
            .contentShape(Rectangle())
    }

    /// «12 h este mes · sobre todo drama»: del primer periodo con algo (nunca vacía: el domingo la semana empieza en cero).
    /// Sin nada contado, lo último que viste; mientras carga, «Lo que viste».
    private var detail: Text {
        guard let s = stats else { return Text("Lo que viste") }
        if s.isEmpty { return lastTitle.map { Text("Lo último: \($0)") } ?? Text("Aún no hay nada") }
        let h = s.minutes / 60, m = s.minutes % 60
        let amount = h == 0 ? Text("\(m) min") : Text("\(h) h")
        let time = Text("\(amount) \(WatchingCard.phrase(period))")
        guard let genre = genres.first else { return time }
        return Text("\(time) · sobre todo \(genre.lowercased())")
    }

    static func phrase(_ p: WatchingStats.Period) -> Text {
        switch p { case .week: Text("esta semana"); case .month: Text("este mes"); case .year: Text("este año"); case .all: Text("desde siempre") }
    }
}

/// Las barras del periodo (días, semanas, meses o años), la más alta resaltada.
struct WatchingBars: View {
    let values: [Int]
    let labels: [String]
    /// La barra elegida (en «Cómo calificas»): resaltada; nil, la más alta.
    var highlighted: Int? = nil
    /// Tocar una barra (en «Cómo calificas»: abre lo que calificaste con ese número); nil: solo se ve.
    var onTap: ((Int) -> Void)?
    /// Las barras crecen desde abajo, una tras otra, cuando llegan sus números (al abrir o al cambiar de periodo).
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: DS.Space.s1) {
            ForEach(values.indices, id: \.self) { i in
                VStack(spacing: DS.Space.s1) {
                    GeometryReader { geo in
                        VStack { Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous).fill((highlighted.map { $0 == i } ?? (values[i] == top)) && values[i] > 0 ? DS.brandMoon : DS.fillStrong)
                                .frame(height: max(DS.Watching.barMin, geo.size.height * CGFloat(values[i]) / CGFloat(top) * (grown ? 1 : 0)))
                                .animation(DS.Motion.enter(reduceMotion)?.delay(Double(i) * DS.Watching.barStagger), value: grown)
                        }
                    }
                    Text(verbatim: labels.indices.contains(i) ? labels[i] : "").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).lineLimit(1)
                        .minimumScaleFactor(DS.Size.statScale)
                }
                .contentShape(Rectangle())
                .onTapGesture { if values[i] > 0 { onTap?(i) } }
            }
        }
        .frame(height: DS.Watching.barsHeight)
        .onChange(of: values, initial: true) { _, _ in
            grown = false
            Task { @MainActor in grown = true }   // en el siguiente cuadro: así crecen desde abajo y no aparecen ya hechas
        }
        .accessibilityElement(children: onTap == nil ? .ignore : .contain)
        .accessibilityLabel(Text("Minutos por periodo"))
    }
}

/// «Día por día» (Fernando, 31 oct 2026, opción B): el mapa de calor como GitHub (una columna por semana, de lunes a
/// domingo, del azul del logo según cuánto viste), en un `DSWeekStrip`: abre en lo de hoy con semanas enteras a la vista y
/// se desliza hacia atrás (13 nov 2026: antes abría cortado y en el otro extremo). Hoy lleva borde; abajo, la leyenda.
/// Tocar un día abre debajo lo que viste; tocarlo otra vez lo cierra.
struct WatchingZoomMap: View {
    @Environment(\.titleName) var titleName
    let plays: [TraktPlay]
    let locale: Locale
    /// El ancho que le queda (la columna sin sus márgenes): de ahí sale el tamaño de las casillas.
    let available: CGFloat
    @State private var day: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }()

    var body: some View {
        // Solo los últimos tres años y sin los «No sé cuándo» de Trakt (`WatchingHeat`): antes el mapa llegaba a 1970, se
        // trababa al llegar a él y ese día gigante dejaba a todos los demás del mismo azul pálido (Fernando, 14 nov 2026).
        let since = calendar.date(byAdding: .weekOfYear, value: -WatchingHeat.maxWeeks, to: Date()) ?? Date()
        let minutes = WatchingHeat.minutes(plays, since: since, calendar: calendar)
        let byDay = Dictionary(grouping: plays.filter { $0.at >= since }) { calendar.startOfDay(for: $0.at) }
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                map(minutes)
                DSHeatLegend(steps: [0, 1, 2, 3].map(fill))
            }
            if let day {
                // Se asoma desde debajo del mapa (apenas baja y crece un poco, fundiéndose), sin brincar desde arriba; otro
                // día se funde sobre el anterior (Fernando, 31 oct 2026).
                dayDetail(day, byDay)
                    .id(day)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: DS.Watching.dayFrom, anchor: .top))
                                                .combined(with: .offset(y: -DS.Space.s2)),
                                            removal: .opacity))
            }
        }
        .animation(DS.Motion.smooth(reduceMotion), value: day)
        .dsFeedback(.selection, trigger: day)
        .onAppear {
            #if DEBUG
            if Demo.isOn, Demo.zoom == "day", let last = plays.map(\.at).max() { day = calendar.startOfDay(for: last) }
            #endif
        }
    }

    /// Desde el lunes de la semana de lo primero que viste (al menos un año) hasta esta semana.
    private func map(_ minutes: [Date: Int]) -> some View {
        let today = calendar.startOfDay(for: Date())
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let earliest = min(minutes.keys.min() ?? today, calendar.date(byAdding: .weekOfYear, value: -(DS.Watching.yearWeeks - 1), to: thisWeek) ?? today)
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: earliest)?.start ?? earliest
        let weeks = (calendar.dateComponents([.weekOfYear], from: firstWeek, to: thisWeek).weekOfYear ?? 0) + 1
        let levels = WatchingHeat.levels(minutes)
        let calendar = calendar, locale = locale
        let monday = { (w: Int) in calendar.date(byAdding: .weekOfYear, value: w, to: firstWeek) ?? firstWeek }
        return DSWeekStrip(weeks: weeks, available: available, weekdays: DSWeekStrip<EmptyView>.weekdayLetters(locale: locale),
                           label: { DSWeekStrip<EmptyView>.monthLabel(monday($0), calendar: calendar, locale: locale) }) { w, d, _ in
            let date = calendar.date(byAdding: .day, value: d, to: monday(w)) ?? today
            let inside = date <= today
            let chosen = day.map { calendar.isDate($0, inSameDayAs: date) } ?? false
            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                .fill(inside ? fill(levels[date] ?? 0) : .clear)
                .overlay { if date == today { DSWeekStripToday() } }
                .dsSelectionRing(chosen, radius: DS.Radius.xs)
                .contentShape(Rectangle())
                .onTapGesture { if inside { day = chosen ? nil : date } }
                .accessibilityHidden(!inside || ((minutes[date] ?? 0) == 0 && date != today))
                .accessibilityLabel(date == today ? Text("Hoy") : Text(date, format: .dateTime.weekday(.wide).day().month(.wide)))
                .accessibilityValue(Text(verbatim: Strings.duration(minutes[date] ?? 0)))
                .accessibilityAddTraits(.isButton)
        }
        .accessibilityIdentifier("watching-heatmap")
    }

    /// El día: cada título una vez, con sus episodios.
    @ViewBuilder private func dayDetail(_ day: Date, _ byDay: [Date: [TraktPlay]]) -> some View {
        let plays = byDay[calendar.startOfDay(for: day)] ?? []
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack {
                Text(verbatim: YearView.dayTitle(day, locale)).recipe(.cardTitle)
                Spacer()
                DSIconButton(symbol: "xmark", label: "Cerrar el día", size: .regular) { self.day = nil }
            }
            if plays.isEmpty {
                Text("Ese día no viste nada.").recipe(.footnote)
            } else {
                ForEach(WatchingDay.groups(plays), id: \.imdb) { g in
                    TitleNavigationLink(route: TitleRoute(kind: g.kind, metaID: g.imdb, title: g.title, poster: String(format: ForYou.metahubPoster, g.imdb))) {
                        HStack(spacing: DS.Space.s3) {
                            PosterView(url: String(format: ForYou.metahubPoster, g.imdb), title: titleName(g.title, id: g.imdb, kind: g.kind)).frame(width: DS.YearMap.dayPoster)
                            VStack(alignment: .leading, spacing: DS.Space.s1) {
                                Text(verbatim: titleName(g.title, id: g.imdb, kind: g.kind)).recipe(.cardTitle).lineLimit(1)
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
        .padding(DS.Space.s3)
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watching-day")
    }

    /// Nivel 0 (nada) a 3 (de tus días más fuertes), como la leyenda.
    private func fill(_ level: Int) -> Color {
        guard level > 0 else { return DS.fill }
        return DS.orbitalBlue.opacity(DS.Watching.dayFloor + (1 - DS.Watching.dayFloor) * Double(level - 1) / 2)
    }
}

/// Lo que viste en un día, cada título una vez: «2 h 20 min» o «T1 E3 «Nombre», T1 E4» (lo usan «Tu año» y el mapa).
enum WatchingDay {
    static func groups(_ plays: [TraktPlay]) -> [(imdb: String, kind: String, title: String, detail: String)] {
        var order: [String] = [], byTitle: [String: [TraktPlay]] = [:]
        for p in plays { if byTitle[p.imdb] == nil { order.append(p.imdb) }; byTitle[p.imdb, default: []].append(p) }
        return order.compactMap { id in
            guard let list = byTitle[id], let first = list.first else { return nil }
            let detail: String
            if first.kind == "movie" {
                let m = first.minutes
                detail = m > 0 ? (m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min") : ""
            } else {
                detail = list.map { p in
                    guard let s = p.season, let e = p.episode else { return p.episodeTitle ?? "" }
                    return "T\(s) E\(e)" + (p.episodeTitle.map { " «\($0)»" } ?? "")
                }.joined(separator: ", ")
            }
            return (id, first.kind, first.title, detail)
        }
    }
}

/// «Tus géneros» (13 nov 2026, antes una dona de cinco colores): barras de mayor a menor, cada una con su nombre y su parte
/// del total en el mismo renglón y la barra debajo, cada género de su color (`DS.Watching.genreColors`, Fernando, 14 nov 2026;
/// el largo dice cuánto). Se ven cinco; lo demás va junto en «Otros», al final y en gris. Crecen desde la izquierda al llegar (nada con
/// «Reducir movimiento»). VoiceOver: «Comedia, 34 %».
struct WatchingGenres: View {
    let genres: [(name: String, count: Int)]
    let locale: Locale
    let name: (String) -> String
    /// Las barras crecen al llegar, al abrir y al cambiar de periodo.
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Row: Identifiable { let id: String; let label: Text; let count: Int; let rest: Bool }

    var body: some View {
        let total = max(1, genres.reduce(0) { $0 + $1.count })
        let sorted = genres.sorted { $0.count > $1.count }
        let shown = sorted.prefix(DS.Watching.genresShown)
        let rest = sorted.dropFirst(shown.count).reduce(0) { $0 + $1.count }
        let rows = shown.map { Row(id: $0.name, label: Text(verbatim: name($0.name)), count: $0.count, rest: false) }
            + (rest > 0 ? [Row(id: "_rest", label: Text("Otros"), count: rest, rest: true)] : [])
        let most = max(rows.map(\.count).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                let share = Double(row.count) / Double(total)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        row.label.recipe(.secondary).lineLimit(2)
                        Spacer(minLength: DS.Space.s2)
                        Text(share, format: .percent.precision(.fractionLength(0)).locale(locale)).recipe(.data, color: DS.textMuted)
                    }
                    Capsule().fill(DS.fill)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in   // el largo de la barra: su parte del renglón
                                Capsule().fill(row.rest ? DS.fillStrong : DS.Watching.genreColors[i % DS.Watching.genreColors.count])
                                    .frame(width: max(DS.Watching.genreBar, geo.size.width * CGFloat(row.count) / CGFloat(most) * (grown ? 1 : 0)))
                                    .animation(DS.Motion.enter(reduceMotion)?.delay(Double(i) * DS.Watching.barStagger), value: grown)
                            }
                        }
                        .frame(height: DS.Watching.genreBar)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.label)
                .accessibilityValue(Text(share, format: .percent.precision(.fractionLength(0)).locale(locale)))
            }
        }
        .frame(maxWidth: DS.Watching.genresWidth, alignment: .leading)   // en el iPad el nombre y su valor no se alejan
        .onChange(of: genres.map(\.name), initial: true) { _, _ in
            grown = reduceMotion
            Task { @MainActor in grown = true }   // en el siguiente cuadro: así crecen y no aparecen ya hechas
        }
    }
}

/// El carrusel de «Cómo calificas»: los pósters de lo que calificaste con el número elegido, de lo más reciente a lo más
/// viejo; tocar uno abre su ficha.
struct WatchingFiveStars: View {
    @Environment(\.titleName) var titleName
    struct Item: Identifiable { let id: String; let title: String; let kind: String; let poster: String }
    let items: [Item]
    let open: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(items) { item in
                    Button { open(item) } label: {
                        PosterView(url: item.poster, title: titleName(item.title, id: item.id, kind: item.kind))
                            .frame(width: DS.Watching.starPoster)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: titleName(item.title, id: item.id, kind: item.kind)))
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
        .padding(.horizontal, -DS.Space.gutter)
        .scrollClipDisabled()
    }
}
