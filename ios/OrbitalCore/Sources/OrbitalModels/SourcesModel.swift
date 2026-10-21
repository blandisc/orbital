import Foundation
import OrbitalCore

/// Una fuente para mostrar en la lista (sin URL: lleva tu clave de Real-Debrid).
public struct SourceRow: Equatable, Identifiable, Sendable {
    public var id: Int
    public var headline: String          // «1080p · Español · x265»
    public var recommended: Bool
    public var cached: Bool              // «Al instante»
    public var sizeGB: Double?           // nil si no se sabe
    public var heavy: Bool               // más de lo que conviene con datos móviles
    public var hdr: [String]
    public var tags: [String]
    public var addon: String
    /// Para las insignias (como Infuse): la resolución y el sonido (Atmos, TrueHD, 7.1…).
    public var resolution = ""
    public var audio: [String] = []
    /// El nombre del archivo (para quien lo quiera ver: mantener presionada la fuente).
    public var release = ""
    /// Se puede bajar (un archivo, no una lista HLS/DASH).
    public var downloadable = true
    /// La que más conviene guardar en el teléfono (1080p, ligera), cuando no es la recomendada para ver.
    public var bestToSave = false
    /// El grupo en la hoja: «4K», «1080p», «720p» u «Otras».
    public var group: String {
        switch resolution.lowercased() {
        case "4k", "2160p": return "4K"
        case "1080p", "1440p": return "1080p"
        case "720p": return "720p"
        default: return "Otras"
        }
    }
}

/// La lista de fuentes de un episodio o película: una sola, ordenada para ver (la recomendada primero), y en cada una se
/// puede ver o descargar. La que más conviene guardar (ligera) se marca aparte.
@MainActor
public final class SourcesModel: ObservableModel {
    public private(set) var rows: [SourceRow] = [] { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    private var sources: [Source] = []
    private let services: Services
    private var loadCount = 0
    private let kind: String, videoID: String, metaID: String

    public init(_ services: Services, kind: String, metaID: String, videoID: String) {
        self.services = services; self.kind = kind; self.metaID = metaID; self.videoID = videoID
        super.init()
    }

    public func load(onCellular: Bool = false) async {
        isLoading = true
        // Solo la última carga apaga el indicador (una vieja que se cancela no lo quita a media espera).
        loadCount += 1
        let ticket = loadCount
        defer { if ticket == loadCount { isLoading = false } }
        let settings = services.appSettings
        let prefs = services.titlePrefs.languages(for: metaID, settings: settings, onCellular: onCellular).prefs
        let found: [Source]
        do { found = try await services.finder.find(kind: kind, videoID: videoID, prefs: prefs, purpose: .watch) }
        catch where !Task.isCancelled {
            sources = []; rows = []
            self.error = (error as? StreamFinderError)?.description ?? "No pude buscar fuentes. Intenta de nuevo."
            return
        }
        catch { return }
        guard !Task.isCancelled, ticket == loadCount else { return }
        sources = found
        error = sources.isEmpty ? "Real-Debrid aún no tiene este título. Los estrenos suelen aparecer unas horas después." : nil
        let limit = Int64(settings.warnCellularOverGB * 1e9)
        let canSave = { (s: Source) in s.playbackURL.map { !["m3u8", "mpd"].contains($0.pathExtension.lowercased()) } ?? false }
        // Para guardar: el mismo puntaje que usa «Descargar» (1080p, HEVC, tamaño moderado), solo si no es la de ver.
        let toSave = sources.filter(canSave).max { Streams.score($0, prefs: prefs, kind: kind, purpose: .download) < Streams.score($1, prefs: prefs, kind: kind, purpose: .download) }
        rows = sources.enumerated().map { i, s in
            let langs = s.languages.prefix(2).map { Streams.languageName($0, in: services.appSettings.uiLanguage) }.joined(separator: " + ")
            let headline = [s.resolution.isEmpty ? "SD" : s.resolution, langs, s.tags.first(where: { ["REMUX", "WEB-DL", "BluRay"].contains($0) }), s.tags.contains("x265") ? "x265" : nil]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return SourceRow(id: s.index, headline: headline, recommended: i == 0, cached: s.cached, sizeGB: s.size > 0 ? Double(s.size) / 1e9 : nil,
                             heavy: Int64(s.size) > limit, hdr: s.hdr, tags: s.tags.filter { $0 != "x265" && !["REMUX", "WEB-DL", "BluRay", "Atmos", "5.1"].contains($0) }, addon: s.addon,
                             resolution: s.resolution, audio: s.audioBadges, release: s.release,
                             downloadable: canSave(s), bestToSave: i != 0 && s.index == toSave?.index)
        }
    }

    /// La fuente elegida, para reproducir o descargar.
    public func source(_ id: Int) -> Source? { sources.first { $0.index == id } }
}
