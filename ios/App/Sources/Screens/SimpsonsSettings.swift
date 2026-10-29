import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Un Simpson al azar» (Ajustes): de qué temporadas sale el episodio de la dona de Inicio. Las temporadas que existen llegan
/// de Cinemeta al abrirla.
struct SimpsonsSeasonsSection: View {
    @Environment(AppEnvironment.self) private var env
    /// Lo elegido aquí (hasta que no toques nada, lo de Ajustes).
    @State private var selected: [Int]?
    @State private var available = Array(1...SimpsonsModel.knownSeasons)
    /// Cómo se guarda (Ajustes lo pasa por su modelo para que su renglón se ponga al día); sin él, directo a los ajustes.
    var save: (([Int]) -> Void)?

    var body: some View {
        Section {
            SimpsonsSeasonsPicker(selected: selected ?? env.services.appSettings.simpsonsSeasons, available: available, classics: SimpsonsModel.classics) { seasons in
                selected = seasons
                if let save { save(seasons) } else { env.services.settings.update { $0.simpsonsSeasons = seasons }; env.services.settingsDidChange() }
                env.simpsons.seasonsChanged()
            }
            .padding(.vertical, DS.Space.s2)
            .task { available = await env.simpsons.seasonNumbers() }
        } header: { Text("Temporadas") } footer: { Text("La dona de Inicio elige un episodio de estas temporadas.") }
        .listRowBackground(DS.surface)
    }

    /// Lo elegido en pocas palabras, para el renglón de Ajustes: «Las clásicas», «Temporada 4» o «12 temporadas».
    static func summary(_ seasons: [Int]) -> Text {
        if Set(seasons) == Set(SimpsonsModel.classics) { return Text("Las clásicas") }
        if seasons.count == 1, let only = seasons.first { return Text("Temporada \(only)") }
        return Text("\(seasons.count) temporadas")
    }
}
