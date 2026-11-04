import Foundation
import OrbitalAddons

/// El torrent de una versión: su huella y su archivo. La misma clave en la lista con Real-Debrid (que solo trae la dirección
/// `/resolve/realdebrid/<clave>/<huella>/…/<archivo>/`) y en la de Torrentio sin Real-Debrid (`infoHash`, `fileIdx`):
/// así se juntan las dos (R4) y la libreta de pedidos reconoce una versión ya pedida (B-P2-2).
public struct TorrentID: Equatable, Hashable, Sendable {
    public var hash: String
    public var fileIdx: Int?
    public init(hash: String, fileIdx: Int?) { self.hash = hash.lowercased(); self.fileIdx = fileIdx }

    /// Una huella de torrent: 40 letras hexadecimales (o 32 en base32).
    static func looksLikeHash(_ text: String) -> Bool {
        (text.count == 40 && text.allSatisfy(\.isHexDigit)) || (text.count == 32 && text.allSatisfy { $0.isLetter || ("2"..."7").contains($0) })
    }
}

public extension Source {
    /// El torrent de esta versión, si se sabe (su `infoHash`, o la dirección de Torrentio con Real-Debrid).
    var torrent: TorrentID? {
        if let hash = stream["infoHash"]?.nonEmptyString { return TorrentID(hash: hash, fileIdx: stream["fileIdx"]?.intValue) }
        guard let path = playbackURL?.path else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard let at = parts.firstIndex(of: "resolve"), parts.count > at + 3, TorrentID.looksLikeHash(parts[at + 3]) else { return nil }
        let after = parts.dropFirst(at + 4).prefix(2).map { Int($0) }
        return TorrentID(hash: parts[at + 3], fileIdx: after.count == 2 ? (after[1] ?? after[0]) : after.first ?? nil)
    }
}

/// Lo que existe en internet de un video, aunque Real-Debrid no lo tenga (R4): tu Torrentio sin Real-Debrid. Separa
/// «Real-Debrid todavía no lo tiene» (causa 10: hay torrents, se puede pedir) de «Nadie lo tiene todavía en internet» (11).
public struct TorrentLookup: Sendable {
    let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }

    /// Los torrents de ese video, del mejor al peor según tu idioma y calidad (sin CAM ni tráileres). nil si no contestó (sin
    /// red no se puede decir «nadie lo tiene»). `base`: `AddonCatalog.torrentioWithoutDebrid` de tu Torrentio.
    public func torrents(base: String, kind: String, videoID: String, prefs: Preferences, origin: TitleOrigin? = nil) async -> [Source]? {
        guard let url = URL(string: "\(base)/stream/\(kind)/\(uriComponent(videoID)).json") else { return nil }
        let streams: [JSON]
        do { streams = try await http.getJSON(url, timeout: 15)?["streams"]?.array ?? [] }
        catch let error as NetworkError where error.description.hasPrefix("HTTP 4") { return [] }
        catch { return nil }
        let found = streams.enumerated().compactMap { i, stream -> Source? in
            guard stream["infoHash"]?.nonEmptyString != nil else { return nil }
            var source = Streams.parse(stream, addon: "Torrentio", transportURL: base, index: Streams.stableIndex(addonURL: base, stream: stream) ^ i, origin: origin)
            // Igual que la lista de versiones (`StreamFinder`): el nombre que no dice el título baja.
            source.otherTitle = !Streams.mentionsTitle(origin?.titles ?? [], "\(source.release) \(stream["behaviorHints"]?["filename"]?.string ?? "")")
            return source
        }
        return Streams.rank(found, prefs: prefs, kind: kind).filter { $0.notice == nil && !$0.tags.contains("CAM") && !$0.tags.contains("Tráiler") }
    }
}
