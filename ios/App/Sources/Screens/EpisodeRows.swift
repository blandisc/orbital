import SwiftUI
import OrbitalCore
import OrbitalModels

/// Los renglones de episodios de la ficha: la ficha de temporada y cada episodio.

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
    /// Tus estrellas de este capítulo (en Trakt) y calificarlo: solo se ofrecen en los que ya viste.
    var rating: Double?
    var rate: ((Double?) -> Void)?
    /// El color del arte de la ficha: «quedan 20 min» del episodio que vas viendo va en él.
    var accent: Color = DS.accent
    /// Como tarjeta (la fila de episodios del iPad y la Mac, como la TV): la imagen grande y el nombre debajo.
    var card = false
    @Environment(\.colorScheme) private var scheme

    /// El que vas viendo (con avance y sin terminar): se distingue en la lista (O1).
    private var inProgress: Bool { row.progress != nil && !row.watched && row.airs == nil }
    /// En claro, el color del arte se oscurece para leerse sobre el papel (como en `ActionTileLabel`).
    private var ink: Color { scheme == .light ? accent.mix(with: DS.backdropDeep, by: DS.TitleAction.lightDeepen) : accent }

    var body: some View {
        if card { cardContent.pointerHover(.highlight) } else { bodyContent.pointerHover(.highlight) }
    }

    /// La tarjeta: la imagen (con su avance, el ▶ del que vas viendo y el ojito de visto), el nombre, lo que falta y la
    /// sinopsis; lo demás (descargar, versión, marcar, la TV) en «⋯» y al mantenerla presionada.
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Button(action: play) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ZStack(alignment: .bottom) {
                        PosterView(url: row.thumbnail, title: "\(row.number)", aspect: DS.Poster.stillAspect)
                        if let progress = row.progress { DSProgress(fraction: progress, height: inProgress ? DS.Space.s2 : DS.Space.s1) }
                        if row.watched {
                            DS.scrim
                            Image(systemName: "eye.fill").font(DS.TextRecipe.secondary.font).foregroundStyle(DS.text)
                                .frame(maxHeight: .infinity).accessibilityHidden(true)
                        }
                    }
                    .frame(width: DS.EpisodeRow.cardWidth, height: DS.EpisodeRow.cardWidth / DS.Poster.stillAspect)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    (row.hasTitle ? Text("\(row.number) · \(row.title)") : Text("Episodio \(row.number)"))
                        .font(DS.TextRecipe.labelLarge.font).foregroundStyle(DS.text).lineLimit(1)
                    if hasStatus { status.font(inProgress ? DS.TextRecipe.badge.font : DS.TextRecipe.caption.font).foregroundStyle(inProgress ? ink : DS.textMuted) }
                    if !row.overview.isEmpty { Text(row.overview).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint).lineLimit(2) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: DS.EpisodeRow.cardWidth, alignment: .leading)
        .opacity(row.airs == nil ? 1 : DS.Opacity.dimmed)
        .contextMenu { if row.airs == nil { actions(download: true) } }
    }
    @ViewBuilder private var bodyContent: some View {
        // El botón de descargar va junto, no dentro, del que reproduce: anidados, tocar la flecha ponía el episodio.
        // Miniatura, texto y estado en una misma línea central: el estado siempre cae en la misma columna.
        HStack(alignment: .center, spacing: DS.Space.s3) {
            Button(action: play) {
                HStack(alignment: .center, spacing: DS.Space.s3) {
                    ZStack(alignment: .bottom) {
                        PosterView(url: row.thumbnail, title: "\(row.number)", aspect: DS.Poster.stillAspect)
                        if let progress = row.progress {
                            // El que vas viendo: el ▶ sobre la imagen y la barra al doble de gruesa (O1).
                            DSProgress(fraction: progress, height: inProgress ? DS.Space.s2 : DS.Space.s1)
                        }
                        if inProgress {
                            Image(systemName: "play.fill").font(DS.TextRecipe.badge.font).foregroundStyle(DS.paper)
                                .frame(width: DS.EpisodeRow.play, height: DS.EpisodeRow.play).glassEffect(.regular, in: Circle())
                                .frame(maxHeight: .infinity).accessibilityHidden(true)
                        }
                        // Visto: la imagen se apaga y lleva un ojito (sin escribir «Visto»; la palomita va a la derecha).
                        if row.watched {
                            DS.scrim
                            Image(systemName: "eye.fill").font(DS.TextRecipe.secondary.font).foregroundStyle(DS.text)
                                .frame(maxHeight: .infinity).accessibilityHidden(true)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: DS.Poster.episodeThumbWidth, height: DS.Poster.episodeThumbWidth / DS.Poster.stillAspect).clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        (row.hasTitle ? Text("\(row.number) · \(row.title)") : Text("Episodio \(row.number)")).font(DS.TextRecipe.labelLarge.font).foregroundStyle(DS.text).lineLimit(2)
                        if hasStatus { status.font(inProgress ? DS.TextRecipe.badge.font : DS.TextRecipe.caption.font).foregroundStyle(inProgress ? ink : DS.textMuted) }
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
        // Calificar el capítulo: las estrellas en su propio renglón bajo el texto, fuera del botón que reproduce (tocarlas no
        // lo pone).
        .padding(.bottom, row.watched && rate != nil ? DS.Rating.episodeRow : 0)
        .overlay(alignment: .bottomLeading) {
            if row.watched, let rate {
                RatingStars(value: rating, size: DS.Rating.starEpisode, onChange: rate)
                    .padding(.leading, DS.Poster.episodeThumbWidth + DS.Space.s3)
                    .padding(.bottom, DS.Space.s3)
                    .accessibilityIdentifier("episode-rating")
            }
        }
        .opacity(row.airs == nil ? 1 : DS.Opacity.dimmed)
        .contextMenu { if row.airs == nil { actions(download: true) } }
    }

    /// Lo que se puede hacer con un episodio: en el «⋯» de su renglón (a la vista) y al mantenerlo presionado.
    @ViewBuilder private func actions(download withDownload: Bool) -> some View {
        if withDownload { Button("Descargar", systemImage: "arrow.down.circle", action: download) }
        Button("Versión de este episodio…", systemImage: "list.bullet.rectangle", action: chooseSource)   // el mismo ícono que «Versión» de la ficha
        // Ya visto: «Marcar como no visto» (sale de lo visto aquí y en Trakt).
        if row.watched { Button("Marcar como no visto", systemImage: "circle", action: markWatched) }
        else { Button("Marcar como visto", systemImage: "checkmark.circle", action: markWatched) }
        if let playOnTV { Button("Ver en la TV", systemImage: "tv.and.mediabox", action: playOnTV) }
    }

    private var hasStatus: Bool { row.airs != nil || (!row.watched && row.leftMinutes > 0) || row.download == .done }

    @ViewBuilder private var status: some View {
        if let airs = row.airs { Text("Sale el \(Strings.date(airs, .dayMonthShort, language: AppEnvironment.shared.services.appSettings.uiLanguage))") }
        else if !row.watched, row.leftMinutes > 0 { Text(timeLeftText(minutes: row.leftMinutes)) }
        else if row.download == .done { Text("Descargado") }
    }

    /// La palomita siempre está (invisible si no es vista): así, al marcar el episodio, se dibuja en su lugar en vez de aparecer
    /// de golpe. Lo demás (descargado, bajando, «⋯») solo mientras no es visto.
    @ViewBuilder private var stateIcon: some View {
        if row.airs != nil { Image(systemName: "calendar").foregroundStyle(DS.textFaint).accessibilityLabel(Text("Todavía no sale")) }
        else {
            ZStack(alignment: .trailing) {
                WatchedMark(watched: row.watched)
                if !row.watched { unwatchedIcon.transition(.opacity) }
            }
        }
    }

    @ViewBuilder private var unwatchedIcon: some View {
        if row.download == .done { Image(systemName: "arrow.down.circle.fill").foregroundStyle(DS.good).accessibilityLabel(Text("Descargado")) }
        else if row.download == .downloading || row.download == .queued {
            // El mismo anillo que el círculo de Descargar de la ficha.
            DownloadRing(fraction: downloadFraction ?? 0, lineWidth: DS.TitleAction.ringSmallLine)
                .frame(width: DS.TitleAction.ringSmall, height: DS.TitleAction.ringSmall)
        }
        else if row.download == .paused || row.download == .failed {
            // En pausa o falló: seguir donde iba (no empezar de cero con otra fuente). El mismo anillo con «Seguir» de Descargas.
            DownloadRingButton(fraction: downloadFraction ?? 0, action: row.download == .failed ? .retry : .resume, perform: resumeDownload)
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
