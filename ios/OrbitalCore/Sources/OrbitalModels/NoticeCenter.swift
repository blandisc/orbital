import Foundation

/// El tono de un aviso: neutral, logrado, te necesita (ámbar) o algo se perdió (rojo).
public enum NoticeTone: Sendable, Equatable { case info, success, warn, error }

/// Lo que hace el botón de un aviso: ir a Descargas, o lo que pidió quien avisó (`perform`, con su número).
public enum NoticeAction: Equatable, Sendable { case downloads, perform(Int) }

/// Un aviso de la app: lo que pasó («Descargando…») o lo que salió mal, ya en el idioma de la app.
public struct Notice: Equatable, Sendable {
    public var text: String
    public var tone: NoticeTone
    public var action: NoticeAction?
    /// Un segundo renglón («1080p · 2.4 GB») y el nombre del botón (por omisión, «Ver»), con su ícono si lo lleva.
    public var detail: String?
    public var actionTitle: String?
    public var actionSymbol: String?
    /// Otro ícono que el del tono (el del tipo al cambiar Todo · Películas · Series en Inicio).
    public var symbol: String?
    /// Su número: cada aviso es otro aunque diga lo mismo (para animar el cambio y quitar justo ese).
    public var serial = 0

    public init(text: String, tone: NoticeTone, action: NoticeAction? = nil, detail: String? = nil, actionTitle: String? = nil, actionSymbol: String? = nil, symbol: String? = nil, serial: Int = 0) {
        self.text = text; self.tone = tone; self.action = action; self.detail = detail
        self.actionTitle = actionTitle; self.actionSymbol = actionSymbol; self.symbol = symbol; self.serial = serial
    }
}

/// La cola de avisos de la app: uno a la vista; uno con salida («Deshacer») no se pisa, los demás esperan detrás
/// (hasta `queueLimit`). Quien pinta lee `current` (se vuelve a pintar con cada cambio); quien avisa llama `show`.
@MainActor
public final class NoticeCenter: ObservableModel {
    public let queueLimit: Int
    private var shown: Notice?
    private var queue: [Notice] = []
    /// Lo que corre el botón de cada aviso con `.perform` (el de la vista y los que esperan).
    private var performs: [Int: () -> Void] = [:]
    private var serial = 0

    public init(queueLimit: Int) {
        self.queueLimit = queueLimit
        super.init()
    }

    /// El aviso a la vista (la vista que lo lee mientras se pinta se vuelve a pintar al cambiar).
    public var current: Notice? { track(); return shown }
    /// Cuántos esperan detrás del que se ve.
    public var waiting: Int { queue.count }

    /// Guarda lo que hace el botón de un aviso y da el número con que se pide (`.perform(n)`).
    public func register(_ perform: @escaping () -> Void) -> Int {
        serial += 1
        performs[serial] = perform
        return serial
    }

    /// Pone el aviso, o lo forma detrás del que está si ese trae salida (así no se pierde un «Deshacer»).
    public func show(_ notice: Notice) {
        var new = notice
        if new.serial == 0 { serial += 1; new.serial = serial }
        if let current = shown, current.action != nil, current.text != new.text {
            queue.removeAll { $0.text == new.text }
            queue.append(new)
            while queue.count > queueLimit { forget(queue.removeFirst()) }
            return
        }
        if let current = shown { forget(current) }
        shown = new
        changed()
    }

    /// Se fue (se acabó su tiempo, lo tocaste o lo deslizaste): sale el siguiente que esperaba.
    public func dismiss(_ serial: Int) {
        guard let current = shown, current.serial == serial else { return }
        forget(current)
        shown = queue.isEmpty ? nil : queue.removeFirst()
        changed()
    }

    /// Corre lo que pidió quien avisó con `.perform(n)` (si sigue vigente).
    public func perform(_ n: Int) { performs[n]?() }

    private func forget(_ notice: Notice) { if case .perform(let n)? = notice.action { performs[n] = nil } }
}
