import Foundation
import OrbitalCore

/// «Tu año» (Ajustes › Tu año): lo que viste desde el 1 de enero según Trakt. Antes la vista le pedía a Para ti directo
/// (auditoría del 31 oct 2026, B2).
@MainActor
public final class YearReviewModel: ObservableModel {
    /// nil sin Trakt o si no contestó.
    public private(set) var review: YearInReview? { didSet { if oldValue != review { changed() } } }
    public private(set) var loading = true { didSet { if oldValue != loading { changed() } } }

    private let services: Services
    private let preset: YearInReview?

    /// `preset`: un año ya armado (la demostración), sin pedir nada.
    public init(_ services: Services, preset: YearInReview? = nil) {
        self.services = services
        self.preset = preset
    }

    /// El último día con algo visto (el mapa abre ahí).
    public var lastDay: Date? { review?.plays.keys.max() }

    public func load() async {
        guard loading else { return }
        review = if let preset { preset } else { await services.forYou.yearInReview() }
        loading = false
    }
}
