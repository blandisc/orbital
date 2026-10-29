import SwiftUI
import OrbitalCore
import OrbitalModels

/// Los renglones de episodios de la ficha: la ficha de temporada y cada episodio.

/// Una temporada en la tira de filtros.
struct SeasonChip: Hashable, Identifiable {
    var season: Int
    var isSpecials: Bool
    var id: Int { season }
}

struct EpisodeRowView: View {
    let row: EpisodeRow
    let play: () -> Void
    let download: () -> Void
    /// Marca como visto, o como no visto si ya lo estaba.
    let markWatched: () -> Void
    let chooseSource: () -> Void
    var resumeDownload: () -> Void = {}
    var downloadFraction: Double?
    var playOnTV: (() -> Void)?

    var body: some View { bodyContent.pointerHover(.highlight) }
    @ViewBuilder private var bodyContent: some View {
        // El botón de descargar va junto, no dentro, del que reproduce: anidados, tocar la flecha ponía el episodio.
        // Miniatura, texto y estado en una misma línea central: el estado siempre cae en la misma columna.
        HStack(alignment: .center, spacing: DS.Space.s3) {
            Button(action: play) {
                HStack(alignment: .center, spacing: DS.Space.s3) {
                    ZStack(alignment: .bottom) {
                        PosterView(url: row.thumbnail, title: "\(row.number)", aspect: DS.Poster.stillAspect)
                        if let progress = row.progress { DSProgress(fraction: progress) }
                        // Visto: la imagen se apaga y lleva un ojito (sin escribir «Visto»; la palomita va a la derecha).
                        if row.watched {
                            DS.scrim
                            Image(systemName: "eye.fill").font(DS.TextRecipe.secondary.font).foregroundStyle(DS.text)
                                .frame(maxHeight: .infinity).accessibilityHidden(true)
                        }
                    }
                    .frame(width: DS.Poster.episodeThumbWidth, height: DS.Poster.episodeThumbWidth / DS.Poster.stillAspect).clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        (row.hasTitle ? Text("\(row.number) · \(row.title)") : Text("Episodio \(row.number)")).font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text).lineLimit(2)
                        if hasStatus { status.font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted) }
                        if !row.overview.isEmpty { Text(row.overview).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint).lineLimit(2) }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            stateIcon.frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget, alignment: .trailing)
        }
        .padding(.vertical, DS.Space.s3)
        .opacity(row.airs == nil ? 1 : DesignTokens.Opacity.faint)
        .contextMenu { if row.airs == nil { actions(download: true) } }
    }

    /// Lo que se puede hacer con un episodio: en el «⋯» de su renglón (a la vista) y al mantenerlo presionado.
    @ViewBuilder private func actions(download withDownload: Bool) -> some View {
        if withDownload { Button("Descargar", systemImage: "arrow.down.circle", action: download) }
        Button("Versión de este episodio…", systemImage: "list.bullet.rectangle", action: chooseSource)   // el mismo ícono que «Versión» de la ficha
        // Ya visto: «Marcar como no visto» (sale de lo visto aquí y en Trakt).
        if row.watched { Button("Marcar como no visto", systemImage: "circle", action: markWatched) }
        else { Button("Marcar como visto", systemImage: "checkmark.circle", action: markWatched) }
        if let playOnTV { Button("Ver en la TV", systemImage: "tv", action: playOnTV) }
    }

    private var hasStatus: Bool { row.airs != nil || (!row.watched && row.leftMinutes > 0) || row.download == .done }

    @ViewBuilder private var status: some View {
        if let airs = row.airs { Text("Sale el \(airs, format: .dateTime.day().month(.abbreviated))") }
        else if !row.watched, row.leftMinutes > 0 { Text(timeLeftText(minutes: row.leftMinutes)) }
        else if row.download == .done { Text("Descargado") }
    }

    @ViewBuilder private var stateIcon: some View {
        if row.airs != nil { Image(systemName: "calendar").foregroundStyle(DS.textFaint).accessibilityLabel(Text("Todavía no sale")) }
        else if row.watched { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.good).accessibilityLabel(Text("Visto")) }
        else if row.download == .done { Image(systemName: "arrow.down.circle.fill").foregroundStyle(DS.good).accessibilityLabel(Text("Descargado")) }
        else if row.download == .downloading || row.download == .queued {
            // El mismo anillo que el círculo de Descargar de la ficha.
            DownloadRing(fraction: downloadFraction ?? 0, lineWidth: DS.TitleAction.ringSmallLine)
                .frame(width: DS.TitleAction.ringSmall, height: DS.TitleAction.ringSmall)
        }
        else if row.download == .paused || row.download == .failed {
            // En pausa o falló: seguir donde iba (no empezar de cero con otra fuente).
            Button(action: resumeDownload) {
                Image(systemName: row.download == .failed ? "arrow.clockwise" : "play.circle").foregroundStyle(row.download == .failed ? DS.warning : DS.textMuted)
                    .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
            }
            .buttonStyle(.plain).accessibilityLabel(row.download == .failed ? Text("Reintentar") : Text("Reanudar"))
        }
        else {
            // «⋯» a la vista: Descargar, Elegir versión, Marcar como visto y Ver en la TV (antes solo la flecha de descargar, y
            // elegir la versión de un episodio estaba escondido en mantenerlo presionado).
            Menu { actions(download: true) } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(DS.textMuted).frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
            }
            .accessibilityLabel(Text("Más del episodio"))
            .accessibilityIdentifier("episode-more")
        }
    }
}
