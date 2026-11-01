import Foundation
import OrbitalCore

/// Una persona de TMDB (al tocar una cara en la ficha): su foto, su biografía y lo que ha hecho. Antes la vista le pedía a
/// TMDB directo y no había cómo probarlo (auditoría del 31 oct 2026, B2).
@MainActor
public final class PersonModel: ObservableModel {
    public private(set) var person: PersonDetails? { didSet { if oldValue != person { changed() } } }
    /// TMDB no contestó (sin red, sin clave, la persona no existe).
    public private(set) var failed = false { didSet { if oldValue != failed { changed() } } }
    public var isLoading: Bool { person == nil && !failed }

    private let services: Services
    private let id: Int

    public init(_ services: Services, id: Int) {
        self.services = services
        self.id = id
    }

    /// Una vez: al volver a la pantalla no se pide otra vez.
    public func load() async {
        guard person == nil else { return }
        do {
            person = try await services.tmdb.person(id)
            failed = false
        } catch {
            failed = true
        }
    }
}
