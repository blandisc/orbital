import SwiftUI
import OrbitalCore
import OrbitalModels

// El control del iPhone se acomoda a lo que ves (Fernando, 26 nov 2026: IV-A, IV-B y CT-A de docs/producto/control-iphone/):
// - IV-A «Cómo lo ves»: idioma, subtítulos y versión en una hoja del iPhone, en palabras normales y sin el pad. La versión se
//   pone en la TV en el mismo minuto.
// - IV-B: un toque en Idioma o Subtítulos cambia a lo siguiente más probable (`TrackCycle`); mantenerlas abre la hoja.
// - CT-A: arriba del pad, lo que tienes enfocado en la TV con su botón principal, para no levantar la vista.

/// IV-A: la hoja «Cómo lo ves», con el pulido de los ajustes de Apple: arriba lo que suena y cómo lo estás viendo en una línea
/// («Inglés 5.1 · Español · 4K HDR»); abajo tres grupos de renglones con palomita. Cada pista dice su idioma grande y lo demás
/// («5.1», «SDH») en gris debajo; cada versión, su calidad en palabras y sus insignias de disco (4K · HDR) a la derecha.
struct RemoteWatchSheet: View {
    let model: TVNowModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = model.track()
        ScrollView {
            DSSheet(title: Text("Cómo lo ves"), spacing: DS.Space.s4) {
                if let now = model.now {
                    hero(now)
                    if !now.audioTracks.isEmpty {
                        section("Idioma", symbol: "waveform")
                        VersionGroup(inset: DSListRow.textInset) {
                            ForEach(now.audioTracks) { t in
                                let p = Self.split(t.label)
                                DSListRow(lead: .symbol(t.selected ? "speaker.wave.2.fill" : "speaker.wave.2"), title: Text(verbatim: p.name),
                                            detail: p.rest.map { Text(verbatim: $0) }, mark: t.selected ? .check : .none,
                                            identifier: "watch-audio-\(t.id)", action: { Task { await model.control("audio", track: t.id) } }, selected: t.selected)
                            }
                        }
                    }
                    if !now.subtitleTracks.isEmpty {
                        section("Subtítulos", symbol: "captions.bubble")
                        VersionGroup(inset: DSListRow.textInset) {
                            let none = !now.subtitleTracks.contains(where: \.selected)
                            DSListRow(lead: .symbol("nosign"), title: Text("Sin subtítulos"), mark: none ? .check : .none,
                                        identifier: "watch-subs-no", action: { Task { await model.control("subtitles", track: "no") } }, selected: none)
                            ForEach(now.subtitleTracks) { t in
                                let p = Self.split(t.label)
                                DSListRow(lead: .symbol(t.selected ? "captions.bubble.fill" : "captions.bubble"), title: Text(verbatim: p.name),
                                            detail: p.rest.map { Text(verbatim: $0) }, mark: t.selected ? .check : .none,
                                            identifier: "watch-subs-\(t.id)", action: { Task { await model.control("subtitles", track: t.id) } }, selected: t.selected)
                            }
                        }
                    }
                    // En vivo o sin ficha (un juego, un archivo propio) no hay otras versiones: sin sección vacía.
                    if !now.live, now.metaID != nil { versions }
                }
            }
            .dsSheetContent()
        }
        // Por capítulo: si la TV pasa al siguiente con la hoja abierta, se piden las suyas (no se pone una del anterior).
        .task(id: model.now.map { $0.videoID ?? $0.metaID ?? $0.title }) { await model.loadVersions() }
        // Si en la TV se acaba lo que suena, la hoja ya no tiene de qué hablar.
        .onChange(of: model.now == nil) { _, gone in if gone { dismiss() } }
        .accessibilityIdentifier("remote-watch-sheet")
    }

    /// Lo que suena: el póster, el nombre y, en turquesa, cómo lo ves ahora.
    private func hero(_ now: OrbitalRemote.NowPlaying) -> some View {
        HStack(spacing: DS.Space.s4) {
            PosterView(url: now.art, title: now.title, fallback: now.artFallback)
                .frame(width: DS.Remote.watchPoster)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: now.title).recipe(.sectionQuiet, color: DS.text).lineLimit(2)
                if !now.episodeLabel.isEmpty { Text(verbatim: now.episodeLabel).recipe(.footnote, color: DS.textMuted).lineLimit(1) }
                Text(verbatim: Self.summary(now)).recipe(.label, color: DS.accent).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func section(_ title: LocalizedStringKey, symbol: String) -> some View {
        VersionGroupHeader(title: Text("\(Image(systemName: symbol)) \(Text(title))"))
    }

    @ViewBuilder private var versions: some View {
        section("Versión", symbol: "square.stack")
        if model.versionsLoading {
            DSInlineProgress(text: Text("Buscando versiones en tu TV…"))
        } else if model.versionsFailed {
            DSNotice(text: "No pude traer las versiones de tu TV. Revisa que esté prendida.", tone: .warn)
        } else if let list = model.versions?.list, !list.isEmpty {
            if model.versionSwitchFailed {
                DSNotice(text: "Tu TV no cambió de versión. Revisa que esté prendida e intenta otra vez.", tone: .warn)
            }
            VersionGroup(inset: DSListRow.textInset) {
                ForEach(Array(list.prefix(DS.Remote.versionsShown).enumerated()), id: \.element.id) { i, v in
                    DSListRow(lead: .symbol(i == 0 ? DS.Symbol.recommended : "film"), title: Self.quality(v), detail: Self.detail(v, first: i == 0),
                                identifier: "watch-version-\(i)", action: {
                                    // Se cierra cuando la TV la puso; si no, se queda abierta y lo dice.
                                    Task { if await model.switchVersion(v) { dismiss() } }
                                }, trailing: AnyView(QualityBadges(items: Self.badges(v)).padding(.trailing, DS.Space.s2)))
                }
            }
            Text("Cambia en la TV en el mismo minuto; la imagen se corta unos segundos.").recipe(.footnote, color: DS.textMuted)
                .padding(.horizontal, DS.Space.s2)
        } else if model.versions != nil {
            DSNotice(text: "Tu TV no encontró otras versiones que arranquen al instante.")
        }
    }

    /// «Inglés 5.1 · 1080p» → («Inglés», «5.1 · 1080p»); «Español latino» queda entero.
    static func split(_ label: String) -> (name: String, rest: String?) {
        let parts = label.components(separatedBy: " · ")
        var head = parts[0].split(separator: " ").map(String.init)
        var extra = Array(parts.dropFirst())
        // Lo técnico del final del nombre («5.1», «Atmos», «SDH») baja a la segunda línea.
        while let last = head.last, head.count > 1, last.first?.isNumber == true || (last == last.uppercased() && last != last.lowercased()) || last == "Atmos" {
            extra.insert(head.removeLast(), at: 0)
        }
        return (head.joined(separator: " "), extra.isEmpty ? nil : extra.joined(separator: " · "))
    }

    /// «Inglés 5.1 · Español · 4K HDR»: el audio, los subtítulos (o «Sin subtítulos») y la calidad de lo puesto.
    static func summary(_ now: OrbitalRemote.NowPlaying) -> String {
        let audio = now.audioTracks.first(where: \.selected).map { split($0.label).name }
        let subs = now.subtitleTracks.first(where: \.selected).map { split($0.label).name } ?? String(localized: "Sin subtítulos")
        return [audio, subs].compactMap { $0 }.joined(separator: " · ")
    }

    /// La calidad en palabras: «Ultra HD 4K», «Full HD», «HD».
    static func quality(_ v: OrbitalRemote.Version) -> Text {
        switch v.resolution.lowercased() {
        case "4k", "2160p": Text("Ultra HD 4K")
        case "1080p": Text("Full HD")
        case "720p": Text("HD")
        case "": Text("Versión")
        default: Text(verbatim: v.resolution)
        }
    }

    static func badges(_ v: OrbitalRemote.Version) -> [String] {
        [["4k", "2160p"].contains(v.resolution.lowercased()) ? "4K" : nil, v.hdr ? "HDR" : nil].compactMap { $0 }   // las de disco; 1080p ya lo dice el nombre
    }

    /// «La que pondría tu TV · Español, Inglés · Atmos · 2.1 GB».
    static func detail(_ v: OrbitalRemote.Version, first: Bool) -> Text {
        let parts = [v.languages.prefix(2).joined(separator: ", "), v.audio, v.size].filter { !$0.isEmpty }.joined(separator: " · ")
        if first { return parts.isEmpty ? Text("La que pondría tu TV") : Text("La que pondría tu TV · \(parts)") }
        return Text(verbatim: parts)
    }
}

