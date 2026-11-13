import SwiftUI
import OrbitalCore
import OrbitalModels

/// Lo que se sugiere, para «Decide por mí», sacado de lo que carga Explorar (`ParaTiModel`). Un solo lugar para las dos
/// puertas (Explorar e Inicio): antes vivía dentro de `ParaTiView` y por eso Inicio mandaba a Explorar para abrir la hoja.
extension ParaTiModel {
    /// «Porque viste», el mosaico y cada estante que se ve.
    func decidePool() -> [Suggestion] { (because?.items ?? []) + mosaic + visibleShelves.flatMap { items(for: $0) } }

    /// El abanico de la puerta (`DecideDoor`), igual en Inicio y en Explorar: carteles de lo mismo que alimenta la hoja, sin
    /// repetir, saltando los primeros (en Explorar ya son la portada del mosaico) si hay de dónde.
    func decideFan() -> [String] {
        var seen = Set<String>()
        let posters = decidePool().map(\.poster).filter { !$0.isEmpty && seen.insert($0).inserted }
        let skip = posters.count >= DS.ParaTiB.matchFan * 2 ? DS.ParaTiB.matchFan : 0
        return Array(posters.dropFirst(skip).prefix(DS.ParaTiB.matchFan))
    }

    /// De dónde («De qué listas»): «Porque viste», lo nuevo en tus plataformas, cada estante que se ve (con su nombre) y todas
    /// tus listas (las que aún no se abren se piden solo si las eliges).
    func decideSources(language: String) -> [DecideModel.Source] {
        var out: [DecideModel.Source] = []
        let suggested = "Sugerencias"
        if let because { out.append(.init(id: "because", name: String(format: Strings.tr("Porque viste %@", language: language), because.seed.title), origin: suggested, items: because.items)) }
        if !newOnPlatforms.isEmpty { out.append(.init(id: "new", name: Strings.tr("Nuevo en tus plataformas", language: language), origin: suggested, items: newOnPlatforms)) }
        for plan in visibleShelves {
            let name: String = switch plan.id {
            case "watchlist": Strings.tr("Mi lista", language: language)
            case "mine": Strings.tr("Tus series", language: language)
            case "recs": Strings.tr("Recomendadas", language: language)
            case "trend": Strings.tr("En tendencia", language: language)
            case "popular": Strings.tr("Lo más popular", language: language)
            default: plan.title.isEmpty ? plan.id : plan.title
            }
            out.append(.init(id: plan.id, name: name, origin: DecideModel.origin(ofShelf: plan.id), items: items(for: plan)))   // F7: «Mi lista» es tuya
        }
        for list in traktLists where !out.contains(where: { $0.id == list.id }) && !list.title.isEmpty {
            let yours = list.group == .mine || DecideModel.origin(ofShelf: list.id) == DecideModel.yoursOrigin
            let origin = yours ? DecideModel.yoursOrigin : list.source.isEmpty ? suggested : list.source
            out.append(.init(id: list.id, name: list.title, origin: origin, items: items(for: list), load: decideLoader(for: list)))
        }
        return out
    }
}

/// La hoja de «Decide por mí» desde cualquier puerta, sobre la pantalla donde estás (Fernando, 13 nov 2026: la tarjeta de
/// Inicio la abre ahí mismo, sin mandarte a Explorar). Lo que se sugiere sale del mismo `ParaTiModel` de Explorar
/// (`env.paraTi`); si aún no ha cargado, la hoja dice que carga y lo pide, en lugar de abrirse vacía. `open`: una ficha
/// elegida en la hoja, que abre la pantalla de abajo.
struct DecideSheet: View {
    let open: (TitleRoute) -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let m = env.paraTi.model
        let language = env.services.appSettings.uiLanguage
        Group {
            if m.hasLoaded || !m.decidePool().isEmpty {
                DecideView(pool: m.decidePool(), sources: m.decideSources(language: language),
                           reload: { await m.refresh(); return (m.decidePool(), m.decideSources(language: language)) }, open: open)
            } else {
                // Lo que se sugiere aún no llega (Inicio antes de pasar por Explorar): la hoja con su título y el cargando.
                VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                    DSSheetHeader(title: Text("Decide por mí")) { EmptyView() }
                    DSLoadingState()
                }
                .dsSheetContent()
                .presentationDetents([.height(DS.Decide.quickHeight)])
                .presentationDragIndicator(.visible)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("decide-loading")
            }
        }
        .task { await m.loadIfStale() }
    }
}
