import Foundation
import OrbitalCore
import OrbitalAddons

/// V4 (9 nov 2026): «Versión» sin ninguna versión dice por qué con la misma tabla que «Ver» de la ficha (`UnavailableCause`),
/// nunca una hoja en blanco. Va en el orden de la tabla: tu cuenta, tus complementos, la búsqueda que falló y, al final, lo que
/// se supo (lo puede bajar la nube, o nadie lo tiene).
extension SourcesModel {
    /// La causa de una hoja vacía. `thrown`: lo que tronó al buscar (nil si contestaron sin nada); `online`: hay internet;
    /// `hasToken`: tienes clave de Real-Debrid; `addonsOff`: tu lista no tiene ningún complemento de video prendido;
    /// `notices`: lo que dijo Torrentio en lugar de versiones; `canRequest`: hay versiones para pedir a la nube (abajo, en
    /// «Hay que pedirlas»); `language`: el idioma que quieres.
    public static func emptyCause(thrown: Error?, online: Bool, account: UnavailableCause.Account, hasToken: Bool, addonsOff: Bool,
                                  notices: [StreamNotice], canRequest: Bool, language: String) -> UnavailableCause {
        if let byAccount = UnavailableCause.first(notice: nil, account: account, language: language) { return byAccount }
        if !hasToken { return .reconnectDebrid }
        if addonsOff { return .noAddonsOn }
        if let thrown {
            switch thrown as? StreamFinderError {
            // Alguno no contestó y los demás no tenían nada: «no sé si hay versiones», nunca «no hay» (Fernando, 9 nov).
            case let unsure? where unsure != .unreachable: return .cannotSearch(reason: unsure.description)
            // Ninguno contestó: con internet son ellos; sin internet, tu conexión.
            case _?: return online ? .addonsOffline : .cannotSearch(reason: StreamFinderError.unreachable.description)
            case nil: return .cannotSearch(reason: "No pude buscar versiones. Intenta de nuevo.")
            }
        }
        if let said = UnavailableCause.first(notice: notices.first(where: \.aboutTheAccount) ?? notices.first, account: account, language: language) { return said }
        return canRequest ? .notInDebrid(language: language) : .nobodyHasIt
    }

    /// La causa con lo que sabe la app ahora (la cuenta guardada, sin preguntarle otra vez a Real-Debrid).
    func emptyCause(thrown: Error?, canRequest: Bool) async -> UnavailableCause {
        let list = services.addonList
        return Self.emptyCause(thrown: thrown, online: services.isOnline(),
                               account: .from(nil, saved: services.debrid.saved, now: services.now()), hasToken: services.debrid.hasToken,
                               addonsOff: list.isConfigured && !list.installed.contains { $0.enabled && $0.resources.contains("stream") },
                               notices: await services.finder.notices(kind: kind, videoID: videoID), canRequest: canRequest, language: prefs.audio)
    }
}
