import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Viendo en la TV»: la tarjeta de Inicio sobre lo que se ve ahora en tu Orbital (ola 1: control remoto).
/// Película o episodio: póster, título, avance (interpolado entre sondeos, sin saltar) y −10 · Pausa · +10 · Siguiente.
/// TV en vivo: el canal, «● En vivo» y ▲▼ · Sin sonido. Con letra de accesibilidad grande los botones se apilan con su nombre.
struct NowPlayingCard: View {
    let now: OrbitalRemote.NowPlaying
    let fetchedAt: Date
    let busy: Bool
    let onAction: (String, Double?) -> Void
    let onContinueHere: () -> Void
    /// Con su caja (en Inicio). En la hoja del control remoto, sin caja: la hoja ya es el contenedor.
    var framed = true
    /// Los sustos de la película (si hay mapa): marcados en la barra de avance.
    var scares: [JumpScare] = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var tap = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Label(now.live ? "En la TV · En vivo" : "Viendo en la TV", systemImage: "tv")
                .font(DS.TextRecipe.caption.font.weight(.semibold)).foregroundStyle(DS.textMuted)
            HStack(alignment: .center, spacing: DS.Space.s3) {
                PosterView(url: now.art, title: now.title, aspect: DS.Poster.aspect, whole: true).frame(width: DS.Poster.nowPlayingWidth)
                info
                Spacer(minLength: 0)
            }
            controls
        }
        .padding(framed ? DS.Space.s3 : 0)
        .background(framed ? DS.fill : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var info: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if now.live {
                HStack(spacing: DS.Space.s1) {
                    Text("●").font(DS.TextRecipe.caption.font).foregroundStyle(DS.live)
                    Text("En vivo").font(DS.TextRecipe.caption.font.weight(.semibold)).foregroundStyle(DS.live)
                }
            }
            Text(now.live ? (now.channel ?? now.title) : now.title).font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text).lineLimit(1)
            if now.live {
                if let category = now.category, !category.isEmpty {
                    Text(category).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).lineLimit(1)
                }
            } else {
                if !now.episodeLabel.isEmpty {
                    Text(verbatim: Strings.tvEpisode(season: now.season, episode: now.episode, label: now.episodeLabel, language: AppEnvironment.shared.services.appSettings.uiLanguage)).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).lineLimit(1)
                }
                TimelineView(.periodic(from: fetchedAt, by: DS.NowPlaying.progressTick)) { context in
                    let left = Int(max(0, now.duration - interpolatedPosition(at: context.date)) / 60)
                    Text(timeLeftText(minutes: left)).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint).lineLimit(1)
                }
                TimelineView(.periodic(from: fetchedAt, by: DS.NowPlaying.progressTick)) { context in
                    if scares.isEmpty { DSProgress(fraction: now.duration > 0 ? interpolatedPosition(at: context.date) / now.duration : 0) }
                    else { ScareTimeline(position: interpolatedPosition(at: context.date), duration: now.duration, scares: scares) }
                }
            }
        }
    }

    /// Mientras no está en pausa, el avance se calcula a partir del último sondeo (no salta cada 5 s).
    private func interpolatedPosition(at date: Date) -> Double {
        guard !now.live else { return now.position }
        return now.position(at: date, since: fetchedAt)
    }

    @ViewBuilder private var controls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Space.s2) { buttons(labeled: true) }
            } else {
                // Repartidos a lo ancho (en un iPhone grande no se amontonan a la izquierda).
                HStack(spacing: DS.Space.s2) { buttons(labeled: false) }.frame(maxWidth: .infinity)
            }
        }
        .disabled(busy)
        .opacity(busy ? DS.NowPlaying.busyOpacity : 1)
        .sensoryFeedback(.impact, trigger: tap)
    }

    @ViewBuilder private func buttons(labeled: Bool) -> some View {
        if now.live {
            // Igual que el control remoto: arriba es el siguiente canal, abajo el anterior.
            actionButton(symbol: "chevron.up", text: "Canal siguiente", labeled: labeled) { act("next") }
            actionButton(symbol: "chevron.down", text: "Canal anterior", labeled: labeled) { act("previous") }
            actionButton(symbol: now.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", text: "Sin sonido", labeled: labeled) { act("mute") }
        } else {
            actionButton(symbol: "gobackward.10", text: "Retroceder 10 segundos", labeled: labeled) { act("skip", -10) }
            actionButton(symbol: now.paused ? "play.fill" : "pause.fill", text: now.paused ? "Continuar" : "Pausa", prominent: true, labeled: labeled) { act("toggle") }
            actionButton(symbol: "goforward.10", text: "Adelantar 10 segundos", labeled: labeled) { act("skip", 10) }
            if now.kind == "series" { actionButton(symbol: "forward.end.fill", text: "Siguiente episodio", labeled: labeled) { act("next") } }
        }
        moreMenu
    }

    private var moreMenu: some View {
        DSMoreMenu {
            Button("Salir del video", systemImage: "xmark.circle") { act("stop") }
            if !now.live { Button("Seguir aquí", systemImage: "iphone") { onContinueHere() } }
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity)
    }

    @ViewBuilder private func actionButton(symbol: String, text: LocalizedStringKey, prominent: Bool = false, labeled: Bool, action: @escaping () -> Void) -> some View {
        Group {
            if labeled, prominent {
                Button { tapAndRun(action) } label: { Label(text, systemImage: symbol) }.dsPrimaryButton()
            } else if labeled {
                Button { tapAndRun(action) } label: { Label(text, systemImage: symbol) }.buttonStyle(.glass)
            } else {
                DSIconButton(symbol: symbol, label: text, prominent: prominent) { tapAndRun(action) }.frame(maxWidth: .infinity)
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

    /// Lo que mandaste desde la TV, como un destacado chico (Proyección: el arte es la luz): el fondo del título con su velo,
    /// «Desde la TV · hace 2 minutos», su logo, el dato (episodio o «Película»), «Ver» con el color de su arte y «Descargar»;
    /// descartarla es la ✕ discreta de la esquina.
    var body: some View {
        let background = item.metaID.hasPrefix("tt") ? String(format: ForYou.metahubBackground, item.metaID) : item.poster
        WithArtColors(url: background) { colors in
            ZStack(alignment: .bottomLeading) {
                PosterView(url: background, title: item.title, aspect: nil, bleed: true, maxPoints: DS.Image.bleed)
                    .overlay(ArtVeil(kind: .both, at: DS.Backdrop.scrimMid))
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack(alignment: .firstTextBaseline) {
                        Label { eyebrow } icon: { Image(systemName: "tv") }.recipe(.eyebrow, color: DS.onArtSecondary).lineLimit(1)   // ds-exception: rótulo de estado sobre el arte («En la tele»), no un porqué
                        Spacer(minLength: DS.Space.s2)
                        Button(action: onDismiss) { Image(systemName: "xmark").font(DS.TextRecipe.footnote.font.weight(.semibold)) }
                            .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
                            .accessibilityLabel(Text("Quitar"))
                    }
                    Spacer(minLength: DS.Space.s2)
                    TitleLogo(url: Artwork.logoURL(metaID: item.metaID), title: item.title)
                    DataLine(parts: [detail], color: DS.onArtSecondary)
                    HeroActions {
                        Button(action: onWatch) { Label("Ver", systemImage: "play.fill").lineLimit(1) }.dsArtButton(colors).controlSize(.large)
                        Button(action: onDownload) { Label("Descargar", systemImage: "arrow.down.circle").lineLimit(1) }.buttonStyle(.glass).controlSize(.large)
                    }
                    .padding(.top, DS.Space.s1)
                }
                .padding(DS.Space.s4)
                .onArt()
            }
            .frame(minHeight: DS.Poster.fromTVHeight)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
        }
        .accessibilityElement(children: .contain)
    }

    /// «Desde la TV · hace 2 minutos» (cuándo la mandaste, en el idioma de la app).
    private var eyebrow: Text {
        let sent = Date(timeIntervalSince1970: item.at)
        guard item.at > 0 else { return Text("Desde la TV") }
        return Text("Desde la TV · \(sent.formatted(.relative(presentation: .named).locale(AppEnvironment.shared.uiLocale)))")
    }

    /// «T2 E5» para un episodio, «Película» para una película.
    private var detail: String {
        let language = AppEnvironment.shared.services.appSettings.uiLanguage
        if item.episodeLabel.isEmpty && item.episode == nil { return Strings.kind(item.kind, language: language) }
        return Strings.tvEpisode(season: item.season, episode: item.episode, label: item.episodeLabel, language: language)
    }
}

