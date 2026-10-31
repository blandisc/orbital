import SwiftUI
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
        return DS.Watching.calendar.opacity(DS.Watching.dayFloor + (1 - DS.Watching.dayFloor) * Double(watched) / Double(most))
    }
}

/// Los géneros como barras horizontales con su parte del total.
struct WatchingGenres: View {
    let genres: [(name: String, count: Int)]
    let name: (String) -> String

    var body: some View {
        let total = max(1, genres.reduce(0) { $0 + $1.count })
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(genres.prefix(5), id: \.name) { g in
                HStack(spacing: DS.Space.s3) {
                    Text(verbatim: name(g.name)).recipe(.footnote).frame(width: DS.Watching.genreLabel, alignment: .leading).lineLimit(1)
                    GeometryReader { geo in
                        Capsule().fill(DS.fillStrong).overlay(alignment: .leading) {
                            Capsule().fill(DS.text.opacity(DS.Watching.genreFill)).frame(width: geo.size.width * CGFloat(g.count) / CGFloat(total))
                        }
                    }
                    .frame(height: DS.Watching.genreBar)
                    Text(verbatim: "\(g.count * 100 / total) %").recipe(.caption, color: DS.textMuted).monospacedDigit()
                        .frame(width: DS.Watching.percentColumn, alignment: .trailing)   // columna fija: las barras terminan parejas
                }
            }
        }
    }
}
