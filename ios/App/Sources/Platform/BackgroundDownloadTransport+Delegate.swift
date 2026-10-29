import Foundation
import UIKit
import OrbitalCore

/// Lo que `URLSession` le cuenta a la sesión de fondo: avance, archivo terminado, errores, y el carril rápido por pedazos.
extension BackgroundDownloadTransport {
    // MARK: URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (id, part, context) = current(downloadTask) else { return }   // una tarea vieja (cambiada o cancelada): no cuenta
        if let part, context.parts != nil {
            // Con datos de reanudación `totalBytesWritten` ya incluye lo que esa tarea había bajado; se suma a lo que ya tenía el
            // archivo del pedazo (lo del carril rápido).
            let base = lock.withLock { backgroundBase[id]?[part] } ?? got(id, part)
            lock.withLock { backgroundBase[id, default: [:]][part] = base; partWritten[id, default: [:]][part] = base + totalBytesWritten }
            return reportParts(id, context)
        }
        let response = downloadTask.response as? HTTPURLResponse
        var base: Int64 = 0
        var total: Int64? = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        if !context.usedResumeData, response?.statusCode == 206, let range = response?.value(forHTTPHeaderField: "Content-Range"),
           let parts = range.split(separator: "/").last, let full = Int64(parts) { total = full; base = full - max(totalBytesExpectedToWrite, 0) }
        report(id, written: base + totalBytesWritten, total: total)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (id, part, context) = current(downloadTask) else {
            // Sin contexto pero sin otra tarea vigente (se perdió al cerrar la app): que la cola lo vuelva a pedir, no que se
            // quede «descargando» para siempre.
            if let id = Self.parse(downloadTask.taskDescription)?.id, lock.withLock({ contexts[id] }) == nil {
                continuation.yield(.failed(id: id, status: nil, message: "Se perdió la descarga; se vuelve a pedir"))
            }
            return
        }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Demasiadas conexiones a la vez (el servidor dice «espera»): ese pedazo se pide otra vez en un rato, cuando otro
            // termine y libere lugar; los demás siguen.
            if let part, context.parts != nil, status == 429 || status == 503 { return retryPart(id, part: part, token: context.token) }
            // Un 403/404/410 no es un archivo: Real-Debrid dice que el enlace caducó.
            if context.parts != nil { return failParts(id, token: context.token, status: status, message: DownloadMessages.forStatus(status)) }
            continuation.yield(.failed(id: id, status: status, message: DownloadMessages.forStatus(status)))
            return
        }
        if let part, let parts = context.parts, part < parts.count { return finishPart(id, part: part, location: location, status: status, parts: parts) }
        let destination = absolute(context.file)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if status == 206, !context.usedResumeData {
                // Un trozo (se pidió con Range): solo sirve si el parcial está ahí; si no, se pide completo otra vez.
                guard FileManager.default.fileExists(atPath: destination.path) else {
                    continuation.yield(.failed(id: id, status: nil, message: "Falta el archivo parcial"))
                    return
                }
                try append(location, to: destination)
            } else {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            }
            excludeFromBackup(destination)
            try? FileManager.default.removeItem(at: resumeFile(id))
            continuation.yield(.finished(id: id))
        } catch {
            continuation.yield(.failed(id: id, status: nil, message: "No pude guardar el archivo: \(error.localizedDescription)"))
        }
    }

    func retryPart(_ id: String, part: Int, token: String?) {
        let key = "\(id)#\(part)"
        let attempt = lock.withLock { () -> Int in throttled[key, default: 0] += 1; return throttled[key]! }
        guard attempt <= Self.throttleRetries else {
            return failParts(id, token: token, status: 429, message: DownloadMessages.forStatus(429))
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(min(30, 2 << min(attempt, 4))) * 1_000_000_000)
            guard let context = lock.withLock({ contexts[id] }), context.token == token else { return }
            let live = await session.allTasks.filter { Self.parse($0.taskDescription)?.id == id }
            startParts(id: id, context: context, live: live)
        }
    }

    /// Un pedazo terminó en segundo plano: se guarda aparte (hay que sacarlo antes de que el sistema lo borre; si el carril
    /// rápido ya había bajado el principio, va detrás de eso) y, si era el último, se junta todo.
    func finishPart(_ id: String, part: Int, location: URL, status: Int, parts: [Part]) {
        let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64) ?? 0
        let token = lock.withLock { contexts[id]?.token }
        // Justo al volver a la app ese pedazo ya lo baja el carril rápido: este resultado se tira (escribirían los dos el archivo).
        if lock.withLock({ streams[id]?[part] != nil }) { return }
        let have = min(parts[part].size, got(id, part))
        // Un 200 a una petición de pedazo trae el archivo entero (el servidor ignoró el Range): no sirve como pedazo.
        guard status == 206, size == parts[part].size - have else {
            return failParts(id, token: token, status: nil, message: "El servidor no mandó el pedazo completo")
        }
        do {
            try FileManager.default.createDirectory(at: partFolder(id), withIntermediateDirectories: true)
            if have > 0 { try append(location, to: partFile(id, part)) }
            else {
                try? FileManager.default.removeItem(at: partFile(id, part))
                try FileManager.default.moveItem(at: location, to: partFile(id, part))
            }
        } catch {
            return failParts(id, token: token, status: nil, message: "No pude guardar el archivo: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: resumeFile(id, part: part))
        markPartDone(id, part: part)
    }

    /// Un pedazo completo (por cualquier carril): se anota y, si era el último, se junta todo.
    func markPartDone(_ id: String, part: Int) {
        let allDone = lock.withLock { () -> Bool in
            throttled["\(id)#\(part)"] = nil
            contexts[id]?.parts?[part].done = true
            partWritten[id]?[part] = nil
            backgroundBase[id]?[part] = nil
            saveContexts()
            return contexts[id]?.parts?.allSatisfy(\.done) ?? false
        }
        if allDone { assemble(id) }
        else if let context = lock.withLock({ contexts[id] }) { reportParts(id, context) }
    }
}
