import SwiftUI
import OrbitalCore
import OrbitalModels

/// Canales (Inicio, docs/producto/inicio-benchmark/): tus series siempre al aire, como la tele. Cada canal enseña la imagen
/// y el nombre del capítulo que está pasando (no el arte de la serie), con su barra que avanza sola; cuando termina, entra
/// otro al azar. Tocas uno y entras justo donde va. El «+» abre la hoja para elegir tus canales (los tuyos, unas sugeridas
/// y un buscador). Solo series: con «Películas» en la barra, no se pinta.
struct HomeChannels: View {
    let model: ChannelsModel
    /// I9 · «Un Simpson al azar» (la dona), junto a «Elegir canales»: también es tele que siempre está al aire.
    var simpsons: (() -> Void)?
    var simpsonsZoom: Namespace.ID?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.titleName) private var titleName
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var choosing = false
    /// Si la fila se ve en Inicio: abajo de la portada no se ve al abrir, y el acercamiento de cada tarjeta gastaba ~18 % de
    /// CPU sin que nadie lo viera (auditoría del 31 oct 2026, R3).
    @State private var onScreen = false

    var body: some View {
        let _ = model.track()
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .sectionTitle) {
                DSSectionHead(title: Text("Canales"), eyebrow: Text("Siempre hay un episodio al aire"))
                Spacer(minLength: DS.Space.s2)
                if let simpsons, let simpsonsZoom {
                    DSIconButton(asset: "Glyphs/donut", label: "Un Simpson al azar", size: .regular, action: simpsons)
                        .matchedTransitionSource(id: "simpsons", in: simpsonsZoom)   // la tele sale de la dona
                        .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
                        .accessibilityIdentifier("home-random-simpsons")
                }
                DSIconButton(symbol: "plus", label: "Elegir canales", size: .regular) { choosing = true }
                    .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
                    .accessibilityIdentifier("home-channels-edit")
            }
            .padding(.horizontal, DS.Space.gutter)
            // Cada medio minuto se vuelve a calcular qué va al aire y cuánto lleva (es una cuenta: no pide nada a la red).
            TimelineView(.periodic(from: .now, by: DS.HomeChannels.tick)) { context in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                        ForEach(model.channels) { channel in
                            if let air = channel.onAir(at: context.date) { card(channel, air) }
                        }
                        addCard
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .onScrollVisibilityChange(threshold: DS.HomeChannels.visibleShare) { onScreen = $0 }
        .task { await model.load() }
        // Las imágenes de lo que va al aire en todos los canales, de antemano: los de la derecha ya no llegan vacíos al
        // deslizar (la tira es perezosa y cada tarjeta pedía su imagen hasta que aparecía).
        .task(id: model.channels.map(\.id)) {
            let now = Date()
            ImagePipeline.shared.prefetchPosters(model.channels.compactMap { channel in
                channel.onAir(at: now).map { $0.episode.still.isEmpty ? channel.background : $0.episode.still }
            })
        }
        .sheet(isPresented: $choosing, onDismiss: { Task { await model.load() } }) { ChannelsSheet(model: model) }
    }

    /// El nombre de la serie en el idioma de la app («The Simpsons» en inglés); los que vienen de la búsqueda, tal cual.
    /// El nombre del canal por la misma puerta que el resto de la app («La Oficina», no «The Office»; revisión 2).
    private func name(_ pick: ChannelsModel.Pick) -> String {
        titleName(Strings.tr(pick.title, language: env.services.appSettings.uiLanguage), id: pick.id, kind: "series")
    }

    private func label(_ episode: ChannelSchedule.Episode) -> String {
        Strings.episode(season: episode.season, episode: episode.episode, language: env.services.appSettings.uiLanguage)
    }

    private func card(_ channel: ChannelsModel.Channel, _ air: ChannelSchedule.OnAir) -> some View {
        let still = air.episode.still.isEmpty ? channel.background : air.episode.still
        return Button {
            // Lo que va al aire en este momento (no en el último tic, que puede ser de hace medio minuto).
            guard let now = channel.onAir(at: Date()) else { return }
            Task {
                await env.play(kind: "series", metaID: channel.id, videoID: now.episode.videoID, title: name(channel.pick),
                               originalTitle: channel.originalTitle, episodeLabel: label(now.episode), poster: channel.pick.poster, at: now.elapsed,
                               offTheRecord: true)   // como la tele: no cuenta como visto
            }
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ZStack(alignment: .bottomLeading) {
                    PosterView(url: still, title: name(channel.pick), aspect: DS.Poster.stillAspect, fallback: channel.background)
                        // La imagen sale de golpe en cuanto llega: sin esto heredaba la animación de 14 s del acercamiento y
                        // aparecía despacio, fundiéndose desde adentro (31 oct 2026).
                        .transaction { $0.animation = nil }
                        // El «cachito»: la imagen del capítulo se acerca despacio, como si estuviera pasando.
                        .modifier(ChannelDrift(running: !reduceMotion && onScreen && scenePhase == .active))
                    ArtVeil(at: DS.HomeChannels.veilStart)
                    // Sobre la imagen, solo el nombre del capítulo; la serie y el dato van abajo, como en Seguir viendo
                    // (Fernando, 2 nov 2026, D6: antes era al revés).
                    if !air.episode.name.isEmpty {
                        // R4: si el nombre se quedó en otro idioma (no hay traducción), lo dice, discreto.
                        VStack(alignment: .leading, spacing: 0) {
                            if let code = air.episode.nameLanguage { DSLanguageMark(code: code, uiLanguage: env.services.appSettings.uiLanguage) }
                            Text(verbatim: air.episode.name).recipe(.cardTitle).lineLimit(1)
                        }
                        .onArt()
                        .padding(.horizontal, DS.Space.s3).padding(.bottom, DS.Space.s4)
                    }
                    DSProgress(fraction: air.progress).padding(.horizontal, DS.Space.s3).padding(.bottom, DS.Space.s2)
                }
                .overlay(alignment: .topLeading) {
                    TitleLogo(url: channel.logo, title: name(channel.pick))
                        .frame(maxWidth: DS.HomeChannels.logoWidth, maxHeight: DS.HomeChannels.logoHeight, alignment: .topLeading)
                        .padding(DS.Space.s3).onArt()
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                // La serie arriba y el capítulo con lo que queda abajo, igual que una tarjeta de Seguir viendo (`StillCard`).
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(verbatim: name(channel.pick)).recipe(.cardTitle).lineLimit(1)
                    DataLine(parts: progressFact(season: air.episode.season, episode: air.episode.episode, leftMinutes: air.minutesLeft,
                                                 language: env.language).components(separatedBy: " · "))
                }
            }
            .frame(width: DS.HomeChannels.width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Entra justo donde va"))
    }

    private var addCard: some View {
        Button { choosing = true } label: {
            VStack(spacing: DS.Space.s2) {
                Image(systemName: "plus").font(DS.TextRecipe.cardTitle.font)
                Text("Añadir canal").recipe(.label)
            }
            .frame(width: DS.HomeChannels.addWidth, height: DS.HomeChannels.width / DS.Poster.stillAspect)
            .dsCard(translucent: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-channels-add")
    }
}

/// Elegir tus canales: los tuyos (tocar uno lo quita), unas sugeridas y un buscador para añadir cualquier serie.
struct ChannelsSheet: View {
    @Environment(\.titleName) var titleName
    let model: ChannelsModel
    @State private var query = ""
    /// La búsqueda va en camino (no se dice «No encontré…» antes de tiempo).
    @State private var searching = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    /// El nombre del canal por la misma puerta que el resto de la app («La Oficina», no «The Office»; revisión 2).
    private func name(_ pick: ChannelsModel.Pick) -> String {
        titleName(Strings.tr(pick.title, language: env.services.appSettings.uiLanguage), id: pick.id, kind: "series")
    }

    var body: some View {
        let _ = model.track()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
                    if query.trimmingCharacters(in: .whitespaces).count >= ChannelsModel.minQuery {
                        results
                    } else {
                        // La nota va pegada a los pósters de arriba (antes tenía el aire de una sección y quedaba suelta).
                        section(Text("Tus canales"), model.picks, note: model.suggestions.isEmpty)
                        if !model.suggestions.isEmpty { section(Text("Te sugerimos"), model.suggestions, note: true) }
                        if env.services.settingsEntries.simpsons { simpsonsSeasons }
                    }
                }
                .padding(DS.Space.gutter)
            }
            .navigationTitle(Text("Tus canales")).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Busca una serie para añadirla"))
            .task(id: query) {
                searching = true
                // Cada tecla cancela la espera anterior: solo se busca cuando dejas de escribir.
                guard (try? await Task.sleep(for: DS.HomeChannels.searchDelay)) != nil else { return }
                await model.search(query)
                searching = false
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    /// De qué temporadas sale la dona (antes en Ajustes; revisión del 11 nov: vive con la dona, junto a los canales).
    private var simpsonsSeasons: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: Text("Un Simpson al azar"), level: .section)
            NavigationLink { SimpsonsSeasonsPage() } label: {
                HStack(spacing: DS.Space.s2) {
                    SettingsRow(title: "Temporadas", symbol: "dice", tint: DS.ListTint.watching,
                                value: SimpsonsSeasonsSection.summary(env.services.appSettings.simpsonsSeasons))
                    Image(systemName: "chevron.right").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textFaint)
                }
                .padding(DS.Space.s3)
                .dsCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("channels-simpsons-seasons")
        }
    }

    private func section(_ title: Text, _ picks: [ChannelsModel.Pick], note: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: title, level: .section)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3), count: DS.HomeChannels.gridColumns), spacing: DS.Space.s3) {
                ForEach(picks) { pick in
                    Button { model.toggle(pick) } label: {
                        PosterView(url: pick.poster, title: titleName(pick.title, id: pick.id, kind: "series"))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: model.isChannel(pick.id) ? "checkmark.circle.fill" : "plus.circle.fill")
                                    .font(DS.TextRecipe.cardTitle.font).symbolRenderingMode(.palette)
                                    .foregroundStyle(DS.onPrimary, DS.primary)
                                    .padding(DS.Space.s1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: name(pick)))
                    .accessibilityValue(model.isChannel(pick.id) ? Text("Es canal") : Text("No es canal"))
                }
            }
            if note {
                Text("Cada canal pasa episodios al azar de esa serie, todo el día. Toca uno y entras justo donde va.")
                    .recipe(.footnote, color: DS.textMuted)
            }
        }
    }

    @ViewBuilder private var results: some View {
        if searching && model.results.isEmpty {
            DSLoadingState()
        } else if model.results.isEmpty {
            Text("No encontré «\(query)». Prueba con otro nombre.").recipe(.footnote, color: DS.textMuted)
        } else {
            VStack(spacing: DS.Space.s2) {
                ForEach(model.results) { pick in
                    let on = model.isChannel(pick.id)
                    // Todo el renglón es el botón; a la derecha, un ícono (no una pastilla de texto): + para añadir, ✓ si ya es canal.
                    Button { model.toggle(pick) } label: {
                        HStack(spacing: DS.Space.s3) {
                            PosterView(url: pick.poster, title: titleName(pick.title, id: pick.id, kind: "series")).frame(width: DS.HomeChannels.resultPoster)
                            Text(verbatim: name(pick)).recipe(.cardTitle).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: DS.Space.s2)
                            Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
                                .font(DS.TextRecipe.section.font)
                                .foregroundStyle(on ? DS.success : DS.text)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? Text("Quitar \(name(pick)) de tus canales") : Text("Añadir \(name(pick)) a tus canales"))
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("channel-\(pick.id)")
                }
            }
        }
    }
}

