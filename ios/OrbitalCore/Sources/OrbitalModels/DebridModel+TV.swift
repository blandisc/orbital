import Foundation
import OrbitalCore
import OrbitalAddons

/// K1 · tu clave de Real-Debrid entre el iPhone y tu TV (Ajustes › Cuentas › Real-Debrid), con la llave de este aparato y
/// solo si tu TV reparte llaves (`pairing: 2`). En Plus o sin TV no aparece. La clave nunca se enseña ni se guarda fuera del
/// llavero: a la TV va en el cuerpo del PUT (https o Tailscale) y de la TV llega en la respuesta de `?full=1`.
extension DebridModel {
    /// ¿Se enseñan «Pasar a la TV» y «Usar la de la TV»?
    public var canShareWithTV: Bool { services.canShareKeysWithTV }

    /// «Pasar a la TV» (después de «Tu TV usará esta clave»): la TV la comprueba con Real-Debrid y se queda con ella; si no la
    /// reconoce (422), conserva la que tenía.
    public func passToTV() async {
        guard canShareWithTV, let key = services.addonList.debridToken else { return }
        tvShare = .working
        do { tvShare = .passed(try await services.orbital.putRealDebrid(token: key)) }
        catch let failure as OrbitalRemote.Failure { tvShare = .failed(failure.description) }
        catch { tvShare = .failed(OrbitalRemote.Failure.unreachable.description) }
    }

    /// «Usar la de la TV»: se trae la de tu TV y se comprueba como una pegada; solo se guarda si Real-Debrid la acepta con Premium.
    public func useTVKey() async {
        guard canShareWithTV else { return }
        tvShare = .working
        do {
            guard let key = try await services.orbital.realDebridKey(), !key.isEmpty else {
                tvShare = .failed("Tu TV todavía no tiene clave de Real-Debrid."); return
            }
            let found = try await services.debrid.verify(key)
            guard found.isPremium else { tvShare = .failed("Esa cuenta de Real-Debrid no tiene Premium: no la guardé."); return }
            await keep(key, found)
            tvShare = .used
        } catch let failure as OrbitalRemote.Failure { tvShare = .failed(failure.description) }
        catch let error as DebridError { tvShare = .failed(error.description) }
        catch { tvShare = .failed(DebridError.unexpected.description) }
    }

    /// Al abrir la página: lo de la vez pasada no se queda (lo que dice la pantalla es verdad al abrirla).
    public func resetTVShare() { tvShare = .idle }
}
