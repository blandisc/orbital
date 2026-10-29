import Foundation
import OrbitalCore

/// «¿Qué vemos?»: cuántas opciones quedan con los filtros puestos y de qué listas.
extension DecideModel {
    // MARK: cuántas quedan
    /// Cuántas opciones hay con lo elegido (o con un cambio: `change`), sin contar lo que ya viste ni lo apartado hoy. Lo
    /// que aún no se sabe (sin datos de Cinemeta) no cuenta todavía; el número sube solo cuando llegan.
    /// `strictTime`: que el tiempo filtre aunque no lo hayas elegido (los conteos del menú «Tiempo»).
    public func count(strictTime: Bool? = nil, _ change: (inout Filters) -> Void = { _ in }) -> Int {
        let strict = strictTime ?? timeChosen
        var f = filters
        change(&f)
        let skipped = notToday()
        let seen = f.includeWatched ? [] : (watched ?? [])
        return candidatesPool.filter { s in
            guard !skipped.contains(s.imdb), !seen.contains(s.imdb), f.kind == nil || s.kind == f.kind, let v = verdict(s, f) else { return false }
            // El tiempo de la hora (no lo elegiste) ordena, no filtra: cuenta lo mismo que se puede proponer.
            return v.matches && (v.fits || !strict)
        }.count
    }

    /// Las listas elegidas, para decir de dónde salen («de «Terror de octubre»», «de 2 listas»).
    public var chosenSourceNames: [String] { sources.filter { sourceIDs.contains($0.id) }.map(\.name) }

    /// Cuántas candidatas aún no se pueden decidir con lo elegido (falta su género, año o calificación de Cinemeta).
    public func unknownCount() -> Int {
        let f = filters
        return candidatesPool.filter { verdict($0, f) == nil }.count
    }

    public func resolveUnknown() {
        let f = filters
        let unknown = candidatesPool.filter { verdict($0, f) == nil }
        guard !unknown.isEmpty, resolving == nil else { return }
        resolving = Task { [weak self] in
            for start in stride(from: 0, to: unknown.count, by: Self.chunk) {
                guard !Task.isCancelled, let self else { return }
                await self.describe(Array(unknown[start..<min(start + Self.chunk, unknown.count)]))
            }
            self?.resolving = nil
        }
    }

    /// Nada cumple: qué quitar (o qué tiempo dar) y con cuántas quedarías; los dos que más abren.
    public func relaxations() -> [(relax: Relax, count: Int)] {
        var out: [(Relax, Int)] = []
        for g in genres { out.append((.genre(g), count { $0.genres.remove(g) })) }
        if mood != nil { out.append((.mood, count { $0.mood = nil })) }
        if kind != nil { out.append((.kind, count { $0.kind = nil })) }
        if !decades.isEmpty { out.append((.decades, count { $0.decades = [] })) }
        if minRating > 0 { out.append((.rating, count { $0.minRating = 0 })) }
        if timeChosen { for t in Time.allCases where t != time { out.append((.time(t), count(strictTime: true) { $0.time = t })) } }
        return Array(out.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(2))
    }

    public func relax(_ r: Relax) async {
        switch r {
        case .genre(let g): genres.remove(g)
        case .mood: mood = nil
        case .kind: kind = nil
        case .decades: decades = []
        case .rating: minRating = 0
        case .time(let t): time = t; timeChosen = true
        case .lists: sourceIDs = []
        }
        await apply()
    }

    /// «Limpiar» en «Más filtros»: géneros, época, listas y lo visto (la calificación va aparte).
    public func clearMoreFilters() async {
        genres = []; decades = []; includeWatched = false; sourceIDs = []
        await apply()
    }

