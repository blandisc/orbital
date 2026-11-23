import Foundation
import OrbitalCore

/// CX8-A · «Darle su propia conexión»: un aparato que entró con el QR de antes la pide sin volver a escanear. La TV pregunta
/// en su pantalla («¿Darle su propia conexión a iPhone de Fernando?») y aquí se espera: «Confirma en tu TV». Si dice que no o
/// no contesta a tiempo, se dice en palabras y queda «Escanear».
@MainActor
public final class OrbitalUpgradeModel: ObservableModel {
    public enum Stage: Equatable, Sendable { case naming, waiting, done, denied, timedOut, failed(String) }
    public private(set) var stage: Stage = .naming { didSet { if oldValue != stage { changed() } } }
    /// CX7-A · el nombre que verá la TV (≤ 60), ya escrito con la sugerencia.
    public var name: String { didSet { if oldValue != name { changed() } } }
    private let services: Services
    private let pollEvery: Duration
    private let giveUpAfter: TimeInterval

    public init(_ services: Services, traktName: String? = nil, pollEvery: Duration = .seconds(2), giveUpAfter: TimeInterval = 120) {
        self.services = services; self.pollEvery = pollEvery; self.giveUpAfter = giveUpAfter
        name = services.suggestedDeviceName(traktName: traktName)
        super.init()
    }

    public func start() async {
        guard services.canUpgradeConnection, stage != .waiting else { return }
        stage = .waiting
        let clean = services.rememberDeviceName(name)
        let remote = services.orbital
        let started = services.now()
        do {
            var step = try await remote.upgrade(name: clean, platform: services.platform)
            while case .pending(let id) = step {
                if services.now().timeIntervalSince(started) > giveUpAfter { stage = .timedOut; return }
                try await Task.sleep(for: pollEvery)
                step = try await remote.upgradeStatus(id)
            }
            switch step {
            case .approved(let paired): try await services.finishUpgrade(paired); stage = .done
            case .denied: stage = .denied
            case .expired, .pending: stage = .timedOut
            }
        } catch is CancellationError { stage = .naming }
        catch let failure as OrbitalRemote.Failure { stage = .failed(failure.description) }
        catch { stage = .failed(OrbitalRemote.Failure.unreachable.description) }
    }

    /// «Intentar otra vez».
    public func reset() { stage = .naming }
}
