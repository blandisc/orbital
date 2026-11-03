import AppIntents
import OrbitalCore

// Elegir la lista del widget «Mosaico de una lista». Vive en `Shared/` (la app y la extensión): iOS busca el intent de
// configuración también en la app; solo en la extensión, la galería no le pasaba ninguno («Intent configuration is required»).

/// Una de tus listas de Explorar, para el selector del widget.
struct WidgetListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Lista"
    static let defaultQuery = WidgetListQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct WidgetListQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetListEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WidgetListEntity] { all() }
    func defaultResult() async -> WidgetListEntity? { all().first }
    private func all() -> [WidgetListEntity] { (WidgetStore.loadLists()?.lists ?? []).map { WidgetListEntity(id: $0.id, title: $0.title) } }
}

struct ChooseListIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Elegir lista"
    static let description = IntentDescription("La lista de Explorar que enseña el mosaico.")
    @Parameter(title: "Lista") var list: WidgetListEntity?
    init() {}
}

/// «Revolver» en el widget «Mosaico de una lista»: otro orden de pósters al momento, sin abrir la app (Fernando, 2 nov 2026).
/// Corre en la extensión; iOS vuelve a dibujar el widget al terminar.
struct ShuffleMosaicIntent: AppIntent {
    static let title: LocalizedStringResource = "Revolver el mosaico"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult {
        WidgetStore.shuffleMosaic()
        return .result()
    }
}
