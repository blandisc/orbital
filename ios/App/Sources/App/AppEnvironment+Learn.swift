import SwiftUI
import UIKit
import OrbitalModels

/// Adónde lleva el botón de la última tarjeta de una historia de «Aprende Orbital» (G3).
extension AppEnvironment {
    func open(_ destination: LearnStory.Destination) {
        switch destination {
        case .connectDebrid, .connectTrakt, .tv: ui.openSettings = true
        case .renewDebrid: UIApplication.shared.open(services.debrid.provider.renewURL)
        case .advancedSearch: openTab = 2; ui.openAdvancedFilter = true
        case .explore, .decide, .watching: openTab = 1
        case .downloads: openTab = Self.downloadsTab
        case .calendar: openTab = 0
        case .languages: ui.openLanguages = true; ui.openSettings = true   // Ajustes › Idiomas y subtítulos › Tus idiomas
        }
    }
}

/// La historia abierta (para `fullScreenCover(item:)`).
struct StoryRoute: Identifiable { let id: String }
