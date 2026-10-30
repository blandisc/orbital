import SwiftUI
import OrbitalCore

/// «Elegir episodio» después de una orden de voz: la lista sale en el teléfono (la TV sigue con lo que veían) y tocar uno lo
/// pone en la TV, con su fuente recomendada y donde ibas. Sin especiales ni episodios que aún no salen.
struct EpisodePickerSheet: View {
    let title: String
    /// El que se ve ahora en la TV, para marcarlo.
    let currentVideoID: String?
    let load: () async -> [Season]
    let play: (Season, Episode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var seasons: [Season]?
    @State private var season: Int?

    var body: some View {
        NavigationStack {
            Group {
                if let seasons, !seasons.isEmpty {
                    List {
                        Section {
                            ForEach(episodes(seasons)) { episode in row(seasons, episode) }
                        } header: {
                            seasonPicker(seasons)
                        }
                    }
                    .listStyle(.plain)
                } else if seasons != nil {
                    DSEmptyState(symbol: "list.bullet", title: Text("No encontré los episodios"), message: Text("Pídelo por voz: «pon The Office temporada 2 episodio 5»."))
                } else {
                    DSLoadingState().frame(maxHeight: .infinity)
                }
            }
            .navigationTitle(Text(verbatim: title)).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
        .task {
            let loaded = await load()
            // Abre en la temporada de lo que se ve ahora (o en la primera).
            season = loaded.first { s in s.episodes.contains { $0.id == currentVideoID } }?.season ?? loaded.first?.season
            seasons = loaded
        }
        .presentationDetents([.large])
    }

    private func episodes(_ seasons: [Season]) -> [Episode] { seasons.first { $0.season == season }?.episodes ?? [] }

    private func seasonPicker(_ seasons: [Season]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: DS.Space.s2) {
                ForEach(seasons) { s in
                    Button { season = s.season } label: {
                        Text("T\(s.season)").font(DS.TextRecipe.footnote.font.weight(.semibold))
                            .foregroundStyle(s.season == season ? DS.onPrimary : DS.text)
                            .padding(.horizontal, DS.Space.s4).frame(minHeight: DS.Size.touchTarget)
                            .background(s.season == season ? DS.primary : DS.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Temporada \(s.season)"))
                    .accessibilityAddTraits(s.season == season ? .isSelected : [])
                }
            }
            .padding(.vertical, DS.Space.s2)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ seasons: [Season], _ episode: Episode) -> some View {
        let current = episode.id == currentVideoID
        return Button {
            if let s = seasons.first(where: { $0.season == season }) { play(s, episode); dismiss() }
        } label: {
            HStack(spacing: DS.Space.s3) {
                PosterView(url: episode.thumbnail, title: episode.title, aspect: DS.Poster.stillAspect).frame(width: DS.Poster.railWidth)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(verbatim: "\(episode.episode) · \(episode.title)").recipe(.cardTitle).lineLimit(2)
                    if current { Text("En la TV ahora").recipe(.caption, color: DS.live) }
                    else if !episode.overview.isEmpty { Text(verbatim: episode.overview).recipe(.caption, color: DS.textMuted).lineLimit(2) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(current ? DS.live.opacity(DesignTokens.Opacity.fill) : Color.clear)
        .accessibilityHint(Text("Ponerlo en la TV"))
        .accessibilityIdentifier("episode-\(episode.id)")
    }
}