/// IV-B: Idioma, Subtítulos y Versión en la fila del reproductor. Un toque cambia; mantener (o Versión) abre la hoja.
struct RemoteWatchKeys: View {
    let model: TVNowModel
    let now: OrbitalRemote.NowPlaying
    let open: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let audio = now.audioTracks.first(where: \.selected)
        let subs = now.subtitleTracks.first(where: \.selected)
        RemoteKey(symbol: "waveform", title: audio.map { Text(verbatim: RemoteWatchKeys.short($0.label)) } ?? Text("Idioma"), longPress: open) {
            // Una TV de antes no manda sus pistas: la tecla de la TV las cambia allá, como siempre.
            if now.audioTracks.isEmpty { Task { await model.press(.alt) } }
            else if let next = TrackCycle.nextAudio(now.audioTracks) { Task { await model.control("audio", track: next) } } else { open() }
        }
        .accessibilityLabel(Text("Idioma"))
        .accessibilityValue(audio.map { Text(verbatim: $0.label) } ?? Text("Sin elegir"))
        .accessibilityHint(Text("Toca para cambiar; mantén para ver todo"))
        .accessibilityIdentifier("remote-audio")
        RemoteKey(symbol: subs == nil ? "captions.bubble" : "captions.bubble.fill",
                  title: subs.map { Text(verbatim: RemoteWatchKeys.short($0.label)) } ?? Text("Sin subtítulos"), longPress: open) {
            if now.subtitleTracks.isEmpty { Task { await model.press(.alt) } }
            else if let next = TrackCycle.toggleSubtitles(now.subtitleTracks, language: env.services.appSettings.uiLanguage) {
                Task { await model.control("subtitles", track: next) }
            } else { open() }
        }
        .accessibilityLabel(Text("Subtítulos"))
        .accessibilityValue(subs.map { Text(verbatim: $0.label) } ?? Text("Sin subtítulos"))
        .accessibilityHint(Text("Toca para ponerlos o quitarlos; mantén para ver todo"))
        .accessibilityIdentifier("remote-subtitles")
        RemoteKey(symbol: "square.stack", title: Text("Versión"), action: open)
            .accessibilityIdentifier("remote-version")
    }

    /// Solo lo primero de la pista («Inglés», no «Inglés · Subtítulos · de…» cortado); el nombre completo va en la hoja.
    static func short(_ label: String) -> String { TrackCycle.short(label) }
}

