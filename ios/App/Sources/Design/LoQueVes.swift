import SwiftUI
import Charts
import OrbitalCore

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
    /// Los géneros de la semana ya en el idioma de la app (los pone quien la usa).
    var genres: [String] = []
    /// nil: solo el renglón (dentro de un `NavigationLink`, que recibe el toque; ver `CollectionsCard`).
    var action: (() -> Void)?

    var body: some View {
        if let action { Button(action: action) { row }.buttonStyle(.plain).accessibilityIdentifier("watching-card") }
        else { row.accessibilityIdentifier("watching-card") }
    }

    private var row: some View {
        ListRow(name: name, detail: detail, posters: (stats?.top ?? []).prefix(DS.ParaTiB.matchFan).map(\.poster))
            .contentShape(Rectangle())
    }

    /// «4 h esta semana · sobre todo drama» (o «Aún nada esta semana»; mientras carga, «Esta semana»).
    private var detail: Text {
        guard let s = stats else { return Text("Esta semana") }
        if s.isEmpty { return Text("Aún nada esta semana") }
        let h = s.minutes / 60, m = s.minutes % 60
        let time = h == 0 ? Text("\(m) min esta semana") : Text("\(h) h esta semana")
        guard let genre = genres.first else { return time }
        return Text("\(time) · sobre todo \(genre.lowercased())")
    }
}

/// Las barras del periodo (días, semanas, meses o años), la más alta resaltada.
struct WatchingBars: View {
    let values: [Int]
    let labels: [String]

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: DS.Space.s1) {
            ForEach(values.indices, id: \.self) { i in
                VStack(spacing: DS.Space.s1) {
                    GeometryReader { geo in
                        VStack { Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: DS.Radius.xs).fill(values[i] == top && values[i] > 0 ? DS.brandMoon : DS.fillStrong)
                                .frame(height: max(DS.Watching.barMin, geo.size.height * CGFloat(values[i]) / CGFloat(top)))
                        }
                    }
                    Text(verbatim: labels.indices.contains(i) ? labels[i] : "").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).lineLimit(1)
                        .minimumScaleFactor(DS.Size.statScale)
                }
            }
        }
        .frame(height: DS.Watching.barsHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Minutos por periodo"))
    }
}

/// «Día por día»: en una semana o un mes, un calendario de verdad (L M X J V S D arriba, el número de cada día) con un solo
/// color, azul (Fernando, 31 oct 2026), más intenso según cuánto viste ese día; en un año o siempre, el mapa de cuadritos
/// con el mismo azul.
struct WatchingDayGrid: View {
    let start: Date
    let end: Date
    let minutes: [Date: Int]
    var calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2   // la semana empieza en lunes, como en los calendarios en español
        return c
    }()

    var body: some View {
        let first = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        let count = max(1, (calendar.dateComponents([.day], from: first, to: end).day ?? 0) + 1)
        let weeks = Int((Double(count) / 7).rounded(.up))
        let most = max(minutes.values.max() ?? 0, 1)
        if weeks <= 6 {
            VStack(spacing: DS.YearMap.gap) {
                HStack(spacing: DS.YearMap.gap) {
                    ForEach(0..<7, id: \.self) { d in
                        Text(verbatim: Self.letter(calendar.date(byAdding: .day, value: d, to: first) ?? first, calendar: calendar))
                            .recipe(.caption, color: DS.textMuted).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<weeks, id: \.self) { w in
                    HStack(spacing: DS.YearMap.gap) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = calendar.date(byAdding: .day, value: w * 7 + d, to: first) ?? first
                            let inside = !(day > end || day < calendar.startOfDay(for: start))
                            let watched = minutes[calendar.startOfDay(for: day)] ?? 0
                            ZStack {
                                RoundedRectangle(cornerRadius: DS.Radius.xs).fill(inside ? fill(watched, most) : .clear)
                                if inside {
                                    Text(verbatim: "\(calendar.component(.day, from: day))")
                                        .recipe(.caption, color: watched > 0 ? DS.paper : DS.textMuted).monospacedDigit()
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)   // ds-exception: cuadros cuadrados (un día)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        } else {
            longGrid(first: first, weeks: weeks, most: most)
        }
    }

    private func longGrid(first: Date, weeks: Int, most: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.YearMap.gap) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: DS.YearMap.gap) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = calendar.date(byAdding: .day, value: w * 7 + d, to: first) ?? first
                            RoundedRectangle(cornerRadius: DS.YearMap.radius)
                                .fill(day > end || day < calendar.startOfDay(for: start) ? .clear : fill(minutes[calendar.startOfDay(for: day)] ?? 0, most))
                                .frame(width: DS.Watching.cell, height: DS.Watching.cell)
                        }
                    }
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        .accessibilityHidden(true)
    }

    /// L M X J V S D (miércoles es X, como en los calendarios en español).
    static func letter(_ day: Date, calendar: Calendar) -> String {
        ["D", "L", "M", "X", "J", "V", "S"][calendar.component(.weekday, from: day) - 1]
    }

    /// Azul más intenso según los minutos de ese día; sin nada, el relleno de siempre.
    private func fill(_ watched: Int, _ most: Int) -> Color {
        guard watched > 0 else { return DS.fill }
        return DS.orbitalBlue.opacity(DS.Watching.dayFloor + (1 - DS.Watching.dayFloor) * Double(watched) / Double(most))
    }
}

