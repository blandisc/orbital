import BackgroundTasks
import Foundation
import UIKit
import OrbitalCore

/// Que las descargas sigan a toda velocidad con la app cerrada: una tarea continua de iOS 26 (`BGContinuedProcessingTask`).
/// Se pide con la app a la vista cuando empieza a bajar algo; mientras dura, la app sigue viva en segundo plano y el carril
/// rápido del transporte (`BackgroundDownloadTransport`) no se suelta. iOS enseña su avance en su propia actividad y ahí la
/// puedes cancelar; si la cancelas o iOS la corta (poca batería, memoria), lo que falta pasa a la sesión de segundo plano
/// (más lenta) sin perder lo bajado.
@MainActor
final class DownloadContinuation {
    /// Debe estar en `BGTaskSchedulerPermittedIdentifiers` de `project.yml` (y empezar con el id de la app).
    static let identifier = "mx.iracheta.orbital.downloads.keep"

    private var task: BGContinuedProcessingTask?
    private var submitted = false
    private var registered = false
    /// Las descargas de esta tanda (las terminadas cuentan completas: el avance no se regresa al acabar una).
    private var batch: Set<String> = []
    /// Lo que hace la app cuando la tarea arranca (el carril rápido, aunque ya te hayas ido) y cuando se acaba antes de tiempo
    /// (lo que falta pasa al carril de segundo plano).
    var onStarted: () async -> Void = {}
    var onExpired: () async -> Void = {}
    var language: () -> String = { "es" }

    /// ¿Está corriendo? (la app al irse a segundo plano no suelta el carril rápido). Pedida pero sin arrancar no cuenta: si iOS
    /// no la arranca, las descargas no se quedan en un carril que se congela con la app suspendida.
    var isRunning: Bool { task != nil }

    /// Cada cambio de la cola: con algo bajando y la app a la vista, se pide la tarea; sin nada pendiente, se termina.
    func update(_ items: [DownloadItem]) {
        let pending = items.filter { $0.state == .downloading || $0.state == .queued }
        guard !pending.isEmpty else { return finish(success: true) }
        batch.formUnion(pending.map(\.id))
        if let task { return report(items, to: task) }
        guard !submitted, UIApplication.shared.applicationState == .active else { return }
        submit(title: pending[0].title)
    }

    private func submit(title: String) {
        if !registered {
            registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { [weak self] task in
                MainActor.assumeIsolated { self?.started(task) }
            }
        }
        let request = BGContinuedProcessingTaskRequest(identifier: Self.identifier, title: Self.title(title, language: language()),
                                                       subtitle: Strings.tr("Empezando…", language: language()))
        request.strategy = .fail   // si iOS no puede ahora, no se forma para después: sigue el carril de segundo plano
        // Si iOS no la da (en el simulador nunca; en el iPhone, sin recursos), no se vuelve a pedir en esta tanda.
        do { try BGTaskScheduler.shared.submit(request) } catch { NSLog("Orbital: sin tarea continua para las descargas (%@)", String(describing: error)) }
        submitted = true
    }

    private func started(_ task: BGTask) {
        guard let task = task as? BGContinuedProcessingTask else { return task.setTaskCompleted(success: false) }
        self.task = task
        task.progress.totalUnitCount = Self.units
        Task { await onStarted() }
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, self.task != nil else { return }
                self.task = nil
                await self.onExpired()
                task.setTaskCompleted(success: false)
            }
        }
    }

    /// Nada pendiente: se acaba la tarea y la siguiente descarga que pidas pide otra.
    private func finish(success: Bool) {
        batch = []
        submitted = false
        guard let task else { return }
        task.progress.completedUnitCount = task.progress.totalUnitCount
        task.setTaskCompleted(success: success)
        self.task = nil
    }

    /// El avance de la tanda en la actividad de iOS («Descargando «Dune»» · «62 % · 5.3 GB de 8.5 GB»). Que avance de verdad
    /// importa: iOS corta primero las tareas que parecen atoradas.
    private func report(_ items: [DownloadItem], to task: BGContinuedProcessingTask) {
        let mine = items.filter { batch.contains($0.id) }
        let expected = mine.reduce(Int64(0)) { $0 + max($1.expectedBytes ?? 0, $1.writtenBytes) }
        let written = mine.reduce(Int64(0)) { $0 + ($1.state == .done ? max($1.expectedBytes ?? 0, $1.writtenBytes) : $1.writtenBytes) }
        guard expected > 0 else { return }
        let fraction = min(1, Double(written) / Double(expected))
        task.progress.completedUnitCount = Int64(fraction * Double(Self.units))
        let current = items.first { $0.state == .downloading } ?? mine.first { $0.state != .done }
        let size = ByteCountFormatter.string(fromByteCount: written, countStyle: .file) + " / " + ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
        task.updateTitle(current.map { Self.title($0.title, language: language()) } ?? task.title, subtitle: "\(Int(fraction * 100)) % · \(size)")
    }

    private static func title(_ name: String, language: String) -> String { String(format: Strings.tr("Descargando «%@»", language: language), name) }
    private static let units: Int64 = 1000
}
