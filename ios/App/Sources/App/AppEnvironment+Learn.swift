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
        case .languages: ui.openLanguages = true   // Ajustes › Tus idiomas (ella sola pone Ajustes debajo; con las dos salían dos Ajustes)
        }
    }
}

extension AppEnvironment {
    /// Ya tienes lo que ofrece el botón final de la lección (tu nube, Trakt, tu TV): entonces la lección cierra con «Listo».
    func hasWhatLessonOffers(_ lesson: String) -> Bool {
        switch lesson {
        case "nube": services.debrid.hasToken
        case "tuyo": services.trakt?.linked == true
        case "tv": services.orbital.isConfigured
        default: false
        }
    }
}
