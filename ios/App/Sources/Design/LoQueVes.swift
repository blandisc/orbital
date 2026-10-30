import SwiftUI
import OrbitalCore

// Piezas de «Lo que ves» (docs/producto/muvy-busqueda-premios/prototipo-wrapped.html): la tarjeta de Para ti, un dato
// grande, las barras del periodo, el mapa día por día y los géneros. Los colores de película, serie y las dos son los del
// mapa de «Tu año» (`DS.YearMap`).

/// La tarjeta de Lo que ves en Para ti: las horas de la semana en grande, la racha y un collage de lo que viste de fondo.
struct WatchingCard: View {
    /// nil: aún cargando (esqueleto).
    let stats: WatchingStats?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                collage
                // El velo desde abajo a la izquierda, donde va el texto: los pósters del fondo no se leen a través de las letras.
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: DS.scrimStrong, location: DS.Watching.veilFrom), .init(color: DS.scrimStrong, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [DS.scrimStrong, .clear], startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Lo que ves").recipe(.eyebrow, color: DS.onArtSecondary)
                    if let stats {
                        Text("\(stats.hours) h esta semana").font(DS.TextRecipe.display.font).foregroundStyle(DS.paper)
                            .lineLimit(1).minimumScaleFactor(DS.Size.statScale).contentTransition(.numericText())
                        HStack(spacing: DS.Space.s3) {
                            Label { Text("\(stats.titles) títulos") } icon: { Image(systemName: "film.stack") }
                            if stats.currentStreak > 1 { Label { Text("\(stats.currentStreak) días seguidos") } icon: { Image(systemName: "flame.fill") } }
                        }
                        .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.onArtSecondary)
                    } else {
                        RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.fill).frame(width: DS.Watching.skeleton, height: DS.Watching.skeletonHeight)
                    }
                }
                .padding(DS.Space.s4)
            }
            .frame(height: DS.Watching.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watching-card")
    }

    private var collage: some View {
        HStack(spacing: DS.Space.s1) {
            ForEach((stats?.top.prefix(5)).map(Array.init) ?? [], id: \.imdb) { t in
                PosterView(url: t.poster, title: t.title).frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.surface)
        .saturation(DS.Watching.collageSaturation)
        .accessibilityHidden(true)
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