/// CT-A: lo enfocado en la TV, arriba del pad, como la tarjeta de «Ahora suena» de Apple: el arte desenfocado de fondo, el
/// póster con sombra, «En tu TV» en turquesa, el nombre grande y un botón principal de tamaño normal («Ver», «Jugar»…, lo que
/// diga la TV). El atajo («Mi lista») no se repite aquí: ya está en la fila de teclas de abajo.
struct RemoteFocusCard: View {
    let model: TVNowModel
    let focus: OrbitalRemote.Focus

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            PosterView(url: focus.art, title: focus.title)
                .frame(width: DS.Remote.focusPoster)
                .shadow(DS.Elevation.high)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Label { Text("En tu TV") } icon: { Image(systemName: "tv") }
                    .recipe(.eyebrow, color: DS.eyebrow).foregroundStyle(DS.eyebrow)
                Text(verbatim: focus.title).recipe(.sectionQuiet, color: DS.text).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = focus.detail { Text(verbatim: detail).recipe(.footnote, color: DS.textMuted).lineLimit(1) }
                Button { Task { await model.press(.select) } } label: {
                    Label { model.legend["select"].map { Text(tv: $0) } ?? Text("Abrir") } icon: { Image(systemName: focus.watchable ? "play.fill" : "arrow.up.forward") }
                        .frame(minWidth: DS.Remote.focusButton)
                }
                .dsPrimaryButton(size: .regular)
                .padding(.top, DS.Space.s2)
                .accessibilityIdentifier("remote-focus-select")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Space.s4)
        .background {
            // El arte mismo, desenfocado y oscurecido: la tarjeta toma el color de lo que ves (como Música en la pantalla bloqueada).
            GeometryReader { geo in
                PosterView(url: focus.art, title: focus.title, aspect: nil, bleed: true, decorative: true)
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
            }
                .blur(radius: DS.Remote.focusBlur)
                .overlay(DS.scrim)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .onArt()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("En la TV: \(focus.title)"))
        .accessibilityIdentifier("remote-focus")
    }
}
