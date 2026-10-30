import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un título de TMDB (recomendación, saga, filmografía): busca su id de IMDb y abre la ficha de siempre.
struct TmdbTitleView: View {
    let title: TmdbTitle
    @Environment(AppEnvironment.self) private var env
    @State private var route: TitleRoute?
    @State private var missing = false

    var body: some View {
        Group {
            if let route { TitleView(route: route) }
            else if missing { DSEmptyState(symbol: "film", title: Text("No encontré este título")) }
            else { ProgressView() }
        }
        .task {
            guard route == nil else { return }
            if let imdb = await TitleModel.imdbID(of: title, services: env.services) {
                route = TitleRoute(kind: title.kind, metaID: imdb, title: title.title, poster: title.poster)
            } else { missing = true }
        }
    }
}

/// Una persona (al tocar su cara): su foto, de dónde es, su biografía (se despliega con «Más») y lo que ha hecho, lo más
/// conocido primero, en la cuadrícula de pósters de la app. El nombre sube a la barra solo al deslizar (arriba ya está grande).
struct PersonView: View {
    let route: PersonRoute
    @Environment(AppEnvironment.self) private var env
    @State private var person: PersonDetails?
    @State private var failed = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrolledDown = false
    /// La biografía no cabe en sus renglones (entonces sí va «Más»).
    @State private var bioCut = false
    @State private var bioFull: CGFloat = 0
    @State private var bioShown: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                VStack(alignment: .leading, spacing: DS.Space.s5) {
                    HStack(alignment: .top, spacing: DS.Space.s4) {
                        PersonPhoto(name: route.name, photo: person?.photo, size: DS.Rich.personPhoto)
                        VStack(alignment: .leading, spacing: DS.Space.s1) {
                            Text(verbatim: route.name).recipe(.title)
                            if let born = person?.born { Text(verbatim: [born, person?.place].compactMap { $0 }.joined(separator: " · ")).recipe(.footnote) }
                        }
                    }
                    if let bio = person?.biography, !bio.isEmpty { biography(bio) }
                    if let credits = person?.credits, !credits.isEmpty { DSSectionHead(title: "Filmografía", eyebrow: Text("Dónde la has visto")) }
                }
                .padding(.horizontal, DS.Space.gutter)
                if let credits = person?.credits, !credits.isEmpty {
                    DSPosterGrid(items: credits) { title, width in TmdbPoster(title: title, width: width) }
                } else if person != nil {
                    DSEmptyState(symbol: "film", title: Text("Sin filmografía"), message: Text("TMDB no tiene títulos de esta persona."))
                }
                if person == nil && !failed { ProgressView().frame(maxWidth: .infinity).padding(.vertical, DS.Space.s10) }
                if failed { DSNotice(text: "No pude traer a esta persona de TMDB.").padding(.horizontal, DS.Space.gutter) }
            }
            .padding(.bottom, DS.Space.s14)
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > DS.Size.titleCollapse } action: { _, down in scrolledDown = down }
        .background(Backdrop())
        // El nombre en la barra solo cuando el grande ya se fue (o si no hay nada más que mostrar).
        .navigationTitle(scrolledDown || failed ? Text(verbatim: route.name) : Text(verbatim: "")).navigationBarTitleDisplayMode(.inline)
        .task {
            guard person == nil else { return }
            do { person = try await env.services.tmdb.person(route.id) } catch { failed = true }
        }
    }

    /// La biografía en unos renglones, con «Más ⌄» a la vista para leerla completa (antes solo se desplegaba al tocar el texto).
    private func biography(_ bio: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: bio).recipe(.secondary, color: DS.textMuted).lineLimit(expanded ? nil : DS.Rich.bioLines)
                .background(alignment: .topLeading) {
                    // La biografía completa, invisible, para saber si se corta.
                    Text(verbatim: bio).recipe(.secondary).fixedSize(horizontal: false, vertical: true).hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full in bioFull = full; if !expanded { bioCut = full > bioShown + 1 } }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shown in if !expanded { bioShown = shown; bioCut = bioFull > shown + 1 } }
            if bioCut || expanded { Button { withAnimation(DS.Motion.base(reduceMotion)) { expanded.toggle() } } label: {
                // «Más ⌄»: el nombre primero y el ícono después.
                HStack(spacing: DS.Space.s1) { Text(expanded ? "Menos" : "Más"); Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                    .font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.accent)
            }
            .buttonStyle(.plain)
            .frame(minHeight: DS.Size.touchTarget)
            .accessibilityIdentifier("person-bio-more") }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(DS.Motion.base(reduceMotion)) { expanded.toggle() } }
    }
}
