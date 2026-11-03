import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas del filtro avanzado (la entrada A de Fernando, 31 oct 2026; maqueta en
// docs/producto/muvy-busqueda-premios/filtro-a.html): el mosaico de cada filtro con su dibujo (el mismo en la puerta de
// Buscar y en el cajón), el panel que se abre bajo su mosaico, el cuadro de «Fama» (antes «Qué tan conocida»), la opción grande con ícono y
// el cuadrito de lo filtrado sobre los resultados. La regla de años vive en `YearRuler.swift`. Sin cápsulas: íconos.
// Cada filtro tiene su color (`FilterPage.hue`, dirección A, 31 oct 2026) solo en detalles: el ícono, un puntito cuando
// tiene algo y su control abierto. Lo elegido sigue en blanco; el azul de Orbital queda en lo que es de Orbital.

/// Los filtros con mosaico. El formato (Todo · Películas · Series) no: va arriba del cajón, de un toque.
enum FilterPage: String, Hashable, CaseIterable, Identifiable {
    case genre, era, length, rating, fame, place = "where", origin, awards, studio
    var id: String { rawValue }

    /// Los seis a la vista y los de «Ver más filtros».
    static let main: [FilterPage] = [.genre, .era, .length, .rating, .fame, .place]
    static let more: [FilterPage] = [.origin, .awards, .studio]

    /// Lo tocado en la puerta de Buscar (o `-demo-open filter-genre`); nil, el cajón sin nada abierto.
    init?(door id: String?) {
        guard let id, let page = FilterPage(rawValue: id) else { return nil }
        self = page
    }

    var title: Text {
        switch self {
        case .genre: Text("Género"); case .era: Text("Época"); case .length: Text("Tiempo"); case .rating: Text("Calificación")
        case .fame: Text("Fama"); case .place: Text("Dónde verla"); case .origin: Text("Origen")
        case .awards: Text("Premios"); case .studio: Text("Estudios")
        }
    }

    /// Su color (solo en detalles). Dónde verla lleva el azul de Orbital; Estudios, blanco: el color lo ponen sus logos.
    var hue: Color {
        switch self {
        case .genre: DS.Filter.coral; case .era, .awards: DS.Filter.amber; case .length: DS.Filter.sky; case .rating: DS.Filter.lime
        case .fame: DS.Filter.meadow; case .place: DS.orbitalBlue; case .origin: DS.Filter.lavender; case .studio: DS.text
        }
    }

    var symbol: String {
        switch self {
        case .genre: "theatermasks"; case .era: "calendar"; case .length: "clock"; case .rating: "star"; case .fame: "person.2"
        case .place: "play.tv"; case .origin: "globe.americas"; case .awards: "trophy"; case .studio: "building.2"
        }
    }
}

/// Lo que los mosaicos necesitan para dibujarse: el filtro, tus plataformas y el idioma.
struct FilterContext {
    var filter: AdvancedFilter
    var platforms: [AdvancedFilterModel.Platform] = []
    var language = "es"
}

/// Los catálogos del filtro: países, regiones, el arte de cada género y los premios en su orden.
enum FilterCatalog {
    static let countries: [(code: String, name: String)] = [
        ("MX", "México"), ("AR", "Argentina"), ("CO", "Colombia"), ("BR", "Brasil"), ("US", "Estados Unidos"), ("GB", "Reino Unido"),
        ("ES", "España"), ("FR", "Francia"), ("IT", "Italia"), ("DE", "Alemania"), ("SE", "Suecia"), ("DK", "Dinamarca"),
        ("KR", "Corea del Sur"), ("JP", "Japón"), ("IN", "India"), ("CN", "China"),
    ]
    /// Primero la región, luego el país.
    static var regions: [(id: String, title: LocalizedStringKey, codes: [String])] {
        [("latam", "Latinoamérica", ["MX", "AR", "CO", "BR"]), ("europe", "Europa", ["ES", "FR", "IT", "DE", "GB", "SE", "DK"]),
         ("asia", "Asia", ["KR", "JP", "IN", "CN"])]
    }
    /// El arte de cada género: el mismo de «Por género» en Buscar y en la TV (`genre-*`, Grok Imagine), uno distinto por
    /// género (antes Aventura repetía Acción y Familia repetía Animación).
    static let genreArt = ["accion": "action", "aventura": "adventure", "animacion": "animation", "comedia": "comedy", "crimen": "crime",
                           "documental": "documentary", "drama": "drama", "familia": "family", "fantasia": "fantasy", "terror": "horror",
                           "misterio": "mystery", "romance": "romance", "ciencia-ficcion": "scifi", "suspenso": "thriller",
                           "historia": "history", "belica": "war", "western": "western", "musical": "musical"]
    static func genreImage(_ slug: String) -> String { "genre-\(genreArt[slug] ?? "drama")" }
    /// Los premios que trae la app, en el orden de Colecciones (su id es también el nombre de su estatuilla).
    static var awards: [String] { Canon.awardOrder.filter { id in Awards.all.contains { $0.id == id } } }

    /// La bandera de un país («MX» → 🇲🇽).
    static func flag(_ code: String) -> String {
        String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }))
    }
}

