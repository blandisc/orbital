import SwiftUI
import OrbitalCore

/// Tus estrellas, como en Trakt: 5 con medias (en Trakt, 1…10). Se toca o se arrastra de lado: la mitad izquierda de una
/// estrella es media. Volver a TOCAR tu misma calificación la quita (arrastrar y volver al mismo punto no). El arrastre va a
/// la par del desplazamiento y solo cuenta si es de lado: empezar sobre las estrellas para bajar la ficha sí la baja.
/// Con VoiceOver se ajusta de media en media.
struct RatingStars: View {
    let value: Double?
    var size: CGFloat = DS.Rating.star
    let onChange: (Double?) -> Void
    @State private var dragging: Double?
    /// La dirección del arrastre se decide una vez, al empezar: de lado mueve las estrellas; vertical es el scroll hasta soltar.
    @State private var sideways: Bool?

    var body: some View {
        let shown = dragging ?? value ?? 0
        HStack(spacing: DS.Rating.gap) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Self.symbol(for: i, shown))
                    .font(.system(size: size))   // ds-exception: el tamaño de la estrella sale del token DS.Rating
                    .foregroundStyle(shown >= Double(i) - 0.5 ? DS.Rating.filled : DS.Rating.empty)
            }
        }
        .contentShape(Rectangle())
        .overlay {
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .gesture(tap(width: geo.size.width))
                    .simultaneousGesture(drag(width: geo.size.width))
            }
        }
        .sensoryFeedback(.selection, trigger: dragging) { old, new in old != nil && new != nil && old != new }
        .accessibilityElement()
        .accessibilityLabel(Text("Tu calificación"))
        .accessibilityValue(value.map { Text("\($0.formatted()) de 5 estrellas") } ?? Text("Sin calificar"))
        .accessibilityAdjustableAction { direction in
            let now = value ?? 0
            switch direction {
            case .increment: onChange(min(5, now + 0.5))
            case .decrement: onChange(now <= 0.5 ? nil : now - 0.5)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("rating-stars")
    }

    private func at(_ x: CGFloat, _ width: CGFloat) -> Double { RatingScale.snap(Double(x / max(1, width)) * 5) }

    private func tap(width: CGFloat) -> some Gesture {
        SpatialTapGesture().onEnded { g in
            let picked = at(g.location.x, width)
            onChange(picked == value ? nil : picked)
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: DS.Rating.dragStart)
            .onChanged { g in
                if sideways == nil { sideways = abs(g.translation.width) > abs(g.translation.height) }
                guard sideways == true else { return }   // vertical: es el scroll de la ficha
                dragging = at(g.location.x, width)
            }
            .onEnded { g in
                defer { sideways = nil; dragging = nil }
                guard sideways == true else { return }
                onChange(at(g.location.x, width))
            }
    }

    static func symbol(for star: Int, _ value: Double) -> String {
        let i = Double(star)
        if value >= i { return "star.fill" }
        if value >= i - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// El recordatorio de calificar: una pastilla de vidrio sobre la barra de pestañas con el póster, «¿Qué tal …?» y las
/// estrellas en línea (calificas sin abrir nada). «y 2 más» abre la fila completa; la ✕ es «no calificar esta».
struct RatingReminder: View {
    let title: String
    let poster: URL?
    let more: Int
    let onRate: (Double) -> Void
    let onDismiss: () -> Void
    let onOpenQueue: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            posterThumb
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("¿Qué tal \(title)?").recipe(.footnote).fontWeight(.semibold).lineLimit(1)
                RatingStars(value: nil, size: DS.Rating.starInline) { if let v = $0 { onRate(v) } }
            }
            .layoutPriority(1)   // el título gana el espacio: «y 2 más» y la ✕ son chicos
            Spacer(minLength: 0)
            if more > 0 {
                Button(action: onOpenQueue) { Text("y \(more) más").recipe(.caption, color: DS.textMuted) }
                    .accessibilityIdentifier("rating-reminder-more")
            }
            Button(action: onDismiss) { Image(systemName: "xmark").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted) }
                .accessibilityLabel(Text("No calificar esta"))
                .accessibilityIdentifier("rating-reminder-dismiss")
        }
        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rating-reminder")
    }

    @ViewBuilder private var posterThumb: some View {
        Group {
            if let poster {
                RemoteImage(url: poster, maxPoints: DS.Rating.poster) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { DS.fill }
                }
            } else { DS.fill }
        }
        .frame(width: DS.Rating.poster, height: DS.Rating.poster * DS.Rating.posterAspect)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))
        .accessibilityHidden(true)
    }
}

/// La fila completa de lo que te falta calificar (desde «y 2 más»): un renglón por título con sus estrellas.
struct RatingQueue: View {
    struct Row: Identifiable { let id: String; let title: String; let poster: URL? }
    let rows: [Row]
    let onRate: (String, Double) -> Void
    let onDismiss: (String) -> Void

    var body: some View {
        List(rows) { row in
            HStack(spacing: DS.Space.s3) {
                Text(row.title).recipe(.body).lineLimit(2)
                Spacer(minLength: DS.Space.s2)
                RatingStars(value: nil, size: DS.Rating.starInline) { if let v = $0 { onRate(row.id, v) } }
            }
            .swipeActions { Button("No calificar", role: .destructive) { onDismiss(row.id) } }
        }
        .overlay { if rows.isEmpty { ContentUnavailableView("Nada por calificar", systemImage: "star") } }
        .navigationTitle("Por calificar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
