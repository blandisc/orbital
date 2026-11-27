import SwiftUI
import OrbitalCore

// A dónde se navega desde cualquier pestaña (salieron de `RootView.swift` el 27 nov 2026, por su tope de líneas).

/// Ajustes (desde el ícono de la esquina de Inicio).
struct SettingsRoute: Hashable {}

/// Un título al que se navega.
struct TitleRoute: Hashable {
    var kind: String
    var metaID: String
    var title: String
    var poster: String?
    /// Abrir ya «Versión» de este video (P2-B: «Probar otra versión» desde «Tus pedidos»).
    var versionsFor: String? = nil
}
