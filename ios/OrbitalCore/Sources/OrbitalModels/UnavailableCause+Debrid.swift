import Foundation
import OrbitalCore
import OrbitalAddons

extension UnavailableCause.Account {
    /// Tu cuenta para decir la causa: lo que contestó Real-Debrid ahora (`health`) o, si no se le preguntó, lo guardado.
    public static func from(_ health: DebridHealth?, saved: DebridStatus?, now: Date) -> Self {
        switch health {
        case .status(let status)?: return from(status, now: now)
        case .invalidToken?: return .invalidKey
        case .unreachable(let last)?: return last.map { from($0, now: now) } ?? .unknown
        case .noKey?: return .unknown
        case nil: return saved.map { from($0, now: now) } ?? .unknown
        }
    }

    static func from(_ status: DebridStatus, now: Date) -> Self {
        switch status.state(now: now) {
        case .expired: .expired
        case .free: .free
        case .active, .expiringSoon: .ok
        }
    }
}