/// El acercamiento lento de la imagen del capítulo: de 1 a `driftScale` y de regreso, con entrada y salida suaves, en vueltas
/// de `drift` segundos. Lo pinta un reloj a 30 cuadros (antes un `phaseAnimator`, que va a 120 en ProMotion: el paso es de
/// décimas de punto y no se nota) y solo mientras la tarjeta se ve; quieta, vuelve a su tamaño.
private struct ChannelDrift: ViewModifier {
    let running: Bool
    @State private var visible = false
    @State private var start = Date()

    func body(content: Content) -> some View {
        let on = running && visible
        TimelineView(.animation(minimumInterval: DS.HomeChannels.driftFrame, paused: !on)) { context in
            content.scaleEffect(on ? Self.scale(after: context.date.timeIntervalSince(start)) : 1)
        }
        .onScrollVisibilityChange(threshold: DS.HomeChannels.visibleShare) { visible = $0 }
        .onChange(of: on) { _, now in if now { start = Date() } }
    }

    /// Ida y vuelta: sube en `drift` segundos y baja en otros tantos (como un `easeInOut` que se repite).
    static func scale(after elapsed: TimeInterval) -> CGFloat {
        let lap = DS.HomeChannels.drift
        let t = elapsed.truncatingRemainder(dividingBy: lap * 2) / lap
        let p = t <= 1 ? t : 2 - t
        return 1 + (DS.HomeChannels.driftScale - 1) * CGFloat(0.5 - 0.5 * cos(.pi * p))
    }
}