/// Los géneros como una dona (Fernando, 31 oct 2026): cada uno de su color (los de las listas, `DS.Watching.genreColors`),
/// el principal en el centro y al lado su nombre y su parte del total. Lo que no cabe en cinco va junto en «Otros».
struct WatchingGenres: View {
    let genres: [(name: String, count: Int)]
    let name: (String) -> String

    private struct Slice: Identifiable { let id: String; let label: Text; let count: Int; let color: Color }

    var body: some View {
        let total = max(1, genres.reduce(0) { $0 + $1.count })
        let shown = genres.prefix(DS.Watching.genreColors.count)
        let rest = genres.dropFirst(shown.count).reduce(0) { $0 + $1.count }
        let slices = shown.enumerated().map { i, g in Slice(id: g.name, label: Text(verbatim: name(g.name)), count: g.count, color: DS.Watching.genreColors[i]) }
            + (rest > 0 ? [Slice(id: "_rest", label: Text("Otros"), count: rest, color: DS.fillStrong)] : [])
        HStack(spacing: DS.Space.s5) {
            Chart(slices) { s in
                SectorMark(angle: .value("count", s.count), innerRadius: .ratio(DS.Watching.donutHole), angularInset: DS.Watching.donutGap)
                    .foregroundStyle(s.color).cornerRadius(DS.Radius.xs)
            }
            .chartLegend(.hidden)
            .frame(width: DS.Watching.donut, height: DS.Watching.donut)
            .overlay {
                if let first = slices.first {
                    VStack(spacing: 0) {
                        Text(verbatim: "\(first.count * 100 / total) %").font(DS.TextRecipe.title.font.weight(.heavy)).foregroundStyle(first.color)
                            .monospacedDigit()
                        first.label.recipe(.caption, color: DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                    }
                    .frame(width: DS.Watching.donut * DS.Watching.donutHole * DS.Watching.donutLabel)
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(slices) { s in
                    HStack(spacing: DS.Space.s2) {
                        Circle().fill(s.color).frame(width: DS.Watching.genreDot, height: DS.Watching.genreDot)
                        s.label.recipe(.footnote).lineLimit(1)
                        Spacer(minLength: DS.Space.s1)
                        Text(verbatim: "\(s.count * 100 / total) %").recipe(.caption, color: DS.textMuted).monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// «Tus 5 estrellas» (Fernando, 31 oct 2026, opción R1): los pósters de lo que calificaste con 5, de lo más reciente a lo
/// más viejo; tocar uno abre su ficha.
struct WatchingFiveStars: View {
    struct Item: Identifiable { let id: String; let title: String; let kind: String; let poster: String }
    let items: [Item]
    let open: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(items) { item in
                    Button { open(item) } label: {
                        PosterView(url: item.poster, title: item.title)
                            .frame(width: DS.Watching.starPoster)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: item.title))
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
        .padding(.horizontal, -DS.Space.gutter)
        .scrollClipDisabled()
    }
}
