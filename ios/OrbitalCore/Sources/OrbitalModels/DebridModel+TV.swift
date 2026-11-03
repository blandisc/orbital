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
        do { tvShare = .passed(try await services.orbital.putRealDebrid(token: key)); await compareWithTV() }
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
            await compareWithTV()
        } catch let failure as OrbitalRemote.Failure { tvShare = .failed(failure.description) }
        catch let error as DebridError { tvShare = .failed(error.description) }
        catch { tvShare = .failed(DebridError.unexpected.description) }
    }

    /// Al abrir la página: lo de la vez pasada no se queda (lo que dice la pantalla es verdad al abrirla).
    public func resetTVShare() { tvShare = .idle }

    /// IOS-6 · le pregunta a tu TV qué cuenta usa y la compara con la de este iPhone (por la cuenta, no por la clave). Así
    /// «Pasar la de este iPhone · Usar la de la TV · Dejar cada una» solo se ofrece cuando son distintas.
    public func compareWithTV() async {
        guard canShareWithTV else { tvAccount = .unknown; return }
        tvAccount = .checking
        do {
            guard let tv = try await services.orbital.realDebridAccount() else { tvAccount = .tvHasNone; return }
            tvAccount = Self.compare(tv: tv, mine: hasToken ? status : nil, kept: keptApart(tv.user))
        } catch is CancellationError { tvAccount = .unknown }
        catch { tvAccount = .unreachable }
    }

    nonisolated static func compare(tv: OrbitalTVDebrid, mine: DebridStatus?, kept: Bool) -> TVAccount {
        guard !tv.user.isEmpty else { return .tvKeyBroken }
        guard let mine else { return .onlyTV(user: tv.user) }
        if mine.username.caseInsensitiveCompare(tv.user) == .orderedSame { return .same(user: tv.user) }
        return .different(tv: tv.user, mine: mine.username, keptApart: kept)
    }

    /// «Dejar cada una»: no se vuelve a preguntar por esta pareja de cuentas.
    public func keepAccountsApart() {
        guard case .different(let tv, let mine, _) = tvAccount else { return }
        services.kv.set(Self.apartKey, data: Data("\(tv.lowercased())|\(mine.lowercased())".utf8))
        tvAccount = .different(tv: tv, mine: mine, keptApart: true)
    }

    private func keptApart(_ tvUser: String) -> Bool {
        guard let mine = status?.username, let saved = services.kv.data(Self.apartKey).flatMap({ String(data: $0, encoding: .utf8) }) else { return false }
        return saved == "\(tvUser.lowercased())|\(mine.lowercased())"
    }
    static let apartKey = "debrid.tv-apart"
}

/// IOS-6 · la cuenta de Real-Debrid de tu TV frente a la de este iPhone.
public enum TVAccount: Equatable, Sendable {
    case unknown, checking
    /// Tu TV no contestó.
    case unreachable
    /// Tu TV no tiene Real-Debrid: solo «Pasar a la TV».
    case tvHasNone
    /// Tu TV tiene una clave que Real-Debrid ya no reconoce.
    case tvKeyBroken
    /// Este iPhone no tiene clave y la TV sí: «Usar la de la TV».
    case onlyTV(user: String)
    /// La misma cuenta: «Tu TV usa la cuenta X · la misma que este iPhone ✓», sin botones.
    case same(user: String)
    /// Distintas: la pregunta con tres salidas (o, si ya dijiste «Dejar cada una», solo la línea).
    case different(tv: String, mine: String, keptApart: Bool)
}
