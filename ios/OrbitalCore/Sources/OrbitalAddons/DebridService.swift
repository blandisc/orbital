import Foundation

/// Tu nube (DN1, Fernando, 18 nov 2026: «que pueda funcionar con TorBox, AllDebrid y Real-Debrid. Solamente esos tres»): la
/// que sirve los videos al instante. Una sola activa a la vez; la clave de cada una se guarda aparte en el llavero, así
/// cambiarse y volver no pide la clave otra vez. Sin elegir nunca, Real-Debrid (lo de antes). El contrato, igual que la TV:
/// `design/debrid-services.json` (`DebridServiceContractTests` lo compara).
public enum DebridService: String, CaseIterable, Codable, Sendable, Identifiable {
    case realDebrid = "realdebrid", torBox = "torbox", allDebrid = "alldebrid"

    public var id: String { rawValue }
    /// Sin elegir nunca (o algo que no es una de las tres): Real-Debrid.
    public static let fallback = DebridService.realDebrid
    public static func read(_ raw: String?) -> DebridService { raw.flatMap { DebridService(rawValue: $0.lowercased()) } ?? fallback }

    public var name: String {
        switch self { case .realDebrid: "Real-Debrid"; case .torBox: "TorBox"; case .allDebrid: "AllDebrid" }
    }
    /// La marca de Torrentio: «[RD+]», «[TB+]», «[AD+]».
    public var tag: String {
        switch self { case .realDebrid: "RD"; case .torBox: "TB"; case .allDebrid: "AD" }
    }
    /// Su página, como se dice en los textos («real-debrid.com»).
    public var site: String {
        switch self { case .realDebrid: "real-debrid.com"; case .torBox: "torbox.app"; case .allDebrid: "alldebrid.com" }
    }
    /// Dónde se copia la clave.
    public var keyURL: URL {
        switch self {
        case .realDebrid: URL(string: "https://real-debrid.com/apitoken")!
        case .torBox: URL(string: "https://torbox.app/settings")!
        case .allDebrid: URL(string: "https://alldebrid.com/apikeys/")!
        }
    }
    /// Dónde se renueva o se ve el plan.
    public var renewURL: URL {
        switch self {
        case .realDebrid: URL(string: "https://real-debrid.com/premium")!
        case .torBox: URL(string: "https://torbox.app/pricing")!
        case .allDebrid: URL(string: "https://alldebrid.com/offer/")!
        }
    }
    /// «Todavía no tengo»: su página de planes (`words.signup_urls`).
    public var signupURL: URL { renewURL }
    /// «real-debrid.com/apitoken» sin «https://»: lo que se lee en «Conectar con tu clave · …».
    public var keyPlace: String {
        keyURL.absoluteString.replacingOccurrences(of: "https://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    /// El nombre de su clave en una dirección de Torrentio (`…|torbox=CLAVE/manifest.json`).
    public var torrentioParam: String { rawValue }
    /// El `service` de Comet.
    public var cometService: String { rawValue }
    /// Dónde se guarda su clave en el llavero (la de Real-Debrid, donde siempre).
    public var keyStore: String {
        switch self { case .realDebrid: AddonKeys.realDebridToken; case .torBox: "torbox_token"; case .allDebrid: "alldebrid_token" }
    }
    /// Lo último que se supo de su cuenta.
    var statusStore: String { self == .realDebrid ? AddonKeys.debridStatus : "\(AddonKeys.debridStatus).\(rawValue)" }
    /// Solo Real-Debrid avisa que «No se renueva solo»; con las otras, «Revisa tu plan».
    public var renewsByHand: Bool { self == .realDebrid }
    /// Si dice cuántas descargas a la vez deja tu plan (TorBox no: «Muchas descargas activas» se reintenta una vez).
    public var countsActive: Bool { self != .torBox }

    /// La forma de una clave (`choice.key_shape`): de 16 a 128 letras, números o guiones. La de Real-Debrid, como antes.
    public func looksLikeKey(_ key: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if self == .realDebrid { return RealDebrid.looksLikeToken(key) }
        return (16...128).contains(key.count) && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}

public extension AddonVault {
    /// La nube que usas (Ajustes › Cuentas › Tu nube).
    var debridService: DebridService { DebridService.read(data(AddonKeys.debridService).flatMap { String(data: $0, encoding: .utf8) }) }
    func setDebridService(_ service: DebridService) { setData(AddonKeys.debridService, Data(service.rawValue.utf8)) }
    /// La clave de esa nube (la de la que usas, sin decir cuál). nil si no hay.
    func debridToken(_ service: DebridService? = nil) -> String? {
        secret((service ?? debridService).keyStore).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Quién pidió algo en la libreta: la nube y su cuenta, en una sola tira para compararlas («abc123» es de Real-Debrid, como
/// antes; «torbox:42» de TorBox). Un pedido es tuyo solo si es de tu nube activa y de tu cuenta (`requests.mine`).
public enum DebridOwner {
    public static func make(_ service: DebridService, account: String?) -> String? {
        service == .realDebrid ? account : "\(service.rawValue):\(account ?? "")"
    }
    public static func split(_ owner: String?) -> (service: DebridService, account: String?) {
        guard let owner else { return (.realDebrid, nil) }
        for service in DebridService.allCases where service != .realDebrid && owner.hasPrefix(service.rawValue + ":") {
            let id = String(owner.dropFirst(service.rawValue.count + 1))
            return (service, id.isEmpty ? nil : id)
        }
        return (.realDebrid, owner.isEmpty ? nil : owner)
    }
}
