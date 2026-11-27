import SwiftUI
import OrbitalModels

/// La puerta única del nombre de una película o serie en las vistas (revisión 2 del 11 nov 2026): un mismo título se llama
/// igual en Inicio, la ficha, Guardado, Lo que ves, Buscar, el control y el reproductor. La regla vive en
/// `OrbitalModels.TitleNames` (la misma de la TV); aquí solo se lee del entorno:
///
///     @Environment(\.titleName) private var titleName
///     Text(verbatim: titleName(item.title, id: item.metaID, kind: item.kind))
///
/// `DesignRulesTests.testTitlesGoThroughOneDoor` revisa que ninguna vista pinte el nombre crudo.
struct TitleDoor {
    let names: TitleNames?

    @MainActor func callAsFunction(_ raw: String, id: String?, kind: String? = nil) -> String {
        names?.name(raw, id: id, kind: kind) ?? DisplayTitle.resolve(raw: raw, known: nil)
    }

    /// El logo de un título solo si dice lo mismo que su nombre aquí (`DisplayTitle.logoFits`, PU2-A); si no, nil y
    /// `TitleLogo` escribe el nombre en letra. Todo logo junto a un nombre pasa por aquí (`testLogosSayTheShownName`).
    @MainActor func logo(_ url: String?, for raw: String, id: String?, kind: String? = nil) -> String? {
        guard let url else { return nil }
        return DisplayTitle.logoFits(source: raw, shown: callAsFunction(raw, id: id, kind: kind)) ? url : nil
    }
}

extension EnvironmentValues {
    @Entry var titleName = TitleDoor(names: nil)
}
