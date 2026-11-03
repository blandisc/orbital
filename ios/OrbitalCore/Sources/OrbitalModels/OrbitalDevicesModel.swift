import Foundation
import OrbitalCore

/// K1 · Ajustes › Tu Orbital › los aparatos de tu TV: cada uno con su nombre y cuándo se usó, este marcado, y «Quitar» (con
/// confirmación, sin deshacer). Quitar este aparato borra su llave y lo deja sin emparejar.
@MainActor
public final class OrbitalDevicesModel: ObservableModel {
    public enum Load: Equatable, Sendable { case idle, loading, loaded, failed(String) }
    public private(set) var devices: [OrbitalPairedDevice] = [] { didSet { if oldValue != devices { changed() } } }
    public private(set) var load: Load = .idle { didSet { if oldValue != load { changed() } } }
    /// Por qué no se pudo quitar uno (en palabras); nil si no pasó nada.
    public private(set) var problem: String? { didSet { if oldValue != problem { changed() } } }
    private let services: Services

    public init(_ services: Services) { self.services = services; super.init() }

    /// Solo con la llave de este aparato (la lista es suya).
    public var isAvailable: Bool { services.hasOrbitalDeviceKey }

    public func refresh() async {
        guard isAvailable else { devices = []; load = .idle; return }
        if devices.isEmpty { load = .loading }
        do {
            // Este primero; los demás, el más reciente arriba.
            devices = try await services.orbital.devices().sorted { a, b in
                a.isThis != b.isThis ? a.isThis : (a.seen ?? a.pairedAt ?? .distantPast) > (b.seen ?? b.pairedAt ?? .distantPast)
            }
            load = .loaded
        } catch let failure as OrbitalRemote.Failure { load = .failed(failure.description) }
        catch { load = .failed(OrbitalRemote.Failure.unreachable.description) }
    }

    /// «Quitar» (la pantalla ya preguntó). Si es este aparato, se olvida su llave: queda sin emparejar.
    public func remove(_ device: OrbitalPairedDevice) async {
        problem = nil
        do {
            try await services.orbital.removeDevice(device.id)
            devices.removeAll { $0.id == device.id }
            if device.isThis { services.forgetThisDevice(); devices = [] }
        } catch let failure as OrbitalRemote.Failure { problem = failure.description }
        catch { problem = OrbitalRemote.Failure.unreachable.description }
    }
}
