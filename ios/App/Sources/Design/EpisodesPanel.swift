import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas del reproductor: los botones con nombre, «Audio y subtítulos» (`SubtitleDock`) y sus partes.

/// Los episodios de la serie dentro del reproductor.

/// «Episodios» en el reproductor: las temporadas en cápsulas y, debajo, cada episodio con su imagen, su número y su nombre.
/// El que suena dice «Viendo» y el siguiente «Siguiente». Tocar uno lo pone; mientras eliges, el video sigue.
struct EpisodesPanel: View {
    let seasons: [Season]
    let current: String
    let next: String?
    /// Los que se pueden poner (viendo un archivo descargado, solo los bajados); los demás se ven atenuados.
    let playable: Set<String>?
    let pick: (String) -> Void
    let done: () -> Void
    @State private var season: Int?

    var body: some View {
        let shown = season ?? seasons.first { $0.episodes.contains { $0.id == current } }?.season ?? seasons.first?.season
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack {
                Text("Episodios").recipe(.cardTitle, color: DS.text)
                Spacer()
                Button(action: done) { Text("Listo").font(DS.TextRecipe.label.font) }
                    .dsPrimaryButton(size: .small)
                    .accessibilityIdentifier("episodes-done")
            }
            if seasons.count > 1 {
                // La misma pieza de temporadas de la ficha, Mi media y la hoja de episodios, en su versión sobre el video (D8).
                DSSeasonPicker(seasons: seasons.map(\.season), selection: Binding { shown ?? 0 } set: { season = $0 }, onVideo: true)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: DS.Space.s2) {
                        ForEach(seasons.first { $0.season == shown }?.episodes ?? []) { ep in row(ep, season: shown ?? 0).id(ep.id) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: seasons.count, initial: true) { proxy.scrollTo(current, anchor: .center) }
            }
        }
        .padding(DS.Space.s4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("episodes-panel")
    }

    private func row(_ ep: Episode, season: Int) -> some View {
        let now = ep.id == current, upcoming = ep.id == next
        let available = playable?.contains(ep.id) ?? true
        return Button { if !now { pick(ep.id) } } label: {
            HStack(spacing: DS.Space.s3) {
                PosterView(url: ep.thumbnail, title: "", aspect: DS.Poster.stillAspect, bleed: true)
                    .frame(width: DS.PlayerPanel.episodeThumb)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(verbatim: "E" + String(ep.episode)).recipe(.caption)
                    Text(verbatim: ep.title).recipe(.labelLarge, color: DS.text).lineLimit(2)
                    if now { Text("Viendo").recipe(.badge, color: DS.brandMoon) }
                    else if upcoming { Text("Siguiente").recipe(.badge, color: DS.warning) }
                    else if !available { Text("No descargado").recipe(.caption) }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s2)
            .background(now ? DS.fillStrong : .clear, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : DS.Opacity.disabled)
        .accessibilityLabel(Text("Temporada \(Int(season)), episodio \(Int(ep.episode)), \(ep.title)"))
        .accessibilityValue(now ? Text("Viendo") : upcoming ? Text("Siguiente") : Text(verbatim: ""))
        .accessibilityAddTraits(now ? .isSelected : [])
    }
}
