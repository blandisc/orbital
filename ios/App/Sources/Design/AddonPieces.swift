import SwiftUI
import OrbitalCore
import OrbitalAddons
import OrbitalModels

// Piezas de Complementos y de Torrentio (Fase 3, 3 nov 2026): el renglón de un complemento con cómo le va (C1), las
// palabras de cada opción de Torrentio para quien no sabe de esto (T1–T7) y la prueba con un título (T9).

/// Cómo le va a un complemento en este aparato, en palabras e ícono (nunca solo color): «Contesta en 0,6 s», «Contesta
/// lento · 4,2 s», «No contesta desde el sábado · se salta». Las mismas palabras que la TV (design/vocabulario.json).
struct AddonHealthLine: View {
    let state: AddonHealth.State
    var enabled = true
    /// La app en inglés: «0.6» en vez de «0,6» y los días en inglés.
    var english = false

    var body: some View {
        if !enabled {
            line("circle", DS.textMuted, Text("Apagado"))
        } else if let words {
            line(symbol, color, words)
        }
    }

    /// El ícono en su color (la forma también cambia: no solo el color) y la palabra en gris legible.
    private func line(_ symbol: String, _ color: Color, _ text: Text) -> some View {
        HStack(spacing: DS.Space.s1) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            text.foregroundStyle(DS.textMuted)
        }
        .font(DS.TextRecipe.footnote.font)
        .accessibilityElement(children: .combine)
    }

    private var words: Text? {
        switch state {
        case .unknown: nil
        case .ok(let s): Text("Contesta en \(AddonHealthWords.seconds(s, english: english)) s")
        case .slow(let s): Text("Contesta lento · \(AddonHealthWords.seconds(s, english: english)) s")
        case .down(let since, let skipped):
            skipped ? Text("No contesta desde \(AddonHealthWords.since(since, now: Date(), english: english)) · se salta")
                    : Text("No contesta desde \(AddonHealthWords.since(since, now: Date(), english: english))")
        }
    }

    private var symbol: String {
        switch state { case .ok: "checkmark.circle"; case .slow: "tortoise"; case .down: "slash.circle"; case .unknown: "circle" }
    }

    private var color: Color {
        switch state { case .ok: DS.success; case .slow, .down: DS.warning; case .unknown: DS.textMuted }
    }
}

/// C8 · en la lista de versiones: quién no contestó a tiempo (o se saltó por no contestar antes), por su nombre, para que
/// «no hay latino» no parezca culpa del título. Con la tortuga de «Contesta lento».
struct AddonQuietLine: View {
    let names: [String]

    var body: some View {
        let joined = names.joined(separator: " · ")
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
            Image(systemName: "tortoise").foregroundStyle(DS.warning).accessibilityHidden(true)
            (names.count == 1 ? Text("No contestó a tiempo: \(joined)") : Text("No contestaron a tiempo: \(joined)"))
                .foregroundStyle(DS.textMuted).fixedSize(horizontal: false, vertical: true)
        }
        .font(DS.TextRecipe.caption.font)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sources-quiet")
    }
}

/// M6: un complemento que solo da torrents, en una línea con su ícono: aquí no se reproduce; en la TV (Ultra) sí.
struct AddonTorrentsLine: View {
    /// Hay una TV emparejada (Ultra): se dice que allá sí.
    var tv = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
            Image(systemName: "iphone.slash").foregroundStyle(DS.warning).accessibilityHidden(true)
            (tv ? Text("En el iPhone no se puede reproducir; en la TV sí") : Text("En el iPhone no se puede reproducir")).foregroundStyle(DS.textMuted)
        }
        .font(DS.TextRecipe.footnote.font)
        .accessibilityElement(children: .combine)
    }
}

