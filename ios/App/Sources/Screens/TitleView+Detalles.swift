import SwiftUI
import OrbitalCore
import OrbitalModels

/// La ficha: sinopsis, créditos, detalles y lo de TMDB (reparto, tráileres, parecidas). Aparte de TitleView para que ninguno pase de su tope.
extension TitleView {
    /// La sinopsis en tres renglones y «más» para leerla completa.
    @ViewBuilder func synopsis(_ model: TitleModel) -> some View {
        if model.overview.isEmpty, model.isLoading {
            // Esqueleto: el lugar de la sinopsis mientras llega (antes la ficha se veía vacía la primera vez).
            Text(verbatim: String(repeating: "placeholder ", count: 24)).recipe(.secondary).lineLimit(DS.TitleAction.synopsisLines)
                .redacted(reason: .placeholder).accessibilityHidden(true)
        } else if !model.overview.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(model.overview).recipe(.secondary, color: DS.text).lineLimit(fullSynopsis ? nil : DS.TitleAction.synopsisLines)
                if model.overview.count > DS.Size.synopsisFold {
                    Button(fullSynopsis ? "menos" : "más") { withAnimation(DS.Motion.base(reduceMotion)) { fullSynopsis.toggle() } }
                        .font(DS.TextRecipe.label.font).foregroundStyle(artAccent).buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Como los créditos del cine, en una línea: «Dirección Denis Villeneuve · Guion Jon Spaihts» y «Con …».
    @ViewBuilder func creditLine(_ model: TitleModel) -> some View {
        let crew = model.extras?.crew ?? []
        let directors = crew.filter { $0.role == "Director" || $0.role == "Creator" }.map(\.name)
        let writers = crew.filter { $0.role == "Screenplay" || $0.role == "Writer" }.map(\.name)
        let leads = (model.extras?.cast.prefix(3).map(\.name)) ?? Array(model.credits.cast.prefix(3))
        let lead = directors.isEmpty ? model.credits.directors : directors
        if !lead.isEmpty || !leads.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if !lead.isEmpty {
                    let who = model.kind == "series" ? Text("Creada por") : Text("Dirección")
                    let line = Text("\(who.foregroundStyle(DS.textFaint))\(Text(verbatim: " " + lead.prefix(2).joined(separator: ", ")).foregroundStyle(DS.text))")
                    if let writer = writers.first, model.kind == "movie" {
                        Text("\(line)\(Text(verbatim: " · ").foregroundStyle(DS.textFaint))\(Text("Guion").foregroundStyle(DS.textFaint))\(Text(verbatim: " " + writer).foregroundStyle(DS.text))")
                    } else { line }
                }
                if !leads.isEmpty {
                    Text("\(Text("Con").foregroundStyle(DS.textFaint))\(Text(verbatim: " " + leads.joined(separator: ", ")).foregroundStyle(DS.text))")
                }
            }
            .font(DS.TextRecipe.footnote.font)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Al final, los datos de referencia: estreno, duración, idiomas, lo disponible, clasificación y estudio.
    @ViewBuilder func details(_ model: TitleModel) -> some View {
        let rows = detailRows(model)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                DSSectionHead(title: "Detalles", eyebrow: Text("Los datos de la ficha"))
                Grid(alignment: .leading, horizontalSpacing: DS.Space.s4, verticalSpacing: DS.Space.s2) {
                    ForEach(rows, id: \.0) { label, value in
                        GridRow {
                            Text(LocalizedStringKey(label)).recipe(.footnote, color: DS.textFaint)
                            Text.withFlagImages(value).recipe(.footnote, color: DS.text)
                        }
                    }
                }
            }
        }
    }

    private static let day: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()   // ds-exception: lee fechas de TMDB, no escribe texto

