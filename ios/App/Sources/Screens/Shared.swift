import SwiftUI
import OrbitalCore
import OrbitalModels

/// Arriba a la derecha de cada pestaña: tu avatar, que abre Ajustes (en todas igual: siempre se sabe dónde están).
struct ProfileButton: View {
    @Environment(AppEnvironment.self) private var env
    var avatar: String?
    var body: some View {
        NavigationLink(value: SettingsRoute()) { AvatarImage(id: avatar ?? env.services.appSettings.avatar) }
            .accessibilityLabel(Text("Ajustes"))
    }
}

/// Una lista de Inicio abierta completa desde su encabezado («Mi lista 12 ›»).
struct HomeListRoute: Hashable {
    var id: String
    /// La lista tuya que enseña (para «Quitar de …» al dejar picado un título); «Para ti» y «Seguir viendo» no son una lista.
    var list: SaveDestination? { id == "watchlist" ? .myList : nil }
}
