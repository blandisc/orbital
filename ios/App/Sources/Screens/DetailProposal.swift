#if DEBUG
import SwiftUI
import OrbitalCore
import OrbitalModels

/// MAQUETA DESECHABLE (rama exp/pagina-detalle, no va a main): la ficha propuesta en docs/propuesta-pagina-detalle.md,
/// armada solo con piezas del catálogo y datos fijos. `-demo -demo-proposal serie|pelicula` (con `-demo-scroll N`).
struct DetailProposal: View {
    let movie: Bool
    @State private var scrolled: CGFloat = 0
    @State private var season = 2
    @Environment(\.colorScheme) private var scheme

    private var id: String { movie ? "tt15239678" : "tt0386676" }
    private var art: String { "https://images.metahub.space/background/medium/\(id)/img" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    hero
                    if !movie { episodes }
                    about
                    cast
                    if movie { information }
                }
                .padding(.bottom, DS.Space.s10)
            }
            #if DEBUG
            .modifier(DemoScroll())
            #endif
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in scrolled = y }
            .overlay(alignment: .top) {
                Button { } label: { Label(movie ? "Ver" : "Continuar T2 E5", systemImage: "play.fill").font(DS.TextRecipe.footnote.font.weight(.semibold)) }
                    .dsSolidPrimaryButton().buttonBorderShape(.capsule)
                    .offset(y: -DS.Size.touchTarget - DS.Space.s2)
                    .opacity(scrolled > 360 ? 1 : 0)
            }
            .background(Backdrop(tint: nil))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { } label: { Image(systemName: "chevron.left") } }
                // Propuesta: al pasar «Ver», queda a la mano en la barra (como Apple TV y Música).
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { } label: { Image(systemName: "tv") }
                    Button { } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }

    /// Arte más bajo (la mitad de la pantalla), y todo lo de decidir y actuar sobre él: rótulo, logo, datos, «Ver» y tres
    /// acciones redondas (Guardar, Descargar, Más). Debajo ya empieza lo siguiente (episodios o «Acerca de»).
    private var hero: some View {
        BleedArt(url: art, title: movie ? "Dune: Parte dos" : "The Office", aspect: 0.82, collapse: DS.bg) {
            VStack(spacing: DS.Space.s3) {
                Eyebrow(text: movie ? Text(verbatim: "Película · Ciencia ficción") : Text(verbatim: "Serie · 9 temporadas"), onArt: true)
                TitleLogo(url: Artwork.logoURL(metaID: id), title: movie ? "Dune: Parte dos" : "The Office", size: .hero, centered: true)
                    .containerRelativeFrame(.horizontal) { w, _ in w * 0.6 }
                DataLine(parts: movie ? ["2024", "2 h 47 min", "B12", "4K · Dolby Vision"] : ["2005–2013", "Comedia", "22 min", "B"])
                Button { } label: {
                    VStack(spacing: DS.Space.s1) {
                        Label(movie ? "Ver" : "Continuar T2 E5 · quedan 20 min", systemImage: "play.fill").font(DS.TextRecipe.body.font.weight(.semibold))
                        Text(verbatim: movie ? "Latino · 4K · Dolby Vision" : "Español · 1080p").font(DS.TextRecipe.caption.font.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: DS.TitleAction.primaryHeight - DS.Space.s3 * 2)
                }
                .dsSolidPrimaryButton()
                HStack(spacing: DS.Space.s6) {
                    action("checkmark", "Guardada")
                    action("arrow.down.circle", "Descargar")
                    if movie { action("play.rectangle", "Tráiler") }
                    action("ellipsis", "Más")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .top)
    }

    private func action(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: DS.Space.s1) {
            // Pieza nueva propuesta (`TitleActionCircle`): el círculo del mismo tamaño sea cual sea el glifo.
            Button {} label: { Image(systemName: symbol).frame(width: DS.TitleAction.ringSmall, height: DS.TitleAction.ringSmall) }
                .dsIconButtonLook().buttonBorderShape(.circle).controlSize(.large).accessibilityLabel(Text(verbatim: title))
            Text(verbatim: title).recipe(.caption, color: DS.onArtSecondary)
        }
    }

    /// Series: los episodios justo debajo del arte, en una tira con «Temporada 2 ⌄» en el encabezado; el que sigue, primero.
    private var episodes: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack {
                Menu { ForEach(1...9, id: \.self) { s in Button("Temporada \(s)") { season = s } } } label: {
                    HStack(spacing: DS.Space.s1) { Text(verbatim: "Temporada \(season)").recipe(.section); Image(systemName: "chevron.down").font(DS.TextRecipe.footnote.font.weight(.semibold)) }
                }
                .tint(DS.text)
                Spacer()
                Text(verbatim: "4 de 22 vistos").recipe(.footnote)
            }
            .padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    StillCard(title: "5 · Halloween", art: still(5), data: ["Sigue", "quedan 20 min"], progress: 0.1)
                    StillCard(title: "6 · The Fight", art: still(6), data: ["22 min"])
                    StillCard(title: "7 · The Client", art: still(7), data: ["22 min"])
                    StillCard(title: "8 · Performance Review", art: still(8), data: ["22 min"])
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func still(_ e: Int) -> String { "https://episodes.metahub.space/\(id)/\(season)/\(e)/w780.jpg" }

    /// «Acerca de»: la sinopsis en tu idioma (3 renglones y «más»), calificaciones y quién la hizo, en un solo bloque.
    private var about: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: Text(verbatim: "Acerca de"))
            Text(verbatim: movie ? "Paul Atreides se une a Chani y a los Fremen mientras busca venganza contra quienes destruyeron a su familia. Ante una elección entre el amor de su vida y el destino del universo…"
                                 : "Un falso documental sobre un grupo de oficinistas, donde el día a día está hecho de choques de ego, comportamientos inapropiados, tedio y romance.")
                .recipe(.body).lineLimit(3)
            RatingsRow(imdb: movie ? "8.4" : "9.0", tmdb: movie ? 8.1 : 8.6, trakt: movie ? 8.3 : 8.4)
            Text(verbatim: movie ? "Dirección Denis Villeneuve" : "Creada por Greg Daniels").recipe(.footnote)
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    private var cast: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: Text(verbatim: "Reparto"), trailing: Text(verbatim: "Ver todo"))
                .padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    ForEach(movie ? [("Timothée Chalamet", "Paul"), ("Zendaya", "Chani"), ("Rebecca Ferguson", "Jessica"), ("Javier Bardem", "Stilgar")]
                                  : [("Steve Carell", "Michael"), ("Rainn Wilson", "Dwight"), ("John Krasinski", "Jim"), ("Jenna Fischer", "Pam")], id: \.0) { p in
                        PersonFace(name: p.0, role: p.1, photo: nil)
                    }
                }
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
        }
    }

    /// Película: los datos de consulta al final, en dos columnas (como «Información» de Apple TV).
    private var information: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: Text(verbatim: "Información"))
            Grid(alignment: .leading, horizontalSpacing: DS.Space.s6, verticalSpacing: DS.Space.s3) {
                GridRow { fact("Estreno", "1 de marzo de 2024"); fact("Duración", "2 h 47 min") }
                GridRow { fact("Clasificación", "B12"); fact("Disponible", "4K · DV · Atmos") }
                GridRow { fact("Audio", "Latino, Inglés"); fact("Subtítulos", "Español, Inglés") }
            }
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: label).recipe(.footnote)
            Text(verbatim: value).recipe(.secondary, color: DS.text)
        }
    }
}
#endif
