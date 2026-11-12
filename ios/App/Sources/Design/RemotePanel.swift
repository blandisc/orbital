import SwiftUI
import OrbitalCore

/// Las piezas del panel del control en el iPad (CT2, 11 nov 2026: «Arriba lo que suena, abajo el control»). Las arma
/// `RemoteSheet.panel`; la hoja del iPhone no las usa.

/// Lo que suena en la tele, arriba del panel: el póster, el nombre, «T1 E3 · quedan 27 min» (en vivo: el canal y lo que
/// pasa) y, si se puede, «Seguir aquí» con su ícono. La barra y los botones del reproductor van debajo (`playerDeck`).
struct RemoteNowHeader: View {
    @Environment(\.titleName) private var titleName
    let now: OrbitalRemote.NowPlaying
    let fetchedAt: Date
    /// El idioma de la app (para «T1 E3 · quedan 27 min»).
    let language: String
    /// «Seguir aquí»: el video pasa de la tele a este aparato, donde ibas. Sin esto (TV en vivo) no sale.
    var continueHere: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            PosterView(url: now.art, title: titleName(now.title, id: now.metaID, kind: now.kind), aspect: DS.Poster.aspect, whole: true)
                .frame(width: DS.Poster.nowPlayingWidth)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Label(now.live ? "En la TV · En vivo" : "Viendo en la TV", systemImage: "tv.and.mediabox")
                    .recipe(.footnote, color: now.live ? DS.live : DS.textMuted).lineLimit(1)
                Text(now.live ? (now.channel ?? now.title) : titleName(now.title, id: now.metaID, kind: now.kind))
                    .recipe(.cardTitle).lineLimit(2)
                facts
            }
            Spacer(minLength: DS.Space.s2)
            if let continueHere {
                DSIconButton(symbol: "iphone", label: "Seguir aquí", action: continueHere).accessibilityIdentifier("remote-continue-here")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var facts: some View {
        if now.live {
            if let category = now.category, !category.isEmpty { Text(verbatim: category).recipe(.footnote, color: DS.textMuted).lineLimit(1) }
        } else {
            // Se vuelve a calcular con el reloj del avance: «quedan» baja sin esperar el siguiente sondeo.
            TimelineView(.periodic(from: fetchedAt, by: DS.NowPlaying.progressTick)) { context in
                let left = Int(max(0, now.duration - now.position(at: context.date, since: fetchedAt)) / 60)
                let episode = now.episodeLabel.isEmpty && now.episode == nil ? nil
                    : Strings.tvEpisode(season: now.season, episode: now.episode, label: now.episodeLabel, language: language)
                Text(verbatim: Vocabulary.factLine([episode, left > 0 ? Strings.timeLeft(minutes: left, language: language) : nil]))
                    .recipe(.footnote, color: DS.textMuted).monospacedDigit().lineLimit(2)
            }
        }
    }
}

/// Un título para mandar a la tele (la tele en reposo, «Seguir viendo»): el renglón de lista de siempre (`RowTile`) con el
/// ícono de la tele a la derecha; mientras va en camino, la ruedita en su lugar.
struct RemoteSendRow: View {
    let title: String
    let art: String?
    let detail: String
    var progress: Double?
    var sending = false

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            RowTile(title: title, thumb: art, detail: detail, progress: progress)
            Group {
                if sending { ProgressView().controlSize(.small) }   // ds-exception: la ruedita ocupa el lugar del ícono mientras va a la tele
                else { Image(systemName: "tv.and.mediabox").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted) }
            }
            .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

/// Una frase para la voz (la tele en reposo y nada a medias): se toca y va como si la dijeras.
struct RemoteHintRow: View {
    let phrase: String

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "mic").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted)
                .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                .accessibilityHidden(true)
            Text(verbatim: "«\(phrase)»").recipe(.label, color: DS.text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
