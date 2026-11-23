import Foundation
import Network
import os
import OrbitalCore
import UIKit
import SwiftUI

/// Espacio libre para lo que importa (descargas), según iOS.
enum DiskSpace {
    /// Nunca espera al disco en la pantalla: da lo último que se supo y, si ya es viejo (más de `fresh` segundos), lo vuelve a
    /// preguntar por detrás. Preguntar cuesta 10–125 ms en la Mac (CacheDelete recorre los volúmenes); Descargas lo pedía en
    /// cada repintada (17 nov 2026) y la ficha de una serie, al pintar su menú de descargas (22 nov 2026: 125 ms al abrirla).
    static func freeBytes() -> Int64 {
        let last = cache.withLock { $0 }
        guard let last else { return measure() }   // la primera vez (casi siempre ya la midió `warm()` al abrir la app)
        if Date().timeIntervalSince(last.at) >= fresh { warm() }
        return last.bytes
    }

    /// Lo mide por detrás (al abrir la app y cuando lo que se sabe ya es viejo).
    static func warm() {
        guard refreshing.withLock({ busy in defer { busy = true }; return !busy }) else { return }
        Task.detached(priority: .utility) { _ = measure(); refreshing.withLock { $0 = false } }
    }

    private static func measure() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let bytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
        cache.withLock { $0 = (Date(), bytes) }
        return bytes
    }
    private static let fresh: TimeInterval = 5
    private static let cache = OSAllocatedUnfairLock<(at: Date, bytes: Int64)?>(initialState: nil)
    private static let refreshing = OSAllocatedUnfairLock(initialState: false)

    /// La capacidad del iPhone (para la barra de espacio de Descargas): no cambia, se pregunta una vez.
    static func totalBytes() -> Int64 { total }   // la primera vez la pide Descargas; no vuelve a preguntar
    private static let total: Int64 = {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey])
        return Int64(values?.volumeTotalCapacity ?? 0)
    }()
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

/// Este aparato para tu Orbital: su nombre (desde iOS 16, sin el permiso del nombre, iOS da solo «iPhone» o «iPad»), si
/// es iPhone o iPad y su id por instalación. La TV solo acepta `iphone` e `ipad` (`orbital/companion.py`): la Mac
/// («Diseñada para iPad») se presenta como iPad hasta que la TV conozca `mac` (Etapa 2 de `docs/producto/ipad-y-mac-2026-10.md`).
enum ThisDevice {
    /// Solo el iPhone habla con tu Orbital. La Mac es solo para ver (decisión de Fernando, 29 oct 2026; CX1-B, 3 nov: «La Mac no
    /// se conecta con la TV para nada») y el iPad también (18 nov, confirmada el 23 nov en PA5-A: «El iPad no se conecta a la
    /// TV»): sin control, voz, «Ver en la TV», invitación ni acompañante de juegos. Los dos reciben tu clave de Real-Debrid por
    /// iCloud (CX2-A). `MacNeverTalksToTheTVTests` cuida que esto no cambie.
    static let talksToOrbital = !ProcessInfo.processInfo.isiOSAppOnMac && !runsOnIPad
    /// ¿Es un iPad? Por el modelo del aparato y no por `UIDevice` (que es del hilo principal; esto se lee al armar `Services`).
    private static let runsOnIPad: Bool = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated.hasPrefix("iPad") }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine.hasPrefix("iPad")
    }()
    /// La Mac («Diseñada para iPad»): sus pestañas van en el renglón del logo y la letra es más grande (MAC-A, 16 nov 2026).
    static let isMac = ProcessInfo.processInfo.isiOSAppOnMac || macLookForDemo
    /// Adornos que se mueven solos (el cielo, el muro de Explorar, los canales que se deslizan): en la Mac, quietos. Su pantalla
    /// va a 165 Hz y a todo lo ancho: el compositor de la Mac (WindowServer) se iba a 60–95 % con Orbital en reposo y ni la
    /// ventana se dejaba mover (Fernando, 22 nov 2026: «está inusable»). En la Mac se mueve lo que tocas, nada más.
    /// `DesignRulesTests` cuida que todo adorno en movimiento pregunte por esto.
    static let ambientMotion = !ProcessInfo.processInfo.isiOSAppOnMac
    /// `-demo-mac-look` (solo Debug): el acomodo de la Mac (pestañas en cápsula, ficha en filas, Buscar grande, ▶ ＋) en el
    /// simulador del iPad, para recorrer los flujos de la Mac con XCUITest cuando nadie está frente a la Mac (allí la app de
    /// iPad se queda dormida si no se ve). Solo cambia `isMac`; la letra y los tamaños siguen siendo los del iPad.
    #if DEBUG
    private static let macLookForDemo = Demo.has("-demo-mac-look")
    #else
    private static let macLookForDemo = false
    #endif
    /// Qué trae esta app aquí (D1-B): la versión de la compilación (`ORBITAL_EDITION` → Info.plist › `OrbitalEdition`, leída una
    /// vez; sin ella, Ultra) y si este aparato habla con la TV. Lo que no recibe `Services` (Siri, el menú, la actividad en
    /// vivo) pregunta aquí; lo demás, a `services.capabilities`, que se arma con esto mismo.
    static let capabilities = Capabilities(edition: .bundled(), talksToOrbital: talksToOrbital)
    /// «iphone», «ipad» o «mac»: quién puso la copia compartida de tu clave, y quién quita a quién (CX5).
    @MainActor static var platform: String {
        ProcessInfo.processInfo.isiOSAppOnMac ? "mac" : UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }
    /// El símbolo de este aparato («Para ver sin internet», RX1-A).
    @MainActor static var symbol: String { ["mac": "laptopcomputer", "ipad": "ipad"][platform] ?? "iphone" }
    /// Brillo y volumen con el dedo sobre el video (iPhone, iPad). En la Mac no aplican.
    static let hasTouchScreenControls = !ProcessInfo.processInfo.isiOSAppOnMac
    /// Las descargas en la pantalla bloqueada y la Dynamic Island. En la Mac no existen.
    static let supportsLiveActivities = !ProcessInfo.processInfo.isiOSAppOnMac

    /// El nombre de este aparato en lo que se anota (quién pidió algo a Real-Debrid, R12): «iPhone», «iPad» o «Mac».
    @MainActor static var name: String { ProcessInfo.processInfo.isiOSAppOnMac ? "Mac" : UIDevice.current.name }

    @MainActor static var forOrbital: OrbitalRemote.Device {
        let device = UIDevice.current
        return OrbitalRemote.Device(name: device.name, kind: device.userInterfaceIdiom == .pad ? "ipad" : "iphone",
                                    id: device.identifierForVendor?.uuidString ?? "")
    }
}

/// IOS-12 · las frases con «este iPhone» que también ve la Mac (Real-Debrid: quitar tu clave, dónde se guarda, la copia de
/// tus aparatos Apple). Una app de iPad en la Mac («Diseñada para iPad») se presenta como iPad, así que la variante del
/// catálogo le diría «iPad»; aquí la palabra se elige en el código con `ThisDevice.platform`. `DeviceWordsOnMacTests` lo cuida.
enum DeviceWords {
    @MainActor static func text(_ key: LocalizedStringKey, mac: LocalizedStringKey) -> Text {
        ThisDevice.platform == "mac" ? Text(mac) : Text(key)
    }
}
