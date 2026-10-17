import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un título de TMDB (recomendación, saga, filmografía): busca su id de IMDb y abre la ficha de siempre.
struct TmdbTitleView: View {
    let title: TmdbTitle
    @EnvironmentObject private var env: AppEnvironment
    @State private var route: TitleRoute?
    @State private var missing = false

    var body: some View {
        Group {
            if let route { TitleView(route: route) }
            else if missing { DSNotice(text: "Este título no está en Stremio.").padding(DS.Space.gutter) }
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

/// Una persona (al tocar su cara): su foto, de dónde es, su biografía (se despliega) y lo que ha hecho, lo más conocido primero.
struct PersonView: View {
    let route: PersonRoute
    @EnvironmentObject private var env: AppEnvironment
    @State private var person: PersonDetails?
    @State private var failed = false
    @State private var expanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                HStack(alignment: .top, spacing: DS.Space.s4) {
                    PersonPhoto(name: route.name, photo: person?.photo, size: DS.Rich.personPhoto)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(verbatim: route.name).recipe(.title)
                        if let born = person?.born { Text(verbatim: [born, person?.place].compactMap { $0 }.joined(separator: " · ")).recipe(.footnote) }
                    }
                }
                if let bio = person?.biography, !bio.isEmpty {
                    Text(verbatim: bio).recipe(.secondary, color: DS.textMuted).lineLimit(expanded ? nil : DS.Rich.bioLines)
                        .onTapGesture { withAnimation { expanded.toggle() } }
                }
                if let credits = person?.credits, !credits.isEmpty {
                    DSSectionHead(title: "Filmografía", icon: .list, count: credits.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Poster.railWidth), spacing: DS.Space.s3)], spacing: DS.Space.s4) {
                        ForEach(credits) { TmdbPoster(title: $0) }
                    }
                }
                if person == nil && !failed { ProgressView().frame(maxWidth: .infinity) }
                if failed { DSNotice(text: "No pude traer a esta persona de TMDB.") }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s14)
        }
        .background(Backdrop())
        .navigationTitle(Text(verbatim: route.name)).navigationBarTitleDisplayMode(.inline)
        .task {
            guard person == nil else { return }
            do { person = try await env.services.tmdb.person(route.id) } catch { failed = true }
        }
    }
}
