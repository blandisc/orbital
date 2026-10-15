import Foundation
import Network

/// Espacio libre para lo que importa (descargas), según iOS.
enum DiskSpace {
    static func freeBytes() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

/// ¿Wi‑Fi o datos móviles? Para avisar antes de usar fuentes grandes y para «descargar solo con Wi‑Fi».
final class Connectivity: @unchecked Sendable {
    static let shared = Connectivity()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var path: NWPath?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in self?.lock.withLock { self?.path = path } }
        monitor.start(queue: DispatchQueue(label: "orbital.connectivity"))
    }

    var isCellular: Bool { lock.withLock { path?.usesInterfaceType(.cellular) == true && path?.usesInterfaceType(.wifi) != true } }
    var isOnline: Bool { lock.withLock { path?.status != .unsatisfied } }
    var isExpensive: Bool { lock.withLock { path?.isExpensive == true } }
}