    func detailRows(_ model: TitleModel) -> [(String, String)] {
        let locale = env.uiLocale
        var rows: [(String, String)] = []
        if let raw = model.extras?.releaseDate, let date = Self.day.date(from: raw) {
            rows.append((model.kind == "series" ? "Primer episodio" : "Estreno", date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale))))
        }
        if !model.info.runtime.isEmpty { rows.append(("Duración", model.info.runtime)) }
        let languages = (model.extras?.languages ?? []).compactMap { code in (locale.localizedString(forLanguageCode: code)?.capitalized(with: locale)).map { LanguageFlags.flagged($0, code) } }
        if !languages.isEmpty { rows.append(("Idiomas", languages.prefix(4).joined(separator: ", "))) }
        if let best = model.bestSource {
            let items = QualityBadges.items(resolution: best.resolution, hdr: best.hdr, audio: best.audioBadges)
            if !items.isEmpty { rows.append(("Disponible", items.joined(separator: " · "))) }
        }
        if let rating = model.extras?.certification { rows.append(("Clasificación", rating)) }
        if let studios = model.extras?.studios, !studios.isEmpty { rows.append((model.kind == "series" ? "Cadena" : "Estudio", studios.map(\.name).joined(separator: ", "))) }
        return rows
    }

    /// Lo de TMDB, como Infuse: tráiler y extras, reparto con cara (toca para ver su trabajo), la saga y
    /// «Más como esto». Cada sección con el encabezado de toda la app; las tiras van de borde a borde.
    /// `trailers`, `people`, `similar`: qué partes van (en el iPad cada una vive en su pestaña).
    /// `headed: false`: sin el rótulo de la sección (la pestaña ya lo dice).
    @ViewBuilder func rich(_ x: TitleExtras, trailers: Bool = true, people showPeople: Bool = true, similar: Bool = true, headed: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: DS.Layout.betweenSections) {
            if trailers, let trailer = x.trailer {
                section(title: "Tráiler y extras", meta: Text("Para verla antes de verla")) {
                    VideoClipCard(clip: trailer)
                    ForEach(x.extras) { VideoClipCard(clip: $0) }
                }
            }
            let people = x.crew + x.cast
            if showPeople, !people.isEmpty {
                section(title: "Reparto y equipo", meta: Text("Quién sale y quién la hizo"), headed: headed) {
                    ForEach(people) { p in
                        NavigationLink(value: PersonRoute(id: p.personID, name: p.name)) { PersonFace(name: p.name, role: crewRole(p.role), photo: p.photo) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if similar, let saga = x.collection {
                section(title: "La saga", meta: Text(verbatim: saga.name)) { ForEach(saga.parts) { TmdbPoster(title: $0) } }
            }
            if similar, !x.recommendations.isEmpty {
                section(title: "Más como esto", meta: Text("Si te gusta esta")) { ForEach(x.recommendations) { TmdbPoster(title: $0) } }
            }
        }
    }

    func section<Content: View>(title: LocalizedStringKey, meta: Text, count: Int? = nil, headed: Bool = true, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if headed { DSSectionHead(title: title, count: count, meta: meta).padding(.horizontal, side) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) { content() }.scrollTargetLayout().environment(\.posterCaptions, false)
            }
            .contentMargins(.horizontal, side, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    /// El margen de los lados: el del iPhone, o el de la TV en el iPad y la Mac (FE2-B). Las filas salen por la orilla.
    var side: CGFloat { sizeClass == .regular ? DS.TitleAction.wideSide : DS.Space.gutter }

    /// El trabajo de alguien del equipo, en español (TMDB lo manda en inglés); un personaje se queda tal cual.
    func crewRole(_ role: String) -> String {
        let language = env.services.appSettings.uiLanguage
        switch role {
        case "Director": return Strings.tr("Dirección", language: language)
        case "Screenplay", "Writer": return Strings.tr("Guion", language: language)
        case "Novel": return Strings.tr("Novela", language: language)
        case "Creator": return Strings.tr("Creación", language: language)
        default: return role
        }
    }

    @ViewBuilder func credits(_ model: TitleModel) -> some View {
        if !model.credits.cast.isEmpty || !model.credits.directors.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if !model.credits.cast.isEmpty { creditLine("Reparto", model.credits.cast) }
                if !model.credits.directors.isEmpty { creditLine("Dirección", model.credits.directors) }
                if !model.credits.writers.isEmpty { creditLine("Guion", model.credits.writers) }
            }
        }
    }

    func creditLine(_ title: LocalizedStringKey, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(title).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)
            Text(names.joined(separator: ", ")).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
        }
    }
}