/// Lo que dice cada filtro en su mosaico y en los cuadritos de resultados (nil: cualquiera).
enum FilterText {
    static func format(_ f: AdvancedFilter) -> Text? {
        switch (f.format, f.seriesStatus) {
        case (.all, _): return nil
        case (.movie, _): return Text("Películas")
        case (.series, .airing): return Text("En emisión")
        case (.series, .ended): return Text("Terminadas")
        case (.series, .any): return Text("Series")
        }
    }
    static func genres(_ f: AdvancedFilter) -> Text? {
        let yes = Tmdb.filterGenres.filter { f.genres.contains($0.slug) }.map(\.title)
        let no = Tmdb.filterGenres.filter { f.excluded.contains($0.slug) }.map(\.title)
        if yes.isEmpty && no.isEmpty { return nil }
        if yes.isEmpty { return Text("Sin \(no.joined(separator: ", "))") }
        // «Fantasía o Romance»: basta con uno de ellos (con una coma parecía que debía tener todos).
        guard yes.count > 1, let last = yes.last else { return Text(verbatim: yes.joined(separator: ", ")) }
        return Text("\(yes.dropLast().joined(separator: ", ")) o \(last)")
    }
    static func years(_ f: AdvancedFilter) -> Text? {
        guard let y = f.years else { return f.spread ? Text("Repartido por décadas") : nil }
        let name: Text
        if y == AdvancedFilter.classics { name = Text("Clásicos") }
        else if y == f.releases { name = Text("Estrenos") }
        else if y.lowerBound % 10 == 0, y.upperBound == min(y.lowerBound + 9, f.currentYear) { name = Text(verbatim: Canon.decadeName(y.lowerBound)) }
        else if y.lowerBound == y.upperBound { name = Text(verbatim: String(y.lowerBound)) }
        else { name = Text(verbatim: "\(y.lowerBound)–\(y.upperBound)") }
        return f.spread ? Text("\(name), repartido") : name
    }
    static func length(_ f: AdvancedFilter, language: String) -> Text? {
        switch f.length {
        case .any: nil; case .short: Text("Cortita"); case .regular: Text("Normal"); case .long: Text("Para echarse")
        case .before: Text("Antes de las \(clock(f.endsBy, language: language))")
        }
    }
    /// «Muy buena · 7.5+», «Excelente · ★4.2+» o, con las dos, «7+ y ★3.8+» (`RatingLevels`).
    static func rating(_ f: AdvancedFilter) -> Text? { RatingLevels.summary(f) }
    static func fame(_ f: AdvancedFilter) -> Text? {
        switch f.fame { case .any: nil; case .gems: Text("Joyas ocultas"); case .classics: Text("Las de siempre"); case .niche: Text("Para pocos"); case .blockbusters: Text("Taquilleras") }
    }
    static func places(_ f: AdvancedFilter, platforms: [AdvancedFilterModel.Platform]) -> Text? {
        guard !f.providers.isEmpty else { return nil }
        let names = platforms.filter { f.providers.contains($0.id) }.map(\.name)
        return names.isEmpty ? Text("Tus plataformas") : Text(verbatim: names.joined(separator: ", "))
    }
    static func countries(_ f: AdvancedFilter) -> Text? {
        f.countries.isEmpty ? nil : Text(verbatim: FilterCatalog.countries.filter { f.countries.contains($0.code) }.map(\.name).joined(separator: ", "))
    }
    static func awards(_ f: AdvancedFilter) -> Text? {
        let picked = FilterCatalog.awards.filter { f.awards.contains($0) }
        guard let first = picked.first else { return nil }
        return picked.dropFirst().reduce(AwardNames.title(first)) { Text("\($0), \(AwardNames.title($1))") }
    }
    static func studios(_ f: AdvancedFilter) -> Text? {
        f.studios.isEmpty ? nil : Text(verbatim: Tmdb.studios.filter { f.studios.contains($0.id) }.map(\.name).joined(separator: ", "))
    }