    func prepare() async {
        dropUpcoming()
        shown = []
        exhausted = false
        if watched == nil, let trakt = services.trakt, trakt.linked {
            isLoading = true
            // Lo que ya viste, con tiempo máximo: si Trakt tarda, se decide sin eso (y se pide otra vez la próxima).
            let pending = watchedTask ?? Task { try? await trakt.watchedIDs() }
            let found = await withTaskGroup(of: Set<String>?.self) { group -> Set<String>? in
                group.addTask { await pending.value }
                group.addTask { try? await Task.sleep(nanoseconds: UInt64(Self.watchedWait * 1_000_000_000)); return nil }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            watched = found
        }
    }

    /// La siguiente que cabe. Lo que ya trae su género, duración, año y calificación se decide al momento; lo demás se le
    /// pregunta a Cinemeta, unas cuantas a la vez, con un tiempo máximo: si se acaba, la más cercana.
    ///
    /// Mientras busca, los tres de antes se quedan quietos (antes el nombre cambiaba con cada búsqueda y los carteles
    /// hasta el final); los nuevos llegan juntos, con sus datos y sus carteles.
    public func next() async {
        let key = filtersKey
        var found: [Suggestion] = []
        if let ready = upcoming.first, ready.key == key {
            upcoming.removeFirst()
            // Casi siempre ya está listo (se preparó mientras veías los de antes); si no, se espera solo a ese.
            isLoading = true
            let skipped = notToday()
            found = await ready.task.value.filter { !skipped.contains($0.imdb) }
        }
        if found.isEmpty {
            dropUpcoming()
            isLoading = true
            found = await trio(waitForPosters: true)
        }
        isLoading = false   // ya se ven: «Barajar» responde otra vez (antes esperaba también la duración y la calificación)
        picks = found
        if let first = found.first { select(first) } else { pick = nil; exhausted = true }
        // La duración y la calificación llegan después, sin bloquear nada; los siguientes se preparan desde ya.
        fillUpcoming()
        enrichPicks(found)
    }

    /// La duración y la calificación de los tres que se ven, si faltan: llegan solas al renglón de datos.
    func enrichPicks(_ found: [Suggestion]) {
        enriching?.cancel()
        guard found.contains(where: { details[$0.imdb] == nil }) else { return }
        enriching = Task { [weak self] in
            await self?.describe(found)
            guard let self, !Task.isCancelled, let current = self.pick, found.contains(where: { $0.imdb == current.imdb }) else { return }
            self.select(current)
        }
    }

    /// Tres que caben, con sus datos y sus carteles. `waitForPosters`: los de ahora esperan sus carteles un momento (si la
    /// red tarda, se enseñan igual); los que se preparan por adelantado los bajan completos, sin prisa.
    func trio(waitForPosters: Bool) async -> [Suggestion] {
        var found: [Suggestion] = []
        for _ in 0..<Self.trio {
            guard !Task.isCancelled, let p = await search(), !found.contains(where: { $0.imdb == p.imdb }) else { break }
            found.append(p)
        }
        guard !Task.isCancelled, let warm = warmPosters else { return found }
        let posters = found.compactMap(\.poster)
        if !waitForPosters { await warm(posters); return found }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await warm(posters) }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(Self.posterWait * 1_000_000_000)) }
            await group.next()
            group.cancelAll()
        }
        return found
    }

    /// Tocar uno de los tres carteles: esa es la propuesta.
    public func select(_ s: Suggestion) {
        pick = s
        minutes = s.runtime ?? details[s.imdb]?.minutes
        imdbRating = details[s.imdb]?.rating
    }

    /// La siguiente candidata que cabe (y la marca como enseñada); nil: no hay ninguna.
    func search(retried: Bool = false) async -> Suggestion? {
        let started = services.now()
        let skipped = notToday()
        let seen = includeWatched ? [] : (watched ?? [])
        func available() -> [Suggestion] {
            (order.isEmpty ? candidatesPool : order).filter {
                !shown.contains($0.imdb) && !skipped.contains($0.imdb) && !seen.contains($0.imdb) && (kind == nil || $0.kind == kind)
            }
        }
        var candidates = available()
        // Ya se enseñó todo lo que cabe: se da otra vuelta (antes se quedaba en «No encontré» sin botones).
        if candidates.isEmpty, !shown.isEmpty { shown = []; candidates = available() }
        var closest: Suggestion?   // de lo que pediste, aunque dure más: mejor eso que nada
        let f = filters
        func verdict(_ s: Suggestion) -> (matches: Bool, fits: Bool)? { self.verdict(s, f) }
        func take(_ s: Suggestion) -> Suggestion {
            shown.insert(s.imdb)
            return s
        }
        // 1) Lo que ya se sabe, sin red.
        for s in candidates {
            guard let v = verdict(s) else { continue }
            if v.matches && v.fits { return take(s) }
            if v.matches, closest == nil { closest = s }
        }
        // 2) Lo demás, de 12 en 12, mientras haya tiempo.
        let unknown = candidates.filter { verdict($0) == nil }
        for chunk in stride(from: 0, to: unknown.count, by: Self.chunk).map({ Array(unknown[$0..<min($0 + Self.chunk, unknown.count)]) }) {
            if Task.isCancelled || services.now().timeIntervalSince(started) > Self.budget { break }
            await describe(chunk)
            for s in chunk {
                guard let v = verdict(s) else { continue }
                if v.matches && v.fits { return take(s) }
                if v.matches, closest == nil { closest = s }
            }
        }
        // La más cercana (aunque dure más de lo que tienes), solo si el tiempo no lo elegiste tú: si dijiste «30 min», no se
        // propone una de dos horas. Solo esa cuenta como enseñada, no todas las revisadas.
        if let closest, !timeChosen { return take(closest) }
        // Con un filtro, las que cumplen ya salieron todas: otra vuelta desde el principio (una vez), no «No encontré».
        if !retried, !shown.isEmpty { shown = []; return await search(retried: true) }
        return nil
    }

    /// ¿Cumple? (nil: falta preguntarle a Cinemeta o a TMDB). `fits`: cabe en el tiempo.
    func verdict(_ s: Suggestion, _ f: Filters) -> (matches: Bool, fits: Bool)? {
        let d = details[s.imdb]
        let genreList = s.genres.isEmpty ? d?.genres : s.genres
        if (!f.genres.isEmpty || f.mood != nil) && genreList == nil { return nil }
        let year = s.year ?? d?.year
        if !f.decades.isEmpty && year == nil && d == nil { return nil }
        var ok = true
        if !f.genres.isEmpty { ok = Self.matches(genreList ?? [], picked: f.genres) }
        else if let mood = f.mood { ok = Self.matches(genreList ?? [], mood) }
        if ok, !f.decades.isEmpty { ok = year.map { Self.inDecades($0, f.decades) } ?? false }
        if ok, f.minRating > 0 {
            // Basta con que una de las elegidas llegue; si ninguna se sabe y falta preguntar, aún no se decide.
            var known: [Double] = []
            var pending = false
            for source in f.ratingSources {
                switch source {
                case .imdb: if let r = d?.rating { known.append(r) } else if d == nil { pending = true }
                case .trakt: if let r = s.traktRating { known.append(r) }
                case .tmdb: if let r = d?.tmdbRating { known.append(r) } else if d?.tmdbChecked != true && services.tmdb.configured { pending = true }
                }
            }
            if known.contains(where: { $0 >= f.minRating }) { ok = true }
            else if pending { return nil }
            else { ok = false }
        }
        return (ok, Self.fits(s.runtime ?? d?.minutes, f.time))
    }

    static let chunk = 12

    static let watchedWait: Double = 1.5

    /// Lo más que se busca antes de proponer la más cercana (segundos).
    static let budget: TimeInterval = 6

    /// Lo más que se espera a los carteles antes de enseñar los tres (segundos).
    static let posterWait: Double = 1.2

    /// Volver a las preguntas.
    public func reset() async { pick = nil; exhausted = false; dropUpcoming() }

    /// Al cerrar la hoja: lo que se preparaba en segundo plano ya no hace falta.
    public func stop() {
        dropUpcoming(); enriching?.cancel(); describingAll?.cancel(); describingAll = nil; ratingTMDB?.cancel(); ratingTMDB = nil
        resolving?.cancel(); resolving = nil
    }

    /// «No me interesa» (lo mismo que en Para ti): ya no se sugiere en ningún lado (ni en la TV) y se cambia por otra.
    public func notInterested() async {
        if let pick {
            await services.forYou.dismiss(pick.imdb)
            if services.orbital.isConfigured { await services.forYouRemote.dismiss(pick.imdb) }
        }
        await skipToday()
    }

    /// «Hoy no»: no vuelve a salir en 24 horas; y otra.
    public func skipToday() async {
        if let pick {
            var skipped = notTodayRaw()
            skipped[pick.imdb] = services.now().timeIntervalSince1970
            services.kv.set(Self.skipKey, data: try? JSONEncoder().encode(skipped))
            // Solo esa se cambia por otra; las otras dos se quedan.
            let current = pick.imdb
            let others = picks.filter { $0.imdb != current }
            dropUpcoming()   // los preparados ya no cuentan (se piden otros abajo, sin esperar a los viejos)
            if let fresh = await search(), !others.contains(where: { $0.imdb == fresh.imdb }) {
                await describe([fresh])
                await warmPosters?([fresh.poster].compactMap { $0 })
                picks = picks.map { $0.imdb == current ? fresh : $0 }
                select(fresh)
            } else {
                picks = others
                if let first = others.first { select(first) }
            }
            fillUpcoming()
            return
        }
        await next()
    }

    func notTodayRaw() -> [String: Double] {
        services.kv.data(Self.skipKey).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
    }

    func notToday() -> Set<String> {
        let now = services.now().timeIntervalSince1970
        return Set(notTodayRaw().filter { now - $0.value < 24 * 3600 }.keys)
    }

    func describe(_ items: [Suggestion]) async {
        let cinemeta = services.cinemeta
        let missing = items.filter { details[$0.imdb] == nil }
        let found = await withTaskGroup(of: (String, [String], Int?, Double?, Int?).self) { group in
            for s in missing {
                group.addTask {
                    guard let meta = try? await cinemeta.meta(kind: s.kind, id: s.imdb) else { return (s.imdb, [], nil, nil, nil) }
                    let info = CinemetaParsing.describe(meta)
                    let seconds = CinemetaParsing.runtimeSeconds(info.runtime); let minutes = seconds > 0 ? Int(seconds / 60) : nil
                    let rating = (meta["imdbRating"]?.string).flatMap(Double.init) ?? meta["imdbRating"]?.doubleValue
                    let year = (meta["year"]?.string).flatMap { Int($0.prefix(4)) } ?? meta["year"]?.intValue
                    return (s.imdb, (meta["genres"]?.array ?? meta["genre"]?.array ?? []).compactMap(\.string), minutes, rating, year)
                }
            }
            var out: [(String, [String], Int?, Double?, Int?)] = []
            for await r in group { out.append(r) }
            return out
        }
        var learned = false
        for (id, genres, minutes, rating, year) in found {
            let old = details[id]
            details[id] = Detail(genres: genres, minutes: minutes, rating: rating, year: year, tmdbRating: old?.tmdbRating, tmdbChecked: old?.tmdbChecked)
            learned = learned || !genres.isEmpty || minutes != nil || rating != nil || year != nil
        }
        if learned { saveDetails(); changed() }   // los conteos («34 opciones») suben solos
    }

    /// Se guardan solo los que trajeron algo (un fallo de red se vuelve a preguntar la próxima vez), hasta un tope.
    func saveDetails() {
        var keep = details.filter { !$0.value.genres.isEmpty || $0.value.minutes != nil || $0.value.rating != nil || $0.value.year != nil }
        if keep.count > Self.detailsLimit { keep = Dictionary(uniqueKeysWithValues: keep.prefix(Self.detailsLimit).map { ($0.key, $0.value) }) }
        services.kv.set(Self.detailsKey, data: try? JSONEncoder().encode(keep))
    }
}
