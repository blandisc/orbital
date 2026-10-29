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
                Button(action: done) { Text("Listo").font(DS.TextRecipe.footnote.font.weight(.semibold)) }
                    .buttonStyle(.glassProminent).controlSize(.small).tint(DS.primary).foregroundStyle(DS.onPrimary)
                    .accessibilityIdentifier("episodes-done")
            }
            if seasons.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.s2) {
                            ForEach(seasons) { s in
                                PanelChip(title: Text("T\(s.season)"), selected: s.season == shown) { season = s.season }
                                    .id(s.season)
                                    .accessibilityLabel(Text("Temporada \(s.season)"))
                            }
                        }
                    }
                    // Solo a los lados: de su alto exacto y sin rebote vertical (antes se podía jalar arriba y abajo).
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                    // Los episodios llegan después de abrir (se leen aparte): al llegar, a la temporada que suena.
                    .edgeFade()   // si no caben, las orillas se desvanecen en vez de cortarse
                    .onChange(of: seasons.count, initial: true) { proxy.scrollTo(shown, anchor: .center) }
                }
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
                    Text(verbatim: ep.title).recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(2)
                    if now { Text("Viendo").recipe(.caption, color: DS.brandMoon).fontWeight(.semibold) }
                    else if upcoming { Text("Siguiente").recipe(.caption, color: DS.eyebrow).fontWeight(.semibold) }
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
        .opacity(available ? 1 : DS.PlayerPanel.unavailableOpacity)
        .accessibilityLabel(Text("Temporada \(Int(season)), episodio \(Int(ep.episode)), \(ep.title)"))
        .accessibilityValue(now ? Text("Viendo") : upcoming ? Text("Siguiente") : Text(verbatim: ""))
        .accessibilityAddTraits(now ? .isSelected : [])
    }
}