    static func value(_ page: FilterPage, _ c: FilterContext) -> Text? {
        switch page {
        case .genre: genres(c.filter); case .era: years(c.filter); case .length: length(c.filter, language: c.language)
        case .rating: rating(c.filter); case .fame: fame(c.filter); case .place: places(c.filter, platforms: c.platforms)
        case .origin: countries(c.filter); case .awards: awards(c.filter); case .studio: studios(c.filter)
        }
    }

    /// «7.5» con un decimal.
    static func number(_ value: Double) -> String { String(format: "%.1f", value) }

    /// La hora de «Que acabe antes de las…» (23.5 → «11:30 p. m.»).
    static func clock(_ hour: Double, language: String) -> String {
        let minutes = Int((hour * 60).rounded()) % (24 * 60)
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return Strings.clock(date, language: language)
    }
}

/// El dibujo de un filtro arriba de su mosaico: lo que elegiste, en chiquito (la regla con su ventana, los logos, el cuadro
/// con su esquina). Sin nada elegido, el ícono del filtro en gris.
struct FilterArt: View {
    let page: FilterPage
    let context: FilterContext
    var mini = false

    var body: some View {
        let f = context.filter
        let height = mini ? DS.Filter.miniArtHeight : DS.Filter.artHeight
        let symbolFont = mini ? DS.TextRecipe.secondary.font : DS.TextRecipe.title.font
        Group {
            switch page {
            case .era where f.years != nil || f.spread:
                MiniRuler(years: f.years ?? AdvancedFilter.firstYear...f.currentYear, last: f.currentYear)
            case .rating where f.minRating != nil || f.minLetterboxd != nil:
                // El número manda (en el verde de Calificación); el logo de TMDB, chico, dice de dónde sale.
                // Centrado, como los demás: la estrella y el número; de dónde sale lo dice el renglón de abajo («o más» y el logo de TMDB).
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                    Image(systemName: "star.fill").font(mini ? DS.TextRecipe.caption.font : DS.TextRecipe.footnote.font).foregroundStyle(page.hue)
                    Text(verbatim: FilterText.number(f.minRating ?? f.minLetterboxd ?? 0)).font((mini ? DS.TextRecipe.secondary : DS.TextRecipe.title).font.weight(.bold)).monospacedDigit().foregroundStyle(page.hue)
                }
            case .fame where f.fame != .any:
                // Con una elegida, el cuadro chiquito con su esquina; sin nada, su ícono de línea como los demás (antes, cuatro
                // cuadros grises; Fernando, 2 nov 2026, K3).
                MiniQuadrant(selected: f.fame)
            case .place where !f.providers.isEmpty:
                HStack(spacing: DS.Space.s1) {
                    ForEach(context.platforms.filter { f.providers.contains($0.id) }.prefix(3)) { DSPlatformLogo(url: $0.logo) }
                }
            case .origin where !f.countries.isEmpty:
                Text(verbatim: f.countries.sorted().prefix(4).map(FilterCatalog.flag).joined(separator: " ")).font(symbolFont)
            case .awards where !f.awards.isEmpty:
                HStack(spacing: DS.Space.s1) {
                    ForEach(FilterCatalog.awards.filter { f.awards.contains($0) }.prefix(4), id: \.self) { id in
                        Image("Awards/" + id).resizable().scaledToFit()
                    }
                }
            case .studio where !f.studios.isEmpty:
                HStack(spacing: DS.Space.s2) {
                    ForEach(Tmdb.studios.filter { f.studios.contains($0.id) }.prefix(2), id: \.id) { s in
                        StudioLogo(id: s.id, name: s.name)
                    }
                }
            case .length where f.length != .any:
                Image(systemName: f.length == .short ? "hare" : f.length == .long ? "tortoise" : f.length == .before ? "moon.zzz" : "clock")
                    .font(symbolFont).foregroundStyle(page.hue)
            default:
                Image(systemName: page.symbol).font(symbolFont).foregroundStyle(page.hue)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// Un filtro como mosaico: su dibujo arriba, el nombre y lo elegido. Con algo elegido, borde blanco (lo elegido siempre en
/// blanco); abierto, borde más grueso y fondo más claro. Género lleva de fondo el arte de los géneros elegidos. `mini`: la
/// versión chica de la puerta de Buscar.
struct FilterTile: View {
    let page: FilterPage
    let context: FilterContext
    var mini = false
    var open = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sin ningún filtro puesto, los mosaicos van sin renglón de valor y más bajos (Fernando, 2 nov 2026, K5: seis
    /// «Cualquiera» iguales no decían nada). Con uno puesto, todos crecen juntos (el renglón parejo) y solo el puesto dice su
    /// valor; los demás no repiten «Cualquiera».
    static func compact(_ context: FilterContext) -> Bool { FilterPage.allCases.allSatisfy { FilterText.value($0, context) == nil } }

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        let value = FilterText.value(page, context)
        let on = value != nil
        let compact = Self.compact(context)
        let shape = RoundedRectangle(cornerRadius: mini ? DS.Radius.md : DS.Radius.lg, style: .continuous)
        let art = page == .genre ? Tmdb.filterGenres.filter { context.filter.genres.contains($0.slug) }.prefix(DS.Filter.genreMosaicMax).map { FilterCatalog.genreImage($0.slug) } : []
        Button(action: action) {
            // Centrado (Fernando, 31 oct 2026): el dibujo, el nombre y lo elegido al centro del mosaico.
            VStack(spacing: mini ? DS.Space.s1 / 2 : DS.Space.s1) {
                if art.isEmpty { FilterArt(page: page, context: context, mini: mini) } else { Spacer(minLength: 0) }
                // Sobre el arte de los géneros el texto va en papel (se lee igual en claro y en oscuro).
                page.title.recipe(mini ? .badge : .label, color: art.isEmpty ? DS.text : DS.paper).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                if page == .rating, value != nil {
                    // De dónde sale el número de arriba (el logo de TMDB o el de Letterboxd) y, con las dos, las estrellas.
                    let f = context.filter, stars = f.format == .series ? nil : f.minLetterboxd
                    HStack(spacing: DS.Space.s1) {
                        if f.minRating != nil {
                            Image("rating-tmdb").resizable().scaledToFit().frame(height: DS.Filter.tmdbMark).accessibilityLabel(Text(verbatim: "TMDB"))
                        } else { LetterboxdMark() }
                        if f.minRating != nil, let stars { Text(verbatim: "· ★" + RatingLevels.short(stars)).recipe(.caption, color: DS.Letterboxd.leaf).monospacedDigit() } else { Text("o más").recipe(.caption, color: DS.text) }
                    }
                } else if let value {
                    value.recipe(.caption, color: !art.isEmpty ? DS.paper : DS.text).lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: DS.Motion.leaveScale, anchor: .top)))
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, mini ? DS.Space.s2 : DS.Space.s3)
            .padding(.vertical, mini ? DS.Space.s2 : DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: compact ? (mini ? DS.Filter.miniTileCompact : DS.Filter.tileCompact) : (mini ? DS.Filter.miniTileHeight : DS.Filter.tileHeight))
            .background {
                ZStack {
                    open || mini ? DS.surfaceRaised : DS.surface
                    if !art.isEmpty {
                        GenreMosaic(images: art)
                        ArtVeil(strength: .deep)
                    }
                }
                .animation(DS.Motion.fade, value: art)
            }
            .clipShape(shape)
            .dsSelectionRing(on || open, in: shape)
            .overlay(alignment: .topTrailing) {
                if on { Circle().fill(page.hue).frame(width: DS.Filter.dot, height: DS.Filter.dot).padding(mini ? DS.Space.s2 : DS.Space.s3).accessibilityHidden(true) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityValue(value ?? Text("Cualquiera"))   // VoiceOver sí lo dice: lo que se quitó es solo lo que se ve
        // El valor entra con el resorte de la app y el mosaico crece suave (sin movimiento con Reducir movimiento).
        .animation(DS.Motion.smooth(reduceMotion) ?? DS.Motion.fade, value: on)
        .animation(DS.Motion.smooth(reduceMotion), value: compact)
    }
}

/// Los géneros elegidos como mosaico de fondo (hasta seis): uno solo llena el mosaico; dos o tres, en columnas; de cuatro a
/// seis, en dos renglones (el de arriba con uno menos si son impares, como un mosaico y no una fila apilada).
struct GenreMosaic: View {
    let images: [String]
    var body: some View {
        let rows: [[String]] = images.count <= 3 ? [images] : [Array(images.prefix(images.count / 2)), Array(images.dropFirst(images.count / 2))]
        VStack(spacing: DS.Stroke.regular) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: DS.Stroke.regular) {
                    ForEach(row, id: \.self) { name in
                        Color.clear.overlay { Image(name).resizable().scaledToFill() }.clipped()
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// La regla chiquita del mosaico de Época: una rayita por década y la ventana con lo elegido.
struct MiniRuler: View {
    let years: ClosedRange<Int>
    let last: Int

    var body: some View {
        GeometryReader { geo in
            let first = AdvancedFilter.firstYear
            let span = CGFloat(max(last - first, 1))
            let x = { (y: Int) in CGFloat(min(max(y, first), last) - first) / span * geo.size.width }
            let windowWidth = max(x(years.upperBound + 1) - x(years.lowerBound), DS.Filter.miniWindow)
            ZStack(alignment: .leading) {
                ForEach(Array(stride(from: first, through: last, by: 10)), id: \.self) { d in
                    Rectangle().fill(DS.Filter.tickMid).frame(width: DS.Stroke.regular, height: geo.size.height / 2).offset(x: x(d))
                }
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(DS.Filter.amberFill)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).strokeBorder(DS.Filter.amber, lineWidth: DS.Stroke.selected))
                    // Siempre visible y dentro de la regla (los años muy recientes, como Estrenos, quedaban fuera de la orilla).
                    .frame(width: windowWidth, height: geo.size.height)
                    .offset(x: min(x(years.lowerBound), geo.size.width - windowWidth))
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// El logo real de un estudio, a color (viene con la app, `Assets/Studios`, sacado de TMDB), sobre una plaquita de papel para
/// que se lea igual el negro de A24 que el rojo de Marvel. Sin logo, su nombre.
struct StudioLogo: View {
    let id: Int
    let name: String

    var body: some View {
        Group {
            if UIImage(named: "studio-\(id)") != nil {
                Image("studio-\(id)").renderingMode(.original).resizable().scaledToFit()
                    .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
                    .background(DS.paper, in: RoundedRectangle(cornerRadius: DS.Radius.tag, style: .continuous))   // ds-exception: la plaquita de papel fijo hace que el logo a color se lea igual en los dos modos
            } else {
                Text(verbatim: name).recipe(.badge, color: DS.text).lineLimit(1)
            }
        }
        .frame(maxHeight: DS.Filter.studioLogoHeight)
        .accessibilityLabel(Text(verbatim: name))
    }
}

/// El panel de un filtro abierto, bajo el renglón de su mosaico, con una flechita hacia él (`notch`: 0 a la izquierda, 1
/// a la derecha; 0.25 y 0.75 son las dos columnas).
struct FilterPanel<Content: View>: View {
    var notch: CGFloat = 0.25
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) { content() }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surfaceRaised, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))   // ds-exception: el panel y su flechita van en la superficie elevada (dsCard no tiene ese nivel)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous).fill(DS.surfaceRaised)
                        .frame(width: DS.Filter.notch, height: DS.Filter.notch)
                        .rotationEffect(.degrees(45))
                        .offset(x: geo.size.width * notch - DS.Filter.notch / 2, y: -DS.Filter.notch / 2)
                }
                .frame(height: DS.Filter.notch)
                .accessibilityHidden(true)
            }
    }
}

/// La puerta del filtro avanzado arriba de Buscar (Fernando, 31 oct 2026, entrada A «El cajón asoma»): su nombre, cuántos
/// filtros llevas y cuántos títulos encontró la última vez, y los seis mosaicos del cajón en chiquito. Tocar un mosaico abre
/// el cajón con ese filtro abierto; tocar arriba, el cajón sin nada abierto.
struct FilterDoor: View {
    let context: FilterContext
    /// Cuántos títulos encontró la última búsqueda con este filtro, por tipo (nil: aún no se busca).
    let count: FilterCount?
    /// nil: el cajón sin nada abierto; si no, el filtro tocado.
    let open: (FilterPage?) -> Void
    /// «Limpiar»: quita todos los filtros desde aquí, sin abrir el cajón.
    var clear: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            // La flechita va pegada al título («Búsqueda avanzada ›») y la X sola a la derecha, lejos de ella (Fernando, 31 oct
            // 2026: juntas parecían un mismo botón).
            HStack(alignment: .center, spacing: DS.Space.s5) {
                Button { open(nil) } label: {
                    HStack(spacing: DS.Space.s3) {
                        // Su propio ícono en un círculo: se distingue de un vistazo del campo de arriba, que busca por nombre.
                        Image(systemName: "slider.horizontal.3").font(DS.TextRecipe.labelLarge.font).foregroundStyle(DS.text)
                            .frame(width: DS.Filter.doorIcon, height: DS.Filter.doorIcon)
                            .background(DS.fillStrong, in: Circle())
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            HStack(spacing: DS.Space.s1) {
                                Text("Búsqueda avanzada").recipe(.cardTitle)
                                Image(systemName: "chevron.forward").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted)
                            }
                            subtitle.recipe(.footnote, color: context.filter.isEmpty ? DS.textMuted : DS.text).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("browse-filters")
                if !context.filter.isEmpty {
                    DSIconButton(symbol: "xmark", label: "Limpiar la búsqueda avanzada", size: .regular, action: clear)
                        .accessibilityIdentifier("browse-filters-clear")
                }
            }
            // Dos columnas con letra de accesibilidad: en tres el dibujo se encimaba con el nombre («Cu…»).
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: DS.Space.s2) {
                ForEach(FilterPage.main) { page in
                    FilterTile(page: page, context: context, mini: true) { open(page) }
                        .accessibilityIdentifier("browse-filter-\(page.rawValue)")
                }
            }
        }
        .padding(DS.Space.s3)
        // La tarjeta de siempre: el turquesa no decora orillas ni fondos (Fernando, 2 nov 2026: «la voz de Orbital»; antes
        // teñida de azul y con orilla).
        .dsCard(.card)
    }

    private var subtitle: Text {
        let n = context.filter.activeCount
        guard n > 0 else { return Text("Sin escribir nombres: encuentra por género, época, calificación, premios y más") }
        let filters = n == 1 ? Text("1 filtro") : Text("\(n) filtros")
        guard let count else { return filters }
        return Text("\(filters) · \(ResultCountHeader.phrase(count, language: context.language)) la última vez")
    }
}

/// Cuántos trae una búsqueda (opción A, Fernando 2 nov 2026): la cifra grande con «títulos» y, si hay de los dos, cuántas
/// películas y cuántas series con su ícono. El número es el de TMDB: si se quitan las que ya viste, se dice que es de antes.
struct ResultCountHeader: View {
    let count: FilterCount
    /// «Sin vistas» puesto: el número es de antes de quitarlas.
    var beforeWatched = false
    let language: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: Strings.count(count.total, language: language)).recipe(.stat).contentTransition(.numericText())
                (count.total == 1 ? Text("título") : Text("títulos")).recipe(.labelLarge, color: DS.textMuted)
            }
            if count.movies > 0, count.series > 0 {
                HStack(spacing: DS.Space.s4) {
                    part("movie", count.movies)
                    part("series", count.series)
                }
            }
            if beforeWatched { Text("Antes de quitar las que ya viste").recipe(.caption, color: DS.textMuted) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("filter-total")
    }

    /// «🎬 860 películas»: la cifra en blanco, la palabra en gris.
    private func part(_ kind: String, _ n: Int) -> some View {
        let number = Text(verbatim: Strings.count(n, language: language)).foregroundStyle(DS.text)
        let title: Text = switch (kind, n) {
        case ("movie", 1): Text("\(number) película")
        case ("movie", _): Text("\(number) películas")
        case (_, 1): Text("\(number) serie")
        default: Text("\(number) series")
        }
        return Label { title } icon: { Image(systemName: KindGlyph.symbol(kind)) }.recipe(.label, color: DS.textMuted).monospacedDigit()
    }

    /// En una línea, para la puerta de Buscar: «860 películas y 380 series», «12 películas», «1 serie».
    static func phrase(_ count: FilterCount, language: String) -> String {
        func n(_ v: Int) -> String { Strings.count(v, language: language) }
        func tr(_ key: String, _ v: Int) -> String { String(format: Strings.tr(key, language: language), n(v)) }
        let movies = count.movies == 1 ? tr("%@ película", 1) : tr("%@ películas", count.movies)
        let series = count.series == 1 ? tr("%@ serie", 1) : tr("%@ series", count.series)
        switch (count.movies > 0, count.series > 0) {
        case (true, true): return String(format: Strings.tr("%@ y %@", language: language), movies, series)
        case (true, false): return movies
        case (false, true): return series
        case (false, false): return tr("%@ títulos", 0)
        }
    }
}

