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
    /// Tu copia de OneDrive (no de un complemento).
    public var own: Bool { addon == OneDriveLibrary.addonName }
    /// Para las insignias (como Infuse): la resolución y el sonido (Atmos, TrueHD, 7.1…).
    public var resolution = ""
    public var audio: [String] = []
    /// El nombre del archivo (para quien lo quiera ver: mantener presionada la fuente).
    public var release = ""
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

/// La lista de fuentes de un episodio o película, «Ver» o «Descargar» (se ordenan distinto).
@MainActor
public final class SourcesModel: ObservableModel {
    public private(set) var rows: [SourceRow] = [] { didSet { changed() } }
    public private(set) var purpose: Purpose = .watch { didSet { changed() } }
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

    public func load(_ purpose: Purpose, onCellular: Bool = false) async {
        // Al cambiar Ver ↔ Descargar, la lista vieja se quita: no se puede tocar una fuente de «Ver» para descargarla.
        if purpose != self.purpose { sources = []; rows = []; error = nil }
        self.purpose = purpose
        isLoading = true
        // Solo la última carga apaga el indicador: la vieja que se cancela al cambiar de pestaña no lo quita a media espera.
        loadCount += 1
        let ticket = loadCount
        defer { if ticket == loadCount { isLoading = false } }
        let settings = services.appSettings
        let prefs = services.titlePrefs.languages(for: metaID, settings: settings, onCellular: onCellular).prefs
        let found: [Source]
        do { found = try await services.finder.find(kind: kind, videoID: videoID, prefs: prefs, purpose: purpose) }
        catch where !Task.isCancelled { sources = []; rows = []; self.error = "\(error)"; return }
        catch { return }
        // Cancelada (cambiaste de pestaña antes de que llegara): no pisa la lista nueva.
        guard !Task.isCancelled, purpose == self.purpose else { return }
        sources = found
        error = sources.isEmpty ? "No hay fuentes de Real-Debrid para este título." : nil
        let limit = Int64(settings.warnCellularOverGB * 1e9)
        rows = sources.enumerated().map { i, s in
            let langs = s.languages.prefix(2).map { Streams.languageName($0, in: services.appSettings.uiLanguage) }.joined(separator: " + ")
            let headline = [s.resolution.isEmpty ? "SD" : s.resolution, langs, s.tags.first(where: { ["REMUX", "WEB-DL", "BluRay"].contains($0) }), s.tags.contains("x265") ? "x265" : nil]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return SourceRow(id: s.index, headline: headline, recommended: i == 0, cached: s.cached, sizeGB: s.size > 0 ? Double(s.size) / 1e9 : nil,
                             heavy: Int64(s.size) > limit, hdr: s.hdr, tags: s.tags.filter { $0 != "x265" && !["REMUX", "WEB-DL", "BluRay", "Atmos", "5.1", OneDriveLibrary.addonName].contains($0) }, addon: s.addon,
                             resolution: s.resolution, audio: s.audioBadges, release: s.release)
        }
    }

    /// La fuente elegida, para reproducir o descargar.
    public func source(_ id: Int) -> Source? { sources.first { $0.index == id } }
}
