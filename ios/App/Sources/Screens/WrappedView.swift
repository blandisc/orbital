import SwiftUI
import OrbitalCore

/// Tu Wrapped de la semana, el mes o el año: historias a pantalla completa que avanzan solas (tocar a los lados cambia,
/// mantener pausa) y un quiz que espera tu respuesta. Sale de los mismos números de «Lo que ves».
struct WrappedView: View {
    let stats: WatchingStats
    let language: String
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var paused = false
    @State private var answer: String?
    @State private var progress: Double = 0
    @State private var width: CGFloat = 0

    enum Story: Equatable { case intro, hours, top, genre, streak, busiest, quiz, outro }

    private var stories: [Story] {
        var out: [Story] = [.intro, .hours]
        if stats.top.first != nil { out.append(.top) }
        if stats.genres.first != nil { out.append(.genre) }
        if stats.longestStreak > 1 { out.append(.streak) }
        if stats.busiestDay != nil { out.append(.busiest) }
        if stats.top.count >= 3 { out.append(.quiz) }
        out.append(.outro)
        return out
    }

    var body: some View {
        let story = stories[min(index, stories.count - 1)]
        ZStack {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                bars
                HStack {
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.glass).buttonBorderShape(.circle)
                        .accessibilityLabel(Text("Cerrar")).accessibilityIdentifier("wrapped-close")
                }
                Spacer(minLength: 0)
                content(story).id(index).transition(.opacity.combined(with: .move(edge: .trailing)))
                Spacer(minLength: 0)
            }
            .padding(DS.Space.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        // El fondo va detrás sin medir nada: el póster desenfocado no ensancha las historias.
        .background { background }
        .foregroundStyle(DS.paper)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { g in
            guard story != .quiz || answer != nil else { return }
            step(g.location.x < width * DS.Watching.backZone ? -1 : 1)   // un tercio a la izquierda regresa (también en el iPad)
        })
        .onLongPressGesture(minimumDuration: DS.Watching.holdToPause, perform: {}, onPressingChanged: { paused = $0 })
        .animation(DS.Motion.base(reduceMotion), value: index)
        .task(id: "\(index)|\(paused)|\(answer ?? "")") { await tick(story) }
        .accessibilityAction(named: Text("Siguiente")) { step(1) }
        .accessibilityAction(named: Text("Anterior")) { step(-1) }
        // Contenedor: sin esto el id «wrapped» tapaba el de cada botón de adentro (la ✕ dejaba de ser «wrapped-close»).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wrapped")
    }

    /// Avanza sola salvo en el quiz (espera tu respuesta) y en la pausa.
    private func tick(_ story: Story) async {
        if story == .quiz && answer == nil { progress = 0; return }
        guard !paused else { return }
        let steps = 65
        for i in 0..<steps {
            try? await Task.sleep(for: DS.Watching.story / steps)
            if Task.isCancelled { return }
            progress = Double(i + 1) / Double(steps)
        }
        step(1)
    }

    private func step(_ by: Int) {
        let next = index + by
        if next >= stories.count { close(); return }
        index = max(0, next); progress = 0
    }

    private var bars: some View {
        HStack(spacing: DS.Space.s1) {
            ForEach(stories.indices, id: \.self) { i in
                GeometryReader { geo in
                    Capsule().fill(DS.paper.opacity(DS.Watching.barTrack)).overlay(alignment: .leading) {
                        Capsule().fill(DS.paper).frame(width: geo.size.width * (i < index ? 1 : i == index ? progress : 0))
                    }
                }
                .frame(height: DS.Watching.storyBar)
            }
        }
        .accessibilityHidden(true)
    }

    private var background: some View {
        ZStack {
            DS.backdropDeep
            if let first = stats.top.first {
                Color.clear.overlay {
                    PosterView(url: first.poster, title: first.title, aspect: nil).scaledToFill().blur(radius: DS.Space.s14).opacity(DS.Watching.backdropOpacity)
                }
                .clipped()
            }
            LinearGradient(colors: [.clear, DS.backdropDeep], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var periodName: Text {
        switch stats.period { case .week: Text("Tu semana"); case .month: Text("Tu mes"); case .year: Text("Tu año"); case .all: Text("Todo lo que has visto") }
    }

    @ViewBuilder private func content(_ story: Story) -> some View {
        switch story {
        case .intro:
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("Orbital").recipe(.eyebrow, color: DS.warning)   // ds-exception: rótulo de historia del Wrapped (ámbar), no un porqué
                periodName.font(DS.TextRecipe.display.font)
                Text("en películas y series").recipe(.title, color: DS.onArtSecondary)
            }
        case .hours:
            big(Text(verbatim: "\(stats.hours)"), Text("horas frente a la pantalla"), Text("\(stats.movies) películas y \(stats.episodes) capítulos"))
        case .top:
            if let t = stats.top.first {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text("Lo que más viste").recipe(.eyebrow, color: DS.warning)   // ds-exception: rótulo de historia del Wrapped (ámbar), no un porqué
                    PosterView(url: t.poster, title: t.title).frame(width: DS.Watching.storyPoster)
                    Text(verbatim: t.title).font(DS.TextRecipe.title.font.weight(.bold))
                    Text(t.kind == "movie" ? "\(t.minutes / 60) h" : "\(t.plays) capítulos, \(t.minutes / 60) h").recipe(.body, color: DS.onArtSecondary)
                }
            }
        case .genre:
            if let g = stats.genres.first {
                big(Text(verbatim: WatchingText.genre(g.name, language: language)), Text("fue tu género"), Text("\(g.count) de lo que viste"))
            }
        case .streak:
            big(Text(verbatim: "\(stats.longestStreak)"), Text("días seguidos viendo algo"), Text("tu mejor racha"))
        case .busiest:
            if let b = stats.busiestDay {
                big(Text(b.day, format: .dateTime.weekday(.wide).day().month(.wide)), Text("tu día más intenso"), Text("\(b.minutes / 60) h \(b.minutes % 60) min"))
            }
        case .quiz: quiz
        case .outro:
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("Eso fue").recipe(.title, color: DS.onArtSecondary)
                periodName.font(DS.TextRecipe.display.font)
                Text("Toca para cerrar").recipe(.footnote, color: DS.onArtSecondary)
            }
        }
    }

    /// El quiz: de tres pósters, ¿cuál viste más? Espera tu respuesta y luego dice si atinaste.
    private var quiz: some View {
        let options = Array(stats.top.prefix(3)).sorted { $0.imdb < $1.imdb }
        let right = stats.top.first?.imdb
        return VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("Adivina").recipe(.eyebrow, color: DS.warning)   // ds-exception: rótulo de historia del Wrapped (ámbar), no un porqué
            Text("¿Qué viste más?").font(DS.TextRecipe.title.font.weight(.bold))
            HStack(spacing: DS.Space.s3) {
                ForEach(options, id: \.imdb) { t in
                    Button { if answer == nil { answer = t.imdb } } label: {
                        PosterView(url: t.poster, title: t.title)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(answer == nil ? .clear : t.imdb == right ? DS.brandMoon : .clear, lineWidth: DS.Space.s1))
                            .opacity(answer == nil || t.imdb == right ? 1 : DS.Watching.wrongOpacity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: t.title))
                }
            }
            if let answer {
                Text(answer == right ? "¡Exacto!" : "Casi: fue \(stats.top.first?.title ?? "")").recipe(.cardTitle)
            }
        }
        .sensoryFeedback(.success, trigger: answer) { (_: String?, new: String?) in new.map { $0 == right } ?? false }
    }

    private func big(_ value: Text, _ label: Text, _ detail: Text) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            value.font(.system(size: DS.Watching.storyNumber, weight: .black)).lineLimit(1).minimumScaleFactor(DS.Size.statScale)   // ds-exception: el número enorme de una historia
            label.font(DS.TextRecipe.title.font.weight(.semibold))
            detail.recipe(.body, color: DS.onArtSecondary)
        }
    }
}
