import Foundation
import OrbitalAddons

/// Preguntarle a cada complemento y lo que pasa con el que llega tarde (Fernando, 12 nov, Los Simpson T11E2: «me salen puros
/// episodios en inglés… me salieron todas de Comet»). Antes, pasados `budget` segundos y con Comet ya contestando, a Torrentio
/// se le cortaba la pregunta y sus versiones (las latinas) no llegaban nunca: la búsqueda guardada (15 s) y la de «Versión»
/// salían solo con lo de Comet. Ahora el lento sigue hasta su tope (`perAddon`) y lo que trae se suma a la búsqueda guardada;
/// «Versión» lo espera y se rehace. Y la bitácora dice qué dio cada uno y cuánto tardó.
extension StreamFinder {
    /// Lo que contestaron los complementos en una búsqueda, con su número (para sumarle lo que llegue tarde).
    struct Asked: Sendable {
        var serving: [Addon]
        var results: [[JSON]?]
        var id: UUID
    }

    /// La bitácora del reproductor (la pone la app): sin direcciones, solo el nombre de cada complemento.
    public func configureNotes(_ note: @escaping @Sendable (String) -> Void) { self.note = note }

    /// «Reintentar» de «No contestó a tiempo»: se olvida lo de ese video y la siguiente búsqueda les pregunta a todos.
    public func retryQuiet(kind: String, videoID: String) {
        forget(kind: kind, videoID: videoID)
        askEveryone.insert("\(kind):\(videoID)")
    }

    /// Espera a los complementos lentos de la última búsqueda de ese video. true si alguno trajo versiones (lo ordenado ya no
    /// vale: se vuelve a pedir y salen con lo nuevo). false si no había ninguno en camino o no trajeron nada.
    public func lateAnswers(kind: String, videoID: String) async -> Bool {
        guard let late = lateTasks["\(kind):\(videoID)"] else { return false }
        return await late.task.value
    }

    func fetch(_ addon: Addon, kind: String, videoID: String) async -> [JSON]? {
        // nil si la red falló (para no recordar «no hay» 10 minutos)
        guard let url = URL(string: "\(addon.base)/stream/\(kind)/\(uriComponent(videoID)).json") else { return nil }
        let start = Date()
        do {
            let streams = try await http.getJSON(url, timeout: Self.slowAfter)?["streams"]?.array ?? []
            health?.ok(addon.url, seconds: Date().timeIntervalSince(start))
            // Lo que trajo, contado (sin direcciones ni claves): la próxima vez la bitácora dice por qué dio 0 (13 nov).
            let report = AddonAnswerReport(streams: streams, addonName: addon.name, addonURL: addon.url)
            note("complemento \(addon.name): \(report.line)")
            // Puros torrents de un complemento con Real-Debrid: la dirección va sin tu clave. No es «no tiene»: se rearma.
            if report.torrentsInsteadOfLinks {
                note("complemento \(addon.name): \(report.onlyTorrent) entradas sin enlace: la dirección va sin tu clave")
                keylessAnswers.insert(addon.url)
                return nil
            }
            let found = streams.filter { $0.object != nil && ($0["url"]?.nonEmptyString != nil || $0["infoHash"]?.nonEmptyString != nil) }
            // M6: si solo da torrents, el iPhone no puede reproducir nada de él (la TV sí).
            if !found.isEmpty { health?.answered(addon.url, onlyTorrents: AddonTorrents.onlyTorrents(found.map { ($0["url"]?.string, $0["infoHash"]?.string) })) }
            return found
        } catch let error as NetworkError where error.description.hasPrefix("HTTP 4") && !Self.busy(error) {
            health?.ok(addon.url, seconds: Date().timeIntervalSince(start))
            note("complemento \(addon.name): \(error.description) (cuenta como «no tiene ese video»)")
            return []   // contestó (no tiene ese video): eso es «no hay», no un fallo de red
        } catch {
            if !Task.isCancelled { health?.fail(addon.url) }   // no esperarlo porque otro ya contestó no es un fallo
            return nil
        }
    }

