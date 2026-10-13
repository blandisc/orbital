import Foundation
import OrbitalCore

/// Descargas con `URLSession` en segundo plano: el sistema sigue bajando con la app suspendida y la relanza al
/// terminar (no sobreviven a cerrar la app a la fuerza: iOS las cancela). Se reanuda con `Range` desde lo que ya hay.
///
/// Un `URLSessionDownloadTask` escribe en un archivo temporal: al terminar, si el servidor respondió 206 se agrega al
/// parcial; si respondió 200 (ignoró el Range) lo reemplaza.
final class BackgroundDownloadTransport: NSObject, DownloadTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "com.example.orbital.ios.downloads"

    private struct Context: Codable { var file: String; var resumeFrom: Int64 }
    private let lock = NSLock()
    private var contexts: [String: Context] = [:]
    private var lastProgress: [String: Date] = [:]
    private var session: URLSession!
    private let continuation: AsyncStream<DownloadEvent>.Continuation
    let events: AsyncStream<DownloadEvent>
    private let defaults: UserDefaults
    var allowsCellular: @Sendable () -> Bool = { false }
    /// Lo guarda `AppDelegate.application(_:handleEventsForBackgroundURLSession:)`.
    var backgroundCompletion: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        super.init()
        contexts = (defaults.data(forKey: "orbital.download-contexts").flatMap { try? JSONDecoder().decode([String: Context].self, from: $0) }) ?? [:]
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.isDiscretionary = false          // las pides tú: que empiecen ya
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    private func saveContexts() { defaults.set(try? JSONEncoder().encode(contexts), forKey: "orbital.download-contexts") }

    func start(id: String, url: URL, resumeFrom: Int64, file: URL) async {
        // Si ya había una tarea para ese id (la app se relanzó), se cancela: se empieza de nuevo desde lo que hay en disco.
        await cancel(id: id)
        var request = URLRequest(url: url)
        request.allowsCellularAccess = allowsCellular()
        request.setValue("Orbital", forHTTPHeaderField: "User-Agent")
        if resumeFrom > 0 { request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range") }
        let task = session.downloadTask(with: request)
        task.taskDescription = id
        lock.withLock { contexts[id] = Context(file: file.path, resumeFrom: resumeFrom); saveContexts() }
        task.resume()
    }

    func cancel(id: String) async {
        let tasks = await session.allTasks
        for task in tasks where task.taskDescription == id { task.cancel() }
        lock.withLock { contexts[id] = nil; saveContexts() }
    }

    // MARK: URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, let context = lock.withLock({ contexts[id] }) else { return }
        let response = downloadTask.response as? HTTPURLResponse
        let partial = response?.statusCode == 206
        let base = partial ? context.resumeFrom : 0
        var total: Int64?
        if partial, let range = response?.value(forHTTPHeaderField: "Content-Range"), let last = range.split(separator: "/").last, let n = Int64(last) { total = n }
        else if totalBytesExpectedToWrite > 0 { total = base + totalBytesExpectedToWrite }
        let now = Date()
        let due = lock.withLock { () -> Bool in
            if let last = lastProgress[id], now.timeIntervalSince(last) < 0.5 { return false }
            lastProgress[id] = now; return true
        }
        if due { continuation.yield(.progress(id: id, written: base + totalBytesWritten, total: total)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription, let context = lock.withLock({ contexts[id] }) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Un 403/404/410 no es un archivo: Real-Debrid dice que el enlace caducó.
            continuation.yield(.failed(id: id, status: status, message: "HTTP \(status)"))
            lock.withLock { contexts[id] = nil; saveContexts() }
            return
        }
        let destination = URL(fileURLWithPath: context.file)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if status == 206, context.resumeFrom > 0, FileManager.default.fileExists(atPath: destination.path) {
                let handle = try FileHandle(forWritingTo: destination)
                defer { try? handle.close() }
                try handle.truncate(atOffset: UInt64(context.resumeFrom))   // por si quedó algo de más al cortarse
                try handle.seekToEnd()
                let reader = try FileHandle(forReadingFrom: location)
                defer { try? reader.close() }
                while let chunk = try reader.read(upToCount: 1 << 20), !chunk.isEmpty { try handle.write(contentsOf: chunk) }
            } else {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            }
            var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
            var mutable = destination; try? mutable.setResourceValues(excluded)
            continuation.yield(.finished(id: id))
        } catch {
            continuation.yield(.failed(id: id, status: nil, message: "No pude guardar el archivo: \(error.localizedDescription)"))
        }
        lock.withLock { contexts[id] = nil; saveContexts() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }   // lo cancelamos nosotros (pausa o borrar)
        continuation.yield(.failed(id: id, status: (task.response as? HTTPURLResponse)?.statusCode, message: error.localizedDescription))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in self?.backgroundCompletion?(); self?.backgroundCompletion = nil }
    }
}
