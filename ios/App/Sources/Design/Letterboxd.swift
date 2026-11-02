import SwiftUI
import OrbitalCore

// MARK: Letterboxd (solo leer: tu diario, tus reseñas y tus listas)

/// Los tres puntos de Letterboxd: dicen de dónde viene algo, chiquitos, junto a su nombre.
struct LetterboxdMark: View {
    var body: some View {
        HStack(spacing: DS.Space.s1 / 2) {
            ForEach([DS.Letterboxd.ember, DS.Letterboxd.leaf, DS.Letterboxd.sky], id: \.self) { Circle().fill($0).frame(width: DS.Letterboxd.dot, height: DS.Letterboxd.dot) }
        }
        .accessibilityHidden(true)
    }
}

/// Tus estrellas de Letterboxd (con medias) en su verde, y el ♥ si le diste me gusta.
struct LetterboxdStars: View {
    let rating: Double?
    var liked = false

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            if let rating {
                Text(verbatim: String(repeating: "★", count: Int(rating)) + (rating.truncatingRemainder(dividingBy: 1) >= 0.5 ? "½" : ""))
                    .recipe(.label, color: DS.Letterboxd.leaf)
            }
            if liked { Image(systemName: "heart.fill").font(DS.TextRecipe.caption.font).foregroundStyle(DS.Letterboxd.ember) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(stars: rating, liked: liked))
    }
}

extension Text {
    /// «4 y media estrellas · te gustó».
    init(stars rating: Double?, liked: Bool) {
        let half = (rating ?? 0).truncatingRemainder(dividingBy: 1) >= 0.5
        let base: Text = rating.map { half ? Text("\(Int($0)) y media estrellas") : Text("\(Int($0)) estrellas") } ?? Text(verbatim: "")
        self = liked ? (rating == nil ? Text("Te gustó") : Text("\(base) · te gustó")) : base
    }
}

/// Una reseña de «Tus reseñas»: el póster, el nombre y el año, tus estrellas, dos renglones de tu reseña y cuándo la viste.
struct LetterboxdReviewRow: View {
    let entry: LetterboxdEntry
    let watched: Text?

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            PosterView(url: entry.imdb.map { String(format: ForYou.metahubPoster, $0) }, title: entry.title).frame(width: DS.Letterboxd.poster)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("\(Text(verbatim: entry.title).bold())\(Text(verbatim: entry.year.map { "  \($0)" } ?? "").foregroundStyle(DS.textMuted))")
                    .recipe(.body).lineLimit(1)
                LetterboxdStars(rating: entry.rating, liked: entry.liked)
                if let review = entry.review { Text(verbatim: review).recipe(.footnote, color: DS.textMuted).lineLimit(2) }
                if let watched { watched.recipe(.caption, color: DS.textMuted) }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Tu reseña en la ficha: debajo de los botones, con el borde verde de Letterboxd. Sin reseña ni estrellas, no ocupa lugar.
struct LetterboxdReviewCard: View {
    let entry: LetterboxdEntry
    let watched: Text?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                LetterboxdMark()
                Text("Tu reseña en Letterboxd").recipe(.label, color: DS.Letterboxd.leaf)
            }
            HStack(spacing: DS.Space.s2) {
                LetterboxdStars(rating: entry.rating, liked: entry.liked)
                if let watched { watched.recipe(.caption, color: DS.textMuted) }
            }
            if let review = entry.review {
                Text(verbatim: review).recipe(.footnote, color: DS.textMuted).lineLimit(expanded ? nil : 4)
                    .onTapGesture { expanded.toggle() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(.row)
        .overlay(alignment: .leading) { Rectangle().fill(DS.Letterboxd.leaf).frame(width: DS.Letterboxd.edge).clipShape(Capsule()) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("letterboxd-review")
    }
}

/// Cómo se dice cuándo la viste: «Vista el 1 nov» u «… · otra vez».
enum LetterboxdWords {
    static func watched(_ e: LetterboxdEntry, language: String) -> Text? {
        guard let day = e.watched else { return nil }
        let when = Text(verbatim: Strings.date(day, .dayMonthShort, language: language))
        return e.rewatch ? Text("Vista el \(when) · otra vez") : Text("Vista el \(when)")
    }
}

/// «Reseñas en Letterboxd» de la ficha: las populares (quién, sus estrellas, cuántos «me gusta» y el texto). Las que traen
/// spoilers van tapadas hasta que las tocas. Abajo, todas en Letterboxd.
struct LetterboxdPublicReviews: View {
    let reviews: [LetterboxdPublicReview]
    let link: URL?
    @State private var revealed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                LetterboxdMark()
                DSSectionHead(title: Text("Reseñas en Letterboxd"), level: .subsection)
            }
            ForEach(reviews.prefix(DS.Letterboxd.publicShown)) { r in
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack(spacing: DS.Space.s2) {
                        Text(verbatim: r.author).recipe(.label)
                        LetterboxdStars(rating: r.rating)
                        if let likes = r.likes {
                            Label { Text(likes, format: .number.notation(.compactName)) } icon: { Image(systemName: "heart") }
                                .recipe(.caption, color: DS.textMuted)
                        }
                    }
                    if r.spoiler && !revealed.contains(r.id) {
                        Button { revealed.insert(r.id) } label: { Label("Tiene spoilers · Leer", systemImage: "eye.slash").recipe(.footnote, color: DS.textMuted) }
                            .buttonStyle(.plain)
                    } else {
                        Text(verbatim: r.text).recipe(.footnote, color: DS.textMuted).lineLimit(4)
                    }
                }
                .padding(DS.Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard(.row)
            }
            if let link { Link(destination: link) { Label("Ver más en Letterboxd", systemImage: "arrow.up.right").recipe(.label) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("letterboxd-public-reviews")
    }
}