    func askAll(kind: String, videoID: String, everyone: Bool) async throws -> Asked {
        var all = try await registry.serving("stream", kind: kind, itemID: videoID)
        var ids = [String: String]()   // M5: a los que solo saben de IMDb, con el id traducido
        if IDBridge.isForeign(videoID), let bridge, let imdb = await bridge.videoID(videoID, kind: kind) {
            let known = Set(all.map(\.url))
            for addon in try await registry.serving("stream", kind: kind, itemID: imdb) where !known.contains(addon.url) {
                all.append(addon); ids[addon.url] = imdb
            }
        }
        // Los que no contestan se saltan (C2); si son todos, se les pregunta igual: nunca te quedas sin preguntar.
        let awake = everyone ? all : all.filter { health?.skip($0.url) != true }
        let serving = awake.isEmpty ? all : awake
        let key = "\(kind):\(videoID)"
        let skipped = awake.isEmpty || everyone ? [] : all.filter { health?.skip($0.url) == true }.map(\.name)
        skippedByHealth[key] = skipped
        for name in skipped { note("complemento \(name): se saltó (no contestó las últimas veces)") }
        emit(key, .asking(serving.map(\.name)))
        // Un complemento lento no detiene a los demás: pasado `budget`, si alguno ya dio fuentes, la búsqueda sigue sin él;
        // el lento sigue hasta su tope y lo que traiga se suma después (`absorb`).
        let budget = limits.budget, perAddon = limits.perAddon, addonHealth = health
        let asked = UUID(), board = ArrivalBoard(count: serving.count)
        let tasks: [Task<[JSON]?, Never>] = serving.enumerated().map { i, addon in
            let id = ids[addon.url] ?? videoID
            return Task {
                // Con tope propio: un servidor que gotea (o una red que no hace caso a la cancelación) no detiene la búsqueda.
                let got: [JSON]?? = await Deadline.within(perAddon, or: .none) { .some(await self.fetch(addon, kind: kind, videoID: id)) }
                if case .none = got, !Task.isCancelled { addonHealth?.fail(addon.url) }
                let streams = got ?? nil
                let (late, seconds) = board.arrive(i, streams)
                if !Task.isCancelled { await self.arrived(key: key, asked: asked, index: i, name: addon.name, streams: streams, seconds: seconds, late: late) }
                return streams
            }
        }
        let timer = Task { try? await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000)); board.budgetPassed() }
        let snapshot = await withTaskCancellationHandler {
            await board.wait()
        } onCancel: {
            tasks.forEach { $0.cancel() }; timer.cancel(); board.release()
        }
        timer.cancel()
        happened[key] = nil
        let pending = snapshot.arrived.indices.filter { !snapshot.arrived[$0] }
        if Task.isCancelled { tasks.forEach { $0.cancel() } }
        else if !pending.isEmpty {
            for i in pending { note("complemento \(serving[i].name): sigue buscando a los \(Self.seconds(budget)) s; lo que traiga se suma") }
            let waiting = pending.map { tasks[$0] }
            lateTasks[key] = (asked, Task {
                var got = false
                for task in waiting {
                    let streams = await task.value
                    if !(streams ?? []).isEmpty { got = true }
                }
                await self.lateDone(key: key, asked: asked)
                return got
            })
        }
        return Asked(serving: serving, results: snapshot.results, id: asked)
    }

    /// Contestó un complemento: a la bitácora y a quien mira la búsqueda; si llegó tarde, se suma a lo guardado.
    func arrived(key: String, asked: UUID, index: Int, name: String, streams: [JSON]?, seconds: Double, late: Bool) {
        let found = streams?.filter { $0["url"]?.nonEmptyString != nil }.count
        let time = Self.seconds(seconds)
        if let found { note("complemento \(name): \(found) versiones en \(time) s\(late ? " (llegó tarde: se suman)" : "")") }
        else { note("complemento \(name): no contestó (\(time) s)") }
        emit(key, .answered(addon: name, found: found))
        if late { absorb(key: key, asked: asked, index: index, streams: streams) }
    }

    /// Lo que trajo un complemento lento, a la búsqueda guardada de ese video (si sigue siendo la misma). Si todavía no se
    /// guarda, espera en `lateBuffer`. Lo ordenado de ese video ya no vale.
    func absorb(key: String, asked: UUID, index: Int, streams: [JSON]?) {
        guard streams != nil else { return }   // tampoco contestó después: sigue como «no contestó»
        guard var entry = answers[key], entry.asked == asked else {
            if asking[key] != nil || answers[key] == nil {
                if lateBuffer.count >= Self.cacheMax { lateBuffer = [:] }
                lateBuffer[asked, default: [:]][index] = streams
            }
            return
        }
        guard entry.answers.results.indices.contains(index) else { return }
        entry.answers.results[index] = streams
        entry.failed = entry.answers.results.contains { $0 == nil }
        entry.expires = clock().addingTimeInterval(entry.failed ? Self.retryFailed : Self.cacheSeconds)
        answers[key] = entry
        let prefix = key + ":"
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
    }

    private func lateDone(key: String, asked: UUID) {
        if lateTasks[key]?.asked == asked { lateTasks[key] = nil }
    }

    /// «4,2» (como «Contesta lento · 4,2 s»).
    static func seconds(_ value: Double) -> String { String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",") }

    /// Lo aprendido de otra versión del mismo paquete (la huella del torrent) o de su familia (`bingeGroup`): sus idiomas, como
    /// «probable» (`sibling`), solo si incluyen lo que dice el nombre (se agrega lo que faltaba; nunca se contradice el nombre).
    static func learned(_ source: Source, _ checked: @Sendable (String) -> [AudioLanguage]?) -> [AudioLanguage]? {
        let keys = [source.torrent.map { TitlePreferences.packKey($0.hash) }, source.binge.map(TitlePreferences.familyKey)].compactMap { $0 }
        for key in keys {
            // «ESP» (español sin decir cuál) lo cumple un latino o un castellano comprobado.
            guard let real = checked(key), !real.isEmpty,
                  source.audio.allSatisfy({ said in real.contains { $0.code == said.code || $0.base == said.code } }) else { continue }
            return real.map { AudioLanguage($0.code, $0.evidence == .checked ? .sibling : $0.evidence) }
        }
        return nil
    }
}

