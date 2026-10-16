import SwiftUI
import OrbitalCore
import OrbitalModels

/// «quedan 1 h 40 min» en el idioma de la app.
func timeLeftText(minutes: Int) -> LocalizedStringKey {
    let h = minutes / 60, m = minutes % 60
    if h > 0 && m > 0 { return "quedan \(h) h \(m) min" }
    if h > 0 { return "quedan \(h) h" }
    return "quedan \(m) min"
}

/// «T2 · E5» / «S2 · E5» (o nada si es una película), en el idioma de la app.
@MainActor func episodeText(season: Int?, episode: Int?) -> String {
    guard let episode else { return "" }
    return Strings.episode(season: season, episode: episode, language: AppEnvironment.shared.services.appSettings.uiLanguage)
}

func badgeKey(_ reason: SuggestionReason) -> LocalizedStringKey {
    switch reason {
    case .recommended: "Recomendada"
    case .watching: "Sigues viéndola"
    case .inWatchlist: "En tu lista"
    case .inList(let name): name.isEmpty ? "En tu lista" : "En «\(name)»"
    case .trending: "En tendencia"
    case .popular: "Popular"
    case .onPlatform(let name): "En \(name)"
    }
}

/// Una fila horizontal de portadas con su título.
struct Rail<Content: View>: View {
    let title: LocalizedStringKey
    var trailing: LocalizedStringKey?
    var logo: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: title, trailing: trailing, logo: logo).padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) { content() }.padding(.horizontal, DS.Space.gutter)
            }
        }
    }
}

/// Una portada que lleva a la ficha, con su nombre debajo.
struct TitleLink: View {
    let route: TitleRoute
    var badge: LocalizedStringKey?
    /// El puesto en un Top 10 (chart de Netflix, JustWatch…), si la lista lo trae.
    var rank: Int?
    var progress: Double?
    var width: CGFloat = DS.Poster.railWidth
    /// Un renglón más debajo del nombre («2021 · Película»): distingue títulos que se llaman igual.
    var detail: Text?

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                PosterCard(title: route.title, poster: route.poster, badge: badge, rank: rank, progress: progress, width: width)
                Text(route.title).font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1).frame(width: width, alignment: .leading)
                if let detail { detail.font(DS.font(.xs)).foregroundStyle(DS.textFaint).lineLimit(1).frame(width: width, alignment: .leading) }
            }
        }
        .buttonStyle(.plain)
    }
}

/// «2021 · Película» / «2005–2013 · Serie».
func yearAndKind(year: String, kind: String) -> Text {
    let k = kind == "movie" ? Text("Película") : Text("Serie")
    return year.isEmpty ? k : Text("\(year) · \(k)")
}

/// El dato de una línea de una sugerencia, como `factLine` en la TV: «Serie · T2 · E5», «Película · 2026 · 1 h 45 min».
/// Del más completo al más corto: si no cabe, se quita el año y luego la duración, nunca se corta un número a medias.
@MainActor func factVariants(_ s: Suggestion) -> [Text] {
    let kind = s.kind == "movie" ? Text("Película") : Text("Serie")
    if let next = s.next { return [Text("\(kind) · \(episodeText(season: next.season, episode: next.episode))"), kind] }
    var out: [Text] = []
    let time = s.runtime.map(runtimeText)
    if let year = s.year, let time { out.append(Text("\(kind) · \(String(year)) · \(time)")) }
    if let time { out.append(Text("\(kind) · \(time)")) }
    else if let year = s.year { out.append(Text("\(kind) · \(String(year))")) }
    return out + [kind]
}

/// «45 min», «1 h 45 min», «2 h».
private func runtimeText(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m) min" }
    return m == 0 ? "\(h) h" : "\(h) h \(m) min"
}

extension Suggestion {
    var route: TitleRoute { TitleRoute(kind: kind, metaID: imdb, title: title, poster: poster) }
}