/// Un complemento en la lista (C1): su nombre, qué aporta y, debajo, cómo le va o «Apagado».
struct AddonRowLabel: View {
    let addon: InstalledAddon
    let health: AddonHealth.State
    var english = false
    /// M6: solo da torrents (`AddonTorrentsLine`); `tv`: hay una TV emparejada.
    var torrents = false
    var tv = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: addon.name).font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
            AddonWhat(addon: addon).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            if torrents { AddonTorrentsLine(tv: tv) }
            else { AddonHealthLine(state: health, enabled: addon.enabled, english: english) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Qué aporta un complemento, en una línea: «Fuentes de video · usa tu Real-Debrid», «Subtítulos», «Listas · agregado por ti».
struct AddonWhat: View {
    let addon: InstalledAddon

    var body: some View { text }

    var text: Text {
        let kinds = addon.resources.contains("stream") ? Text("Fuentes de video")
            : addon.resources.contains("subtitles") ? Text("Subtítulos") : Text("Listas")
        if addon.isBuiltIn { return addon.usesDebrid ? Text("\(kinds) · usa tu Real-Debrid") : kinds }
        return addon.usesDebrid ? Text("\(kinds) · agregado por ti · usa tu Real-Debrid") : Text("\(kinds) · agregado por ti")
    }
}

/// Las palabras de cada opción de Torrentio (T2–T8), para quien no sabe de esto: qué es, en una línea.
enum TorrentioWords {
    /// Las calidades que se pueden esconder en la pantalla, en este orden (las otras de Torrentio se conservan si venían).
    static let qualities = ["4k", "1080p", "720p", "480p", "hdrall", "threed", "brremux", "scr", "cam", "other", "unknown"]

    static func quality(_ key: String) -> (name: Text, detail: Text) {
        switch key {
        case "4k": (Text(verbatim: "4K"), Text("La mejor imagen; pesa mucho"))
        case "1080p": (Text(verbatim: "1080p"), Text("Alta definición; la más común"))
        case "720p": (Text(verbatim: "720p"), Text("Buena en el teléfono"))
        case "480p": (Text(verbatim: "480p"), Text("Se ve borrosa en la TV"))
        case "hdrall": (Text("HDR y Dolby Vision"), Text("Colores intensos; solo si tu TV lo aguanta"))
        case "threed": (Text(verbatim: "3D"), Text("Para lentes 3D"))
        case "brremux": (Text("Remux de Blu-ray"), Text("Copia exacta del disco; enorme"))
        case "scr": (Text(verbatim: "Screener"), Text("Copia de prensa, a veces con marcas"))
        case "cam": (Text("Grabada en el cine (CAM)"),   // ds-exception: siglas de calidad de video
                   Text("Con una cámara en la sala: se ve y oye mal"))
        case "other": (Text("Otras copias (DVD)"),   // ds-exception: siglas de calidad de video
                   Text("Copias viejas o de menos calidad"))
        case "unknown": (Text("Sin calidad conocida"), Text("No dice qué es"))
        default: (Text(verbatim: key), Text(verbatim: ""))
        }
    }

    /// Corto, para el renglón: «Sin cine, Screener y Remux».
    static func hidden(_ keys: [String]) -> Text {
        func short(_ key: String) -> Text {
            switch key {
            case "cam": Text("cine"); case "scr": Text(verbatim: "Screener"); case "brremux": Text(verbatim: "Remux"); case "unknown": Text("sin calidad")
            case "4k": Text(verbatim: "4K"); case "hdrall": Text(verbatim: "HDR"); case "threed": Text(verbatim: "3D"); case "other": Text("otras copias")
            default: Text(verbatim: key)
            }
        }
        guard let last = keys.last else { return Text("Ninguna: ves todas") }
        guard keys.count > 1 else { return Text("Sin \(short(last))") }
        let rest = keys.dropLast().dropFirst().reduce(short(keys[0])) { Text("\($0), \(short($1))") }
        return Text("Sin \(rest) y \(short(last))")
    }

    static func sort(_ key: String) -> (name: Text, detail: Text) {
        switch key {
        case "qualitysize": (Text("Calidad y luego tamaño"), Text("Entre iguales, la más ligera"))
        case "seeders": (Text("Las más compartidas primero"), Text("Suelen bajar más rápido"))
        case "size": (Text("Las más pesadas primero"), Text("La mayor calidad de archivo"))
        default: (Text("Mejor calidad primero"), Text("Lo recomendado"))
        }
    }

    static func limit(_ value: Int?) -> (name: Text, detail: Text) {
        switch value {
        case nil: (Text("Todas"), Text("Lista larga, más para elegir"))
        case 5?: (Text("Hasta 5"), Text("Lista corta"))
        case 2?: (Text("Hasta 2"), Text("La más corta"))
        case let n?: (Text("Hasta \(n)"), Text("La que tenías"))
        }
    }

    /// Un idioma de Torrentio en palabras: «Latino», «Español de España», «Japonés».
    static func language(_ key: String, uiLanguage: String) -> Text {
        switch key {
        case "latino": return Text("Latino")
        case "spanish": return Text("Español de España")
        default:
            let code = TorrentioConfig.languageCodes.first { $0.key == key }?.code ?? key
            return Text(verbatim: Streams.languageName(String(code.prefix(2)), in: uiLanguage).capitalized(with: Locale(identifier: uiLanguage)))
        }
    }

    /// «Sin límite» o el tamaño tal cual («5 GB»).
    static func size(_ value: String?) -> Text {
        guard let value else { return Text("Sin límite") }
        return Text(verbatim: value.replacingOccurrences(of: "GB", with: " GB").replacingOccurrences(of: "MB", with: " MB"))
    }

    /// Un resumen de unas opciones (para elegir entre dos Torrentio, C5): «Más compartidas · latino · sin cine, Screener…».
    static func summary(_ options: AddonOptions, uiLanguage: String) -> Text {
        let order = options.sort.map { sort($0).name } ?? sort("quality").name
        let languages = options.languages.first.map { language($0, uiLanguage: uiLanguage) } ?? Text("sin idioma primero")
        return Text("\(order) · \(languages) · \(hidden(options.excludedQualities))")
    }
}

/// T9 · la prueba con un título, en la misma página: cuántas daría o, si no queda nada, el arreglo de un toque.
struct TorrentioProbeRow: View {
    let probe: TorrentioSettingsModel.Probe
    let sample: String
    let apply: (TorrentioProbe.Fix) -> Void

    var body: some View {
        switch probe {
        case .idle: EmptyView()
        case .checking:
            DSInlineProgress(text: Text("Probando con \(sample)…"))
        case .unreachable:
            line("wifi.exclamationmark", DS.textMuted, Text("No pude probar: Torrentio no contestó."))
        case .result(.found(let instant, let toRequest, let other)):
            if instant + toRequest == 0 {
                line("checkmark.circle", DS.success, other == 1 ? Text("Con esto, \(sample) tiene 1 versión.")
                                                                : Text("Con esto, \(sample) tiene \(String(other)) versiones."))
            } else {
                line("checkmark.circle", DS.success, Text("Con esto, \(sample) tiene \(String(instant)) al instante y \(String(toRequest)) para pedir."))
            }
        case .result(.titleHasNothing):
            line("info.circle", DS.textMuted, Text("Hoy \(sample) no tiene versiones ni con lo recomendado: no son tus filtros."))
        case .result(.nothing):
            EmptyView()   // P3-B: «Con esto no verías nada» sube arriba de la página (`TorrentioNothingProblem`)
        }
    }

    private func line(_ symbol: String, _ color: Color, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            text.recipe(.footnote, color: DS.text).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    static func fixTitle(_ fix: TorrentioProbe.Fix) -> Text {
        switch fix {
        case .showQuality(let q): Text("Volver a mostrar \(q == "4k" ? "4K" : q)")
        case .allowRequests: Text("Ver también lo que se puede pedir")
        case .recommended: Text("Volver a lo recomendado")
        }
    }
}

/// P3-B · «Con esto no verías nada» arriba de la página de Torrentio, solo cuando la prueba da 0 versiones, con sus arreglos
/// de un toque (`DSProblem`). Si todo va bien, la página no cambia.
struct TorrentioNothingProblem: View {
    let sample: String
    let fixes: [TorrentioProbe.Fix]
    let apply: (TorrentioProbe.Fix) -> Void

    var body: some View {
        DSProblem(title: Text("Con esto no verías nada"), detail: Text("\(sample) daría 0 versiones con estos filtros.")) {
            ForEach(Array(fixes.enumerated()), id: \.element) { index, fix in
                Button { apply(fix) } label: { TorrentioProbeRow.fixTitle(fix).frame(maxWidth: .infinity) }
                    .dsProblemFix(primary: index == 0)
            }
        }
        .accessibilityIdentifier("torrentio-nothing")
    }
}

/// Lo que dice la hoja de «¿Quitar…?» (Fernando, 3 nov 2026): dónde se quita, que tu Stremio no cambia y que no regresa solo.
struct AddonRemoveMessage: View {
    let last: Bool
    let tv: Bool

    var body: some View {
        switch (last, tv) {
        case (false, false): Text("Se quita de este iPhone.")
        case (false, true): Text("Se quita de este iPhone y de tu TV.")
        case (true, false): Text("Es tu última fuente de video: sin ella no habrá versiones. Se quita de este iPhone.")
        case (true, true): Text("Es tu última fuente de video: sin ella no habrá versiones. Se quita de este iPhone y de tu TV.")
        }
    }
}
