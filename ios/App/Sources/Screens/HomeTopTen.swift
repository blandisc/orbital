import SwiftUI
import OrbitalModels

/// «Top 10 en …» de Inicio: el título con la pastilla de tipo, una pastilla por servicio y el riel con los diez. Aparte de
/// `HomeView` para que ningún archivo pase su tope (`FileBudgetTests`).
struct HomeTopTen: View {
    let model: HomeModel
    @Binding var topMovies: Bool
    @Environment(\.titleName) private var titleName
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// A qué pastilla se ancla la fila: la elegida contra el margen (donde se detiene al deslizar), o el principio si es de las
    /// primeras (se ve completa sin mover nada).
    private func pillAnchor(_ brand: String) -> String {
        let all = HomeModel.topServices.map(\.brand)
        return (all.firstIndex(of: brand) ?? 0) <= 1 ? all[0] : brand
    }

    var body: some View {
        model.track()   // se vuelve a pintar con el modelo, como cuando vivía dentro de `HomeView`
        let service = model.topService
        let series = model.top(kind: "series"), films = model.top(kind: "movie")
        let pageKind = model.spotlightKind
        let movies = pageKind == "movie" ? true : pageKind == "series" ? false : (topMovies && !films.isEmpty || series.isEmpty)
        let items = movies ? films : series
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            // Con letra de accesibilidad la pastilla baja bajo el título (al lado lo empujaba fuera de la pantalla).
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s2))
                                                      : AnyLayout(HStackLayout(alignment: .sectionTitle))
            layout {
                DSSectionHead(title: Text("Top 10 en \(service.name)"),
                              eyebrow: service.weekly ? Text("Esta semana en tu país") : Text("Lo más visto hoy · JustWatch"), quiet: true)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(DS.Size.titleShrink)
                if !typeSize.isAccessibilitySize { Spacer(minLength: DS.Space.s2) }
                // La pastilla junto al título, con ícono (Fernando, 31 oct 2026). Siempre ocupa su lugar (oculta si el servicio
                // solo tiene uno de los dos): al cambiar de servicio nada brinca.
                DSKindFilter(kind: Binding(get: { movies ? "movie" : "series" }, set: { topMovies = $0 == "movie" }), includeAll: false)
                    .opacity(pageKind == nil && !series.isEmpty && !films.isEmpty ? 1 : 0).disabled(pageKind != nil || series.isEmpty || films.isEmpty)
            }
            .padding(.horizontal, DS.Space.gutter)
            // De qué servicio: una pastilla por cada uno, con su logo (la elegida, con su color). Ancladas: al deslizar se
            // detienen en el borde de una pastilla (nunca a la mitad) y la elegida siempre queda a la vista.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(HomeModel.topServices) { s in
                            PlatformPill(name: s.name, logo: s.logo, brand: s.brand, selected: s.brand == service.brand) {
                                Task { await model.selectTop(s.brand) }
                            }
                            .id(s.brand)
                            .accessibilityIdentifier("top-\(s.brand)")
                        }
                    }
                    .padding(.vertical, DS.Stroke.selected)   // el anillo de la elegida no se recorta
                    .scrollTargetLayout()
                }
                .scrollClipDisabled()   // lo que crece al picarlo (o al dejarlo apretado) no se corta en la orilla del listón
                .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
                // Un riel: solo de lado. Antes la fila tenía unos puntos de más y se podía mover arriba y abajo.
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .scrollTargetBehavior(.viewAligned)
                // Un riel fijo: tocar una pastilla no recorre la fila (antes saltaba para dejarla al borde). Solo al abrir, si la
                // guardada está lejos, se acerca.
                .onAppear { proxy.scrollTo(pillAnchor(service.brand), anchor: .leading) }
            }
            .dsFeedback(.selection, trigger: service.brand)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: DS.Space.s2) {
                    if items.isEmpty {
                        if model.loadingTop { ShelfSkeleton() }
                        else { Text("Hoy no hay ranking de este servicio.").recipe(.footnote).frame(width: DS.Size.cardMax, alignment: .leading) }
                    }
                    // El puesto dentro de lo que ves (Series 1, 2, 3…): con el del ranking mezclado, al quitar las películas brincaba
                    // del 4 al 6 (Fernando, 16 nov 2026: «pasa del 4 al 6, se come un par»).
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                        TitleNavigationLink(route: s.route) { RankedPosterCard(rank: i + 1, title: titleName(s.title, id: s.imdb, kind: s.kind), poster: s.poster, movement: s.movement, isNew: s.isNew, tint: DS.PlatformTint.color(service.brand), zoom: s.route) }
                            .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollClipDisabled()   // lo que crece al picarlo (o al dejarlo apretado) no se corta en la orilla del listón
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .pagingArrows()   // C4: ‹ › con el puntero
            .id("\(service.brand)-\(movies)")   // al cambiar, desde el n.º 1
            .transition(.opacity)
        }
        .animation(DS.Motion.base(reduceMotion), value: service.brand)
        .task(id: items.first?.imdb) { ImagePipeline.shared.prefetchPosters(items.map(\.poster)) }
    }
}