/// Un filtro puesto, arriba de los resultados: su ícono y lo elegido en un cuadrito. Tocarlo abre el cajón en ese filtro;
/// mantenerlo presionado lo quita. Sin `remove`, el cuadrito «＋ Filtro».
struct FilterSummarySquare: View {
    let symbol: String
    let title: Text
    /// El color del filtro (su ícono).
    var hue: Color = DS.text
    let edit: () -> Void
    var remove: (() -> Void)?

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        let shape = RoundedRectangle(cornerRadius: DSCardLevel.row.radius, style: .continuous)
        Button(action: edit) {
            VStack(spacing: DS.Space.s1) {
                Image(systemName: symbol).font(DS.TextRecipe.secondary.font).foregroundStyle(remove == nil ? DS.textMuted : hue)
                title.recipe(.badge, color: remove == nil ? DS.textMuted : DS.text).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            }
            .padding(.horizontal, DS.Space.s1)
            .frame(width: DS.Filter.summarySquare, height: DS.Filter.summarySquare)
            .dsCard(fill: remove == nil ? .clear : DS.surfaceRaised)
            .overlay(shape.strokeBorder(remove == nil ? DS.hairline : DS.fillStrong, lineWidth: DS.Stroke.regular))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let remove { Button("Quitar", systemImage: "xmark", role: .destructive, action: remove) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if let remove { Button("Quitar", action: remove) }
        }
    }
}

