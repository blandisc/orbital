import SwiftUI
import OrbitalCore

// Piezas de «Lo que ves» (docs/producto/muvy-busqueda-premios/prototipo-wrapped.html): la tarjeta de Para ti, un dato
// grande, las barras del periodo, el mapa día por día y los géneros. Los colores de película, serie y las dos son los del
// mapa de «Tu año» (`DS.YearMap`).

/// La puerta de «Lo que ves» arriba de Para ti, «Tu semana en su póster» (Fernando, 30 oct 2026, opción L1): de fondo el
/// arte de lo que más viste esta semana, con su velo; encima el porqué en turquesa, tus horas en grande, «Sobre todo …» con
/// tu racha y tus géneros de la semana. El día por día está adentro.
struct WatchingCard: View {
    /// nil: aún cargando (esqueleto).
    let stats: WatchingStats?
    /// Los géneros de la semana ya en el idioma de la app (los pone quien la usa).
    var genres: [String] = []
    /// nil: solo la tarjeta (dentro de un `NavigationLink`, que recibe el toque; ver `CollectionsCard`).
    var action: (() -> Void)?

    var body: some View {
        if let action { Button(action: action) { card }.buttonStyle(.plain).accessibilityIdentifier("watching-card") }
        else { card.accessibilityIdentifier("watching-card") }
    }

    private var card: some View {
        ZStack(alignment: .bottomLeading) {
            if let top = stats?.top.first {
                PosterView(url: String(format: ForYou.metahubBackground, top.imdb), title: top.title, aspect: nil, bleed: true, maxPoints: DS.Image.wide)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    .accessibilityHidden(true)
                ArtVeil(at: DS.Watching.veilFrom)
            } else {
                DS.surface
            }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Eyebrow(text: Text("Lo que ves · Esta semana"), reason: true)
                if let stats {
                    duration(stats).font(DS.TextRecipe.display.font.weight(.heavy)).foregroundStyle(DS.paper)
                        .lineLimit(1).minimumScaleFactor(DS.Size.statScale).contentTransition(.numericText())
                    facts(stats).recipe(.footnote, color: DS.onArtSecondary).lineLimit(2)
                    if !genres.isEmpty {
                        HStack(spacing: DS.Space.s1) {
                            ForEach(genres.prefix(DS.Watching.genres), id: \.self) { g in
                                Text(verbatim: g).recipe(.caption, color: DS.paper).fontWeight(.semibold).lineLimit(1)
                                    .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1 / 2)
                                    .background(DS.paper.opacity(DS.Watching.chipFill), in: Capsule())
                            }
                        }
                        .padding(.top, DS.Space.s1)
                    }
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.fill)
                        .frame(width: DS.Watching.skeleton, height: DS.Watching.skeletonHeight)
                }
            }
            .padding(DS.Space.s4)
            .onArt()
        }
        .frame(maxWidth: .infinity, minHeight: DS.Watching.cardHeight, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chevron.forward").font(DS.TextRecipe.footnote.font.weight(.bold)).foregroundStyle(DS.onArtSecondary)
                .padding(DS.Space.s4).accessibilityHidden(true)
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }

    /// «4 h 12 min», o solo minutos si no llega a una hora.
    private func duration(_ s: WatchingStats) -> Text {
        let h = s.minutes / 60, m = s.minutes % 60
        return h == 0 ? Text("\(m) min") : m == 0 ? Text("\(h) h") : Text("\(h) h \(m) min")
    }

    /// «Sobre todo The Bear · 5 días seguidos» (o qué viste, si no hay racha).
    private func facts(_ s: WatchingStats) -> Text {
        var parts: [Text] = []
        if let top = s.top.first { parts.append(Text("Sobre todo \(Text(verbatim: top.title).fontWeight(.bold).foregroundStyle(DS.paper))")) }
        if s.currentStreak > 1 { parts.append(Text("\(s.currentStreak) días seguidos")) }
        else {
            if s.episodes > 0 { parts.append(s.episodes == 1 ? Text("1 episodio") : Text("\(s.episodes) episodios")) }
            if s.movies > 0 { parts.append(s.movies == 1 ? Text("1 película") : Text("\(s.movies) películas")) }
        }
        if parts.isEmpty { return Text("Aún nada esta semana") }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
    }
}

/// Un dato grande con su nombre abajo («42 h» · «frente a la pantalla»).
struct WatchingStat: View {
    let value: Text
    let label: Text
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            value.font(DS.TextRecipe.title.font.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            label.recipe(.caption, color: DS.textMuted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // todas las del renglón, del mismo alto
        .padding(DS.Space.s3)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
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

/// El mapa día por día: un cuadrito por día, en el color de lo que viste (película, serie o las dos).
struct WatchingDayGrid: View {
    let start: Date
    let end: Date
    let days: [Date: YearInReview.Day]
    var calendar = Calendar.current

    var body: some View {
        let first = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        let count = max(1, (calendar.dateComponents([.day], from: first, to: end).day ?? 0) + 1)
        let weeks = Int((Double(count) / 7).rounded(.up))
        if weeks <= 6 {
            // Una semana o un mes: como calendario, un renglón por semana y cuadros grandes.
            VStack(alignment: .leading, spacing: DS.YearMap.gap) {
                ForEach(0..<weeks, id: \.self) { w in
                    HStack(spacing: DS.YearMap.gap) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = calendar.date(byAdding: .day, value: w * 7 + d, to: first) ?? first
                            RoundedRectangle(cornerRadius: DS.Radius.xs)
                                .fill(day > end || day < calendar.startOfDay(for: start) ? .clear : color(days[calendar.startOfDay(for: day)]))
                                .aspectRatio(1, contentMode: .fit)   // ds-exception: cuadros cuadrados (un día)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        } else {
            longGrid(first: first, weeks: weeks)
        }
    }

    private func longGrid(first: Date, weeks: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.YearMap.gap) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: DS.YearMap.gap) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = calendar.date(byAdding: .day, value: w * 7 + d, to: first) ?? first
                            RoundedRectangle(cornerRadius: DS.YearMap.radius)
                                .fill(day > end || day < calendar.startOfDay(for: start) ? .clear : color(days[calendar.startOfDay(for: day)]))
                                .frame(width: DS.Watching.cell, height: DS.Watching.cell)
                        }
                    }
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        .accessibilityHidden(true)
    }

    private func color(_ day: YearInReview.Day?) -> Color {
        switch day { case .movies?: DS.YearMap.movies; case .series?: DS.YearMap.series; case .both?: DS.YearMap.both; case nil: DS.fill }
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
                            Capsule().fill(DS.YearMap.both).frame(width: geo.size.width * CGFloat(g.count) / CGFloat(total))
                        }
                    }
                    .frame(height: DS.Watching.genreBar)
                    Text(verbatim: "\(g.count * 100 / total) %").recipe(.caption, color: DS.textMuted).monospacedDigit()
                }
            }
        }
    }
}
