import Foundation
import OrbitalAddons

/// Lo que contestó un complemento, contado para la bitácora (Fernando, 13 nov, Los Simpson desde la ruleta: «Torrentio RD:
/// 0 versiones en 0,2 s» y no se sabía si venía vacío, con puros torrents o con avisos). Sin direcciones ni claves: solo
/// cuántas entradas, cuántas sin enlace, los avisos por tipo y, de Torrentio, sus opciones y si la dirección lleva tu clave.
public struct AddonAnswerReport: Equatable, Sendable {
    /// Todas las entradas que mandó (objetos JSON en `streams`).
    public var total = 0
    /// Las que traen enlace (`url`): las que el iPhone puede abrir.
    public var withLink = 0
    /// Las que solo traen el torrent (`infoHash`, sin `url`): lo que da un Torrentio sin Real-Debrid.
    public var onlyTorrent = 0
    /// Los avisos de Torrentio («RD error», «descargando»…) por tipo.
    public var notices: [StreamNotice: Int] = [:]
    /// La dirección del complemento lleva la clave de un servicio de descarga (`realdebrid=`…, o la de Comet en base64).
    public var keyInAddress = false
    /// Dice ser de Real-Debrid aunque la dirección no lo lleve (su nombre: «Torrentio RD», «Comet | ElfHosted | RD»).
    public var saysDebrid = false
    /// De Torrentio: sus opciones sin claves («sort=seeders|language=latino,spanish»); nil si no es Torrentio.
    public var torrentioOptions: String?

    public init(streams: [JSON], addonName: String, addonURL: String) {
        for stream in streams where stream.object != nil {
            total += 1
            let link = stream["url"]?.nonEmptyString
            if let notice = TorrentioNotices.notice(name: stream["name"]?.string ?? "", url: link.flatMap(URL.init(string:))) {
                notices[notice, default: 0] += 1
            }
            if link != nil { withLink += 1 } else if stream["infoHash"]?.nonEmptyString != nil { onlyTorrent += 1 }
        }
        keyInAddress = Self.carriesKey(addonURL)
        saysDebrid = Self.namesDebrid(addonName)
        torrentioOptions = TorrentioConfig.publicOptions(addonURL)
    }

    /// Un complemento que debería venir con Real-Debrid (lo dice su dirección o su nombre) mandó entradas, ninguna con enlace
    /// y sí torrents: así contesta Torrentio cuando la dirección va SIN tu clave. No es «0 versiones»: es un fallo.
    public var torrentsInsteadOfLinks: Bool { (keyInAddress || saysDebrid) && total > 0 && withLink == 0 && onlyTorrent > 0 }

    /// «59 entradas · 0 con enlace · 59 solo torrent · avisos: ninguno · opciones: sort=seeders|… · clave: no».
    public var line: String {
        let said = notices.isEmpty ? "ninguno" : notices.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.value) \($0.key.rawValue)" }.joined(separator: ", ")
        var parts = ["\(total) entradas", "\(withLink) con enlace", "\(onlyTorrent) solo torrent", "avisos: \(said)"]
        if let torrentioOptions { parts.append("opciones: \(torrentioOptions.isEmpty ? "las de fábrica" : torrentioOptions)") }
        parts.append("clave en la dirección: \(keyInAddress ? "sí" : "no")")
        return parts.joined(separator: " · ")
    }

    /// La dirección lleva la clave de un servicio de descarga (sin decir cuál es).
    static func carriesKey(_ url: String) -> Bool {
        if TorrentioConfig.parse(url)?.key != nil { return true }
        // Otros (Comet): la clave va dentro de un tramo en base64; tapar la dirección la cambia si la lleva.
        return AddonRedaction.redact(url, secrets: []) != url
    }

    /// «Torrentio RD», «Comet | ElfHosted | RD», «… Real-Debrid»: el nombre dice que trae Real-Debrid.
    static func namesDebrid(_ name: String) -> Bool {
        let words = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }).map(String.init)
        return words.contains("rd") || words.contains("real-debrid") || name.lowercased().contains("realdebrid")
    }
}
