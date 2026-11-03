import Foundation
import OrbitalCore
import OrbitalAddons

/// CX2-A · tu clave entre tus aparatos Apple, en la página de Real-Debrid: «Usar la clave de tus aparatos Apple» (sin clave
/// aquí, junto a «Pega tu clave», nunca en su lugar) y «Tu iPad cambió la clave de Real-Debrid · Usar la nueva / Seguir con
/// la de este iPhone» (otra cuenta). Al abrir y al volver a la app se lee otra vez (TEC-6).
extension Services {
    public func refreshSharedDebrid() async {
        let found = await debrid.checkShared()
        sharedDebrid = found
        if case .adopted = found { await resetAccountCaches() }
        if case .removedEverywhere = found { await resetAccountCaches() }
    }
}

extension DebridModel {
    public var shared: SharedDebrid { services.sharedDebrid }

    /// «iPhone», «iPad» o «Mac»: el aparato que puso la copia compartida (nunca se promete «tu iPhone» si vino del iPad, UX-19).
    nonisolated public static func deviceWord(_ platform: String) -> String? {
        switch platform { case "iphone": "iPhone"; case "ipad": "iPad"; case "mac": "Mac"; default: nil }
    }

    public func checkShared() async {
        await services.refreshSharedDebrid()
        status = services.debrid.saved.flatMap { services.debrid.hasToken ? $0 : nil }
    }

    /// «Usar la nueva» / «Usar la clave de tus aparatos Apple»: Real-Debrid la comprueba y se guarda en este aparato.
    public func useShared() async {
        check = .checking
        do {
            let found = try await services.debrid.useShared()
            guard found.isPremium else { check = .free(found); return }
            services.addonList.startWithRecommended()
            await services.resetAccountCaches()
            status = found; keyCheck = .confirmed; check = .ok(found)
            services.sharedDebrid = .none
        } catch let error as DebridError { check = .failed(error.description) }
        catch { check = .failed(DebridError.unexpected.description) }
    }

    /// «Seguir con la de este iPhone»: no se vuelve a preguntar por esa copia.
    public func keepLocal() {
        services.debrid.keepLocal()
        services.sharedDebrid = .none
    }
}