/// «Viendo en la TV»: la tarjeta de Inicio sobre lo que se ve ahora en tu Orbital (ola 1: control remoto).
/// Película o episodio: póster, título, avance (interpolado entre sondeos, sin saltar) y −10 · Pausa · +10 · Siguiente.
/// TV en vivo: el canal, «● En vivo» y ▲▼ · Sin sonido. Con letra de accesibilidad grande los botones se apilan con su nombre.
struct NowPlayingCard: View {
    let now: OrbitalRemote.NowPlaying
    let fetchedAt: Date
    let busy: Bool
    let onAction: (String, Double?) -> Void
    let onContinueHere: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var tap = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Label(now.live ? "En la TV · En vivo" : "Viendo en la TV", systemImage: "tv")
                .font(DS.font(.xs, weight: .semibold)).foregroundStyle(DS.textMuted)
            HStack(alignment: .center, spacing: DS.Space.s3) {
                PosterView(url: now.poster, title: now.title, aspect: DS.Poster.aspect).frame(width: DS.Poster.nowPlayingWidth)
                info
                Spacer(minLength: 0)
            }
            controls
        }
        .padding(DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var info: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if now.live {
                HStack(spacing: DS.Space.s1) {
                    Text("●").font(DS.font(.xs)).foregroundStyle(DS.warning)
                    Text("En vivo").font(DS.font(.xs, weight: .semibold)).foregroundStyle(DS.warning)
                }
            }
            Text(now.live ? (now.channel ?? now.title) : now.title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
            if now.live {
                if let category = now.category, !category.isEmpty {
                    Text(category).font(DS.font(.sm)).foregroundStyle(DS.textMuted).lineLimit(1)
                }
            } else {
                if !now.episodeLabel.isEmpty {
                    Text(now.episodeLabel).font(DS.font(.sm)).foregroundStyle(DS.textMuted).lineLimit(1)
                }
                TimelineView(.periodic(from: fetchedAt, by: DS.NowPlaying.progressTick)) { context in
                    let left = Int(max(0, now.duration - interpolatedPosition(at: context.date)) / 60)
                    Text(timeLeftText(minutes: left)).font(DS.font(.xs)).foregroundStyle(DS.textFaint).lineLimit(1)
                }
                TimelineView(.periodic(from: fetchedAt, by: DS.NowPlaying.progressTick)) { context in
                    DSProgress(fraction: now.duration > 0 ? interpolatedPosition(at: context.date) / now.duration : 0)
                }
            }
        }
    }

    /// Mientras no está en pausa, el avance se calcula a partir del último sondeo (no salta cada 5 s).
    private func interpolatedPosition(at date: Date) -> Double {
        guard !now.paused, !now.live else { return now.position }
        return min(now.duration, now.position + max(0, date.timeIntervalSince(fetchedAt)))
    }

    @ViewBuilder private var controls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Space.s2) { buttons(labeled: true) }
            } else {
                HStack(spacing: DS.Space.s2) { buttons(labeled: false) }
            }
        }
        .disabled(busy)
        .opacity(busy ? DS.NowPlaying.busyOpacity : 1)
        .sensoryFeedback(.impact, trigger: tap)
    }

    @ViewBuilder private func buttons(labeled: Bool) -> some View {
        if now.live {
            actionButton(symbol: "chevron.up", text: "Canal anterior", labeled: labeled) { act("previous") }
            actionButton(symbol: "chevron.down", text: "Canal siguiente", labeled: labeled) { act("next") }
            actionButton(symbol: now.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", text: "Sin sonido", labeled: labeled) { act("mute") }
        } else {
            actionButton(symbol: "gobackward.10", text: "Retroceder 10 segundos", labeled: labeled) { act("skip", -10) }
            actionButton(symbol: now.paused ? "play.fill" : "pause.fill", text: now.paused ? "Reanudar" : "Pausa", prominent: true, labeled: labeled) { act("toggle") }
            actionButton(symbol: "goforward.10", text: "Adelantar 10 segundos", labeled: labeled) { act("skip", 10) }
            actionButton(symbol: "forward.end.fill", text: "Siguiente episodio", labeled: labeled) { act("next") }
        }
        moreMenu
    }

    private var moreMenu: some View {
        Menu {
            Button("Salir del video", systemImage: "xmark.circle") { act("stop") }
            if !now.live { Button("Seguir aquí", systemImage: "iphone") { onContinueHere() } }
        } label: { Image(systemName: "ellipsis.circle") }
        .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
        .accessibilityLabel(Text("Más"))
    }

    @ViewBuilder private func actionButton(symbol: String, text: LocalizedStringKey, prominent: Bool = false, labeled: Bool, action: @escaping () -> Void) -> some View {
        Group {
            if labeled, prominent {
                Button { tapAndRun(action) } label: { Label(text, systemImage: symbol) }.dsPrimaryButton()
            } else if labeled {
                Button { tapAndRun(action) } label: { Label(text, systemImage: symbol) }.buttonStyle(.glass)
            } else {
                DSIconButton(symbol: symbol, label: text, prominent: prominent) { tapAndRun(action) }
            }
        }
        .controlSize(prominent ? .extraLarge : .large)
    }

    private func tapAndRun(_ action: @escaping () -> Void) {
        tap += 1
        action()
    }

    private func act(_ action: String, _ delta: Double? = nil) {
        guard !busy else { return }
        onAction(action, delta)
    }
}

/// «Desde la TV»: lo que mandaste con «Enviar al iPhone», en una tarjeta pequeña bajo «Viendo en la TV».
/// Ver abre el video donde ibas, Descargar lo guarda en el iPhone y Descartar la quita. Con letra de accesibilidad grande los botones se apilan.
struct FromTVCard: View {
    let item: OrbitalRemote.InboxItem
    let onWatch: () -> Void
    let onDownload: () -> Void
    let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Label("Desde la TV", systemImage: "tv")
                .font(DS.font(.xs, weight: .semibold)).foregroundStyle(DS.textMuted)
            HStack(alignment: .center, spacing: DS.Space.s3) {
                PosterView(url: item.poster, title: item.title, aspect: DS.Poster.aspect).frame(width: DS.Poster.nowPlayingWidth)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(item.title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
                    if !item.episodeLabel.isEmpty {
                        Text(item.episodeLabel).font(DS.font(.sm)).foregroundStyle(DS.textMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Space.s2) { buttons }
            } else {
                HStack(spacing: DS.Space.s2) { buttons }
            }
        }
        .padding(DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var buttons: some View {
        Button(action: onWatch) { Label("Ver", systemImage: "play.fill").lineLimit(1) }.dsPrimaryButton().controlSize(.large)
        if dynamicTypeSize.isAccessibilitySize {
            Button(action: onDownload) { Label("Descargar", systemImage: "arrow.down.circle") }.buttonStyle(.glass).controlSize(.large)
            Button(action: onDismiss) { Label("Descartar", systemImage: "xmark") }.buttonStyle(.glass).controlSize(.large)
        } else {
            // Dos íconos con su nombre para VoiceOver: con el texto no caben en un renglón (se cortaban en «Desc…»).
            DSIconButton(symbol: "arrow.down.circle", label: "Descargar", prominent: false, action: onDownload).controlSize(.large)
            DSIconButton(symbol: "xmark", label: "Descartar", prominent: false, action: onDismiss).controlSize(.large)
        }
    }
}
