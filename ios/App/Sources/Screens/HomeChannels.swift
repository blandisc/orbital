import SwiftUI
import OrbitalCore
import OrbitalModels

/// Canales (Inicio, docs/producto/inicio-benchmark/): tus series siempre al aire, como la tele. Cada canal enseña la imagen
/// y el nombre del capítulo que está pasando (no el arte de la serie), con su barra que avanza sola; cuando termina, entra
/// otro al azar. Tocas uno y entras justo donde va. El «+» abre la hoja para elegir tus canales (los tuyos, unas sugeridas
/// y un buscador). Solo series: con «Películas» en la barra, no se pinta.
struct HomeChannels: View {
    let model: ChannelsModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var choosing = false

    var body: some View {
        let _ = model.track()
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .sectionTitle) {
                DSSectionHead(title: Text("Canales"), eyebrow: Text("Siempre hay un episodio al aire"))
                Spacer(minLength: DS.Space.s2)
                Button { choosing = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
                    .accessibilityLabel(Text("Elegir canales"))
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
        .task { await model.load() }
        .sheet(isPresented: $choosing, onDismiss: { Task { await model.load() } }) { ChannelsSheet(model: model) }
    }

    /// El nombre de la serie en el idioma de la app («The Simpsons» en inglés); los que vienen de la búsqueda, tal cual.
    private func name(_ pick: ChannelsModel.Pick) -> String { Strings.tr(pick.title, language: env.services.appSettings.uiLanguage) }

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
                        // El «cachito»: la imagen del capítulo se acerca despacio, como si estuviera pasando.
                        .phaseAnimator(reduceMotion ? [false] : [false, true]) { view, near in
                            view.scaleEffect(near ? DS.HomeChannels.driftScale : 1)
                        } animation: { _ in DS.HomeChannels.driftAnimation }
                    LinearGradient(stops: [.init(color: .clear, location: DS.HomeChannels.veilStart), .init(color: DS.scrimStrong, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: label(air.episode)).recipe(.caption, color: DS.onArtSecondary).fontWeight(.bold)
                        Text(verbatim: air.episode.name.isEmpty ? name(channel.pick) : air.episode.name).recipe(.cardTitle).lineLimit(1)
                    }
                    .onArt()
                    .padding(.horizontal, DS.Space.s3).padding(.bottom, DS.Space.s4)
                    DSProgress(fraction: air.progress).padding(.horizontal, DS.Space.s3).padding(.bottom, DS.Space.s2)
                }
                .overlay(alignment: .topLeading) {
                    TitleLogo(url: channel.logo, title: name(channel.pick))
                        .frame(maxWidth: DS.HomeChannels.logoWidth, maxHeight: DS.HomeChannels.logoHeight, alignment: .topLeading)
                        .padding(DS.Space.s3).onArt()
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: name(channel.pick)).recipe(.footnote).fontWeight(.semibold).lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text("quedan \(air.minutesLeft) min").recipe(.caption, color: DS.textMuted).monospacedDigit()
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
                Text("Añadir canal").recipe(.footnote).fontWeight(.semibold)
            }
            .frame(width: DS.HomeChannels.addWidth, height: DS.HomeChannels.width / DS.Poster.stillAspect)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-channels-add")
    }
}

/// Elegir tus canales: los tuyos (tocar uno lo quita), unas sugeridas y un buscador para añadir cualquier serie.
struct ChannelsSheet: View {
    let model: ChannelsModel
    @State private var query = ""
    /// La búsqueda va en camino (no se dice «No encontré…» antes de tiempo).
    @State private var searching = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    private func name(_ pick: ChannelsModel.Pick) -> String { Strings.tr(pick.title, language: env.services.appSettings.uiLanguage) }

    var body: some View {
        let _ = model.track()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                    if query.trimmingCharacters(in: .whitespaces).count >= ChannelsModel.minQuery {
                        results
                    } else {
                        section(Text("Tus canales"), model.picks)
                        if !model.suggestions.isEmpty { section(Text("Te sugerimos"), model.suggestions) }
                        Text("Cada canal pasa episodios al azar de esa serie, todo el día. Toca uno y entras justo donde va.")
                            .recipe(.footnote, color: DS.textMuted)
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

    private func section(_ title: Text, _ picks: [ChannelsModel.Pick]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: title, level: .section)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3), count: DS.HomeChannels.gridColumns), spacing: DS.Space.s3) {
                ForEach(picks) { pick in
                    Button { model.toggle(pick) } label: {
                        PosterView(url: pick.poster, title: pick.title)
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
        }
    }

    @ViewBuilder private var results: some View {
        if searching && model.results.isEmpty {
            ProgressView().frame(maxWidth: .infinity)
        } else if model.results.isEmpty {
            Text("No encontré «\(query)». Prueba con otro nombre.").recipe(.footnote, color: DS.textMuted)
        } else {
            VStack(spacing: DS.Space.s2) {
                ForEach(model.results) { pick in
                    let on = model.isChannel(pick.id)
                    // Todo el renglón es el botón; a la derecha, un ícono (no una pastilla de texto): + para añadir, ✓ si ya es canal.
                    Button { model.toggle(pick) } label: {
                        HStack(spacing: DS.Space.s3) {
                            PosterView(url: pick.poster, title: pick.title).frame(width: DS.HomeChannels.resultPoster)
                            Text(verbatim: name(pick)).recipe(.body).fontWeight(.semibold).lineLimit(2).multilineTextAlignment(.leading)
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
