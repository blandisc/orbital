import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas del filtro avanzado (la entrada A de Fernando, 31 oct 2026; maqueta en
// docs/producto/muvy-busqueda-premios/filtro-a.html): el mosaico de cada filtro con su dibujo (el mismo en la puerta de
// Buscar y en el cajón), el panel que se abre bajo su mosaico, el cuadro «Qué tan conocida», la opción grande con ícono y
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
        case .fame: Text("Qué tan conocida"); case .place: Text("Dónde verla"); case .origin: Text("Origen")
        case .awards: Text("Premios"); case .studio: Text("Estudios")
        }
    }

    /// Su color (solo en detalles). Dónde verla lleva el azul de Orbital; Estudios, blanco: el color lo ponen sus logos.
    var hue: Color {
        switch self {
        case .genre: DS.Filter.coral; case .era, .awards: DS.Filter.gold; case .length: DS.Filter.lilac; case .rating: DS.Filter.mint
        case .fame: DS.Filter.rose; case .place: DS.orbitalBlue; case .origin: DS.Filter.sky; case .studio: DS.text
        }
    }

    var symbol: String {
        switch self {
        case .genre: "theatermasks"; case .era: "calendar"; case .length: "clock"; case .rating: "star"; case .fame: "sparkles"
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
    static let genreArt = ["accion": "action", "aventura": "action", "animacion": "animation", "comedia": "comedy", "crimen": "crime",
                           "documental": "documentary", "drama": "drama", "familia": "animation", "fantasia": "fantasy", "terror": "horror",
                           "misterio": "mystery", "romance": "romance", "ciencia-ficcion": "scifi", "suspenso": "thriller"]
    static func genreImage(_ slug: String) -> String { "decide-genre-\(genreArt[slug] ?? "drama")" }
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
        let yes = Tmdb.genres.filter { f.genres.contains($0.slug) }.map(\.title)
        let no = Tmdb.genres.filter { f.excluded.contains($0.slug) }.map(\.title)
        if yes.isEmpty && no.isEmpty { return nil }
        if yes.isEmpty { return Text("Sin \(no.joined(separator: ", "))") }
        return Text(verbatim: yes.joined(separator: ", "))
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
    static func rating(_ f: AdvancedFilter) -> Text? { f.minRating.map { Text("\(number($0)) o más") } }
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
            case .rating where f.minRating != nil:
                // El número manda (en el verde de Calificación); el logo de TMDB, chico, dice de dónde sale.
                // Centrado, como los demás: la estrella y el número; de dónde sale lo dice el renglón de abajo («o más» y el logo de TMDB).
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                    Image(systemName: "star.fill").font(mini ? DS.TextRecipe.caption.font : DS.TextRecipe.footnote.font).foregroundStyle(page.hue)
                    Text(verbatim: FilterText.number(f.minRating ?? 0)).font((mini ? DS.TextRecipe.secondary : DS.TextRecipe.title).font.weight(.bold)).monospacedDigit().foregroundStyle(page.hue)
                }
            case .fame:
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

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        let value = FilterText.value(page, context)
        let on = value != nil
        let shape = RoundedRectangle(cornerRadius: mini ? DS.Radius.md : DS.Radius.lg, style: .continuous)
        let art = page == .genre ? Tmdb.genres.filter { context.filter.genres.contains($0.slug) }.prefix(DS.Filter.genreMosaicMax).map { FilterCatalog.genreImage($0.slug) } : []
        Button(action: action) {
            // Centrado (Fernando, 31 oct 2026): el dibujo, el nombre y lo elegido al centro del mosaico.
            VStack(spacing: mini ? DS.Space.s1 / 2 : DS.Space.s1) {
                if art.isEmpty { FilterArt(page: page, context: context, mini: mini) } else { Spacer(minLength: 0) }
                // Sobre el arte de los géneros el texto va en papel (se lee igual en claro y en oscuro).
                page.title.recipe(mini ? .caption : .footnote, color: art.isEmpty ? DS.text : DS.paper).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                if page == .rating, value != nil {
                    // «o más» y el logo de TMDB (de dónde sale la calificación), en vez de la palabra.
                    HStack(spacing: DS.Space.s1) {
                        Text("o más").recipe(.caption, color: DS.text)
                        Image("rating-tmdb").resizable().scaledToFit().frame(height: DS.Filter.tmdbMark).accessibilityLabel(Text(verbatim: "TMDB"))
                    }
                } else {
                    tileValue(value).recipe(.caption, color: !art.isEmpty ? DS.paper : on ? DS.text : DS.textMuted).lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, mini ? DS.Space.s2 : DS.Space.s3)
            .padding(.vertical, mini ? DS.Space.s2 : DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: mini ? DS.Filter.miniTileHeight : DS.Filter.tileHeight)
            .background {
                ZStack {
                    open || mini ? DS.surfaceRaised : DS.surface
                    if !art.isEmpty {
                        GenreMosaic(images: art)
                        ArtVeil(strength: .deep)
                    }
                }
                .animation(DS.Motion.base(false), value: art)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(on || open ? DS.text : .clear, lineWidth: open ? DS.Size.hairline * 4 : DS.Size.hairline * 2))
            .overlay(alignment: .topTrailing) {
                if on { Circle().fill(page.hue).frame(width: DS.Filter.dot, height: DS.Filter.dot).padding(mini ? DS.Space.s2 : DS.Space.s3).accessibilityHidden(true) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Lo que dice el renglón de abajo (nil: cualquiera).
    private func tileValue(_ value: Text?) -> Text { value ?? Text("Cualquiera") }
}

/// Los géneros elegidos como mosaico de fondo (hasta seis): uno solo llena el mosaico; dos o tres, en columnas; de cuatro a
/// seis, en dos renglones (el de arriba con uno menos si son impares, como un mosaico y no una fila apilada).
struct GenreMosaic: View {
    let images: [String]
    var body: some View {
        let rows: [[String]] = images.count <= 3 ? [images] : [Array(images.prefix(images.count / 2)), Array(images.dropFirst(images.count / 2))]
        VStack(spacing: DS.Size.hairline * 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: DS.Size.hairline * 2) {
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
                    Rectangle().fill(DS.Filter.tickMid).frame(width: DS.Size.hairline * 2, height: geo.size.height / 2).offset(x: x(d))
                }
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(DS.Filter.goldFill)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).strokeBorder(DS.Filter.gold, lineWidth: DS.Size.hairline * 3))
                    // Siempre visible y dentro de la regla (los años muy recientes, como Estrenos, quedaban fuera de la orilla).
                    .frame(width: windowWidth, height: geo.size.height)
                    .offset(x: min(x(years.lowerBound), geo.size.width - windowWidth))
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// El cuadro chiquito de «Qué tan conocida»: cuatro esquinas, la elegida en blanco.
struct MiniQuadrant: View {
    let selected: AdvancedFilter.Fame
    var body: some View {
        Grid(horizontalSpacing: DS.Size.hairline * 4, verticalSpacing: DS.Size.hairline * 4) {
            GridRow { cell(.gems); cell(.classics) }
            GridRow { cell(.niche); cell(.blockbusters) }
        }
        .aspectRatio(DS.Poster.aspect * 2, contentMode: .fit)
    }
    private func cell(_ fame: AdvancedFilter.Fame) -> some View {
        RoundedRectangle(cornerRadius: DS.Size.hairline * 6, style: .continuous).fill(selected == fame ? DS.Filter.rose : DS.fillStrong)
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
                    .background(DS.paper, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            } else {
                Text(verbatim: name).recipe(.caption, color: DS.text).fontWeight(.bold).lineLimit(1)
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
            .background(DS.surfaceRaised, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: DS.Size.hairline * 6, style: .continuous).fill(DS.surfaceRaised)
                        .frame(width: DS.Filter.notch, height: DS.Filter.notch)
                        .rotationEffect(.degrees(45))
                        .offset(x: geo.size.width * notch - DS.Filter.notch / 2, y: -DS.Filter.notch / 2)
                }
                .frame(height: DS.Filter.notch)
                .accessibilityHidden(true)
            }
    }
}

/// «Ver más filtros»: una fila con los íconos de Origen, Premios y Estudios en su color y cuántos tienen algo; al abrirla dice
/// «Menos filtros». Es parte del cajón, no un enlace suelto.
struct FilterMoreRow: View {
    let expanded: Bool
    /// Cuántos de los de «Ver más» tienen algo puesto.
    let active: Int
    let toggle: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        Button(action: toggle) {
            HStack(spacing: DS.Space.s3) {
                HStack(spacing: -DS.Space.s1) {
                    ForEach(FilterPage.more) { page in
                        Image(systemName: page.symbol).font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(page.hue)
                            .frame(width: DS.Filter.moreIcon, height: DS.Filter.moreIcon)
                            .background(DS.surfaceRaised, in: Circle())
                            .overlay(Circle().strokeBorder(DS.surface, lineWidth: DS.Size.hairline * 3))
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    (expanded ? Text("Menos filtros") : Text("Más filtros")).recipe(.footnote, color: DS.text).fontWeight(.semibold)
                    (active > 0 ? Text("\(active) con algo puesto") : Text("Origen, premios y estudios")).recipe(.caption, color: DS.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: DS.Filter.moreRow)
            .background(DS.surface, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointerHover(.highlight)
        .accessibilityLabel(expanded ? Text("Menos filtros") : Text("Más filtros: origen, premios y estudios"))
    }
}

/// La puerta del filtro avanzado arriba de Buscar (Fernando, 31 oct 2026, entrada A «El cajón asoma»): su nombre, cuántos
/// filtros llevas y cuántos títulos encontró la última vez, y los seis mosaicos del cajón en chiquito. Tocar un mosaico abre
/// el cajón con ese filtro abierto; tocar arriba, el cajón sin nada abierto.
struct FilterDoor: View {
    let context: FilterContext
    /// Cuántos títulos encontró la última búsqueda con este filtro (nil: aún no se busca).
    let total: Int?
    /// nil: el cajón sin nada abierto; si no, el filtro tocado.
    let open: (FilterPage?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Button { open(nil) } label: {
                HStack(spacing: DS.Space.s2) {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Label { Text("Búsqueda avanzada").recipe(.cardTitle) } icon: {
                            Image(systemName: "slider.horizontal.3").font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.orbitalBlue)
                        }
                        subtitle.recipe(.footnote, color: context.filter.isEmpty ? DS.textMuted : DS.text).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("browse-filters")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 3), spacing: DS.Space.s2) {
                ForEach(FilterPage.main) { page in
                    FilterTile(page: page, context: context, mini: true) { open(page) }
                        .accessibilityIdentifier("browse-filter-\(page.rawValue)")
                }
            }
        }
        .padding(DS.Space.s3)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }

    private var subtitle: Text {
        let n = context.filter.activeCount
        guard n > 0 else { return Text("Género, época, calificación, premios y más") }
        let filters = n == 1 ? Text("1 filtro") : Text("\(n) filtros")
        guard let total else { return filters }
        return Text("\(filters) · \(Strings.count(total, language: context.language)) títulos la última vez")
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
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        Button(action: edit) {
            VStack(spacing: DS.Space.s1) {
                Image(systemName: symbol).font(DS.TextRecipe.secondary.font).foregroundStyle(remove == nil ? DS.textMuted : hue)
                title.recipe(.caption, color: remove == nil ? DS.textMuted : DS.text).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            }
            .padding(.horizontal, DS.Space.s1)
            .frame(width: DS.Filter.summarySquare, height: DS.Filter.summarySquare)
            .background(remove == nil ? .clear : DS.surfaceRaised, in: shape)
            .overlay(shape.strokeBorder(remove == nil ? DS.hairline : DS.fillStrong, lineWidth: DS.Size.hairline * 2))
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
                title.recipe(.footnote, color: DS.text).fontWeight(.semibold).lineLimit(1)
                if let detail { detail.recipe(.caption, color: DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale) }
            }
            .padding(.horizontal, DS.Space.s2)
            .padding(.vertical, DS.Space.s3)   // aire parejo arriba y abajo (el detalle ya no toca la orilla)
            .frame(maxWidth: .infinity, minHeight: DS.Filter.choiceHeight)
            .background(selected ? DS.Filter.selectedFill : DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).strokeBorder(selected ? DS.text : .clear, lineWidth: DS.Size.hairline * 2))
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
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        Button(action: action) {
            VStack(spacing: DS.Space.s1) {
                logo().frame(height: DS.Filter.awardIcon)
                title.recipe(.caption, color: selected ? DS.text : DS.textMuted).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            }
            .padding(.horizontal, DS.Space.s2)
            .padding(.vertical, DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: DS.Filter.logoTile)
            .background(selected ? DS.Filter.selectedFill : DS.surface, in: shape)
            .overlay(shape.strokeBorder(selected ? DS.text : .clear, lineWidth: DS.Size.hairline * 2))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