/// Una opción grande con ícono (Cortita · Normal · Para echarse, Estrenos, Joyas ocultas…): se enciende al elegirla.
struct FilterChoice: View {
    let symbol: String
    let title: Text
    var detail: Text?
    /// El color del filtro al que pertenece (su ícono).
    var hue: Color = DS.text
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s2) {
                Image(systemName: symbol).font(DS.TextRecipe.title.font).foregroundStyle(hue)
                title.recipe(.label, color: DS.text).lineLimit(1)
                if let detail { detail.recipe(.caption, color: DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale) }
            }
            .padding(.horizontal, DS.Space.s2)
            .padding(.vertical, DS.Space.s3)   // aire parejo arriba y abajo (el detalle ya no toca la orilla)
            .frame(maxWidth: .infinity, minHeight: DS.Filter.choiceHeight)
            .dsCard(fill: selected ? DS.Filter.selectedFill : nil)
            .dsSelectionRing(selected, radius: DS.Radius.lg)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Un logo o un ícono que se elige (una plataforma, un premio, un estudio, un país): el dibujo arriba y el nombre abajo.
struct FilterLogoChoice<Logo: View>: View {
    let title: Text
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let logo: () -> Logo

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DSCardLevel.row.radius, style: .continuous)
        Button(action: action) {
            VStack(spacing: DS.Space.s1) {
                logo().frame(height: DS.Filter.awardIcon)
                title.recipe(.badge, color: selected ? DS.text : DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            }
            .padding(.horizontal, DS.Space.s2)
            .padding(.vertical, DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: DS.Filter.logoTile)
            .dsCard(fill: selected ? DS.Filter.selectedFill : nil)
            .dsSelectionRing(selected, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