/// Quién ya contestó en una búsqueda y cuándo se deja de esperar: todos contestaron, o pasó el plazo y alguno ya dio
/// versiones. Lo que llega después de eso es «tarde».
final class ArrivalBoard: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [[JSON]?]
    private var arrived: [Bool]
    private var overBudget = false
    private var done = false
    private var waiter: CheckedContinuation<(results: [[JSON]?], arrived: [Bool]), Never>?
    private let start = Date()

    init(count: Int) { results = Array(repeating: nil, count: count); arrived = Array(repeating: false, count: count) }

    /// Llegó la respuesta `i`. Devuelve si llegó tarde (la búsqueda ya siguió sin ella) y cuánto tardó.
    func arrive(_ i: Int, _ streams: [JSON]?) -> (late: Bool, seconds: Double) {
        let seconds = Date().timeIntervalSince(start)
        let late: Bool = lock.withLock {
            if done { return true }
            results[i] = streams; arrived[i] = true
            return false
        }
        if !late { check() }
        return (late, seconds)
    }

    func budgetPassed() { lock.withLock { overBudget = true }; check() }

    /// Se canceló quien espera: se suelta con lo que haya.
    func release() { finish() }

    func wait() async -> (results: [[JSON]?], arrived: [Bool]) {
        await withCheckedContinuation { continuation in
            let ready: (results: [[JSON]?], arrived: [Bool])? = lock.withLock {
                if done { return (results, arrived) }
                waiter = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) } else { check() }
        }
    }

    private func check() {
        let ready = lock.withLock { !done && (arrived.allSatisfy { $0 } || (overBudget && results.contains { !($0 ?? []).isEmpty })) }
        if ready { finish() }
    }

    private func finish() {
        let (target, value): (CheckedContinuation<(results: [[JSON]?], arrived: [Bool]), Never>?, (results: [[JSON]?], arrived: [Bool])) = lock.withLock {
            let value = (results: results, arrived: arrived)
            guard !done || waiter != nil else { return (nil, value) }
            done = true
            let target = waiter; waiter = nil
            return (target, value)
        }
        target?.resume(returning: value)
    }
}
