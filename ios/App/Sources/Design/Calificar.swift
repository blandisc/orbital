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
    /// Al calificar con un toque, las estrellas se llenan en onda hasta la que tocaste (cada una crece un instante, una tras
    /// otra) con un toque en la mano por estrella. Al arrastrar no: ahí cada paso ya vibra.
    @State private var wave = 0
    @State private var tick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = dragging ?? value ?? 0
        HStack(spacing: DS.Rating.gap) {
            ForEach(1...5, id: \.self) { i in star(i, shown: shown) }
        }
        .onChange(of: value) { old, new in startWave(from: old, to: new) }
        .dsFeedback(.impact(flexibility: .soft, intensity: DS.Rating.waveIntensity), trigger: tick)
        .contentShape(Rectangle())
        .overlay {
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .gesture(tap(width: geo.size.width))
                    .simultaneousGesture(drag(width: geo.size.width))
            }
        }
        .dsFeedback(.selection, trigger: dragging) { (old: Double?, new: Double?) -> Bool in old != nil && new != nil && old != new }
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

    /// Calificaste más alto con un toque: la onda y un toque en la mano por estrella (con «Reducir movimiento», uno solo).
    private func startWave(from old: Double?, to new: Double?) {
        guard dragging == nil, let new, new > (old ?? 0) else { return }
        if reduceMotion { tick += 1; return }
        wave += 1
        let stars = Int(new.rounded(.up))
        let step = Duration.seconds(DS.Rating.waveStep)
        Task { @MainActor in
            for _ in 0..<stars {
                tick += 1
                try? await Task.sleep(for: step)
            }
        }
    }

    /// Una estrella; en la onda, la llena crece un instante, `i` pasos después de la primera.
    private func star(_ i: Int, shown: Double) -> some View {
        let filled = shown >= Double(i) - 0.5
        let wait = Double(i - 1) * DS.Rating.waveStep
        return Image(systemName: Self.symbol(for: i, shown))
            .font(.system(size: size))   // ds-exception: el tamaño de la estrella sale del token DS.Rating
            .foregroundStyle(filled ? DS.Rating.filled : DS.Rating.empty)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: wave) { view, scale in
                view.scaleEffect(filled ? scale : 1)
            } keyframes: { _ in
                LinearKeyframe(CGFloat(1), duration: wait)
                SpringKeyframe(DS.Rating.wavePop, duration: DesignTokens.Motion.fast)
                SpringKeyframe(CGFloat(1), duration: DesignTokens.Motion.slow)
            }
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
    /// Lo que tocaste: las estrellas se quedan llenas y dice «Guardada» un momento antes de irse (Fernando, 6 nov: «se cerró
    /// inmediatamente y no supe si lo registró»).
    @State private var rated: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            posterThumb
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("¿Qué tal \(title)?").recipe(.label, color: DS.text).lineLimit(1)
                HStack(spacing: DS.Space.s2) {
                    RatingStars(value: rated, size: DS.Rating.starInline) { v in
                        guard let v, rated == nil else { return }
                        rated = v
                        Task { try? await Task.sleep(for: DS.Rating.savedHold); onRate(v) }
                    }
                    if rated != nil {
                        Label("Guardada", systemImage: "checkmark").recipe(.caption, color: DS.textMuted).labelStyle(.titleAndIcon)
                            .transition(.opacity)
                    }
                }
                .animation(DS.Motion.base(reduceMotion), value: rated)
            }
            .layoutPriority(1)   // el título gana el espacio: «y 2 más» y la ✕ son chicos
            Spacer(minLength: 0)
            if more > 0 {
                Button(action: onOpenQueue) { Text("y \(more) más").recipe(.caption, color: DS.textMuted).lineLimit(1).fixedSize() }   // nunca letra por letra
                    .accessibilityIdentifier("rating-reminder-more")
            }
            DSIconButton(symbol: "xmark", label: "No calificar esta", size: .small, action: onDismiss)
                .accessibilityIdentifier("rating-reminder-dismiss")
        }
        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
        // El vidrio de la barra de pestañas: el mismo material, interactivo como ella y con su mismo velo claro (sin él, sobre el
        // fondo oscuro se veía más gris que la barra y que «Viendo en la TV»).
        .glassEffect(.regular.tint(DS.Rating.glassTint).interactive(), in: Capsule())
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
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// La fila completa de lo que te falta calificar (desde «y 2 más»): un renglón por título con sus estrellas.
struct RatingQueue: View {
    @Environment(\.titleName) var titleName
    struct Row: Identifiable { let id: String; let title: String; let poster: URL? }
    let rows: [Row]
    let onRate: (String, Double) -> Void
    let onDismiss: (String) -> Void

    var body: some View {
        List(rows) { row in
            HStack(spacing: DS.Space.s3) {
                Text(verbatim: titleName(row.title, id: row.id)).recipe(.body).lineLimit(2)
                Spacer(minLength: DS.Space.s2)
                RatingStars(value: nil, size: DS.Rating.starInline) { if let v = $0 { onRate(row.id, v) } }
            }
            .swipeActions { Button("No calificar", role: .destructive) { onDismiss(row.id) } }
        }
        .overlay { if rows.isEmpty { DSEmptyState(symbol: "star", title: Text("Nada por calificar")) } }
        .navigationTitle("Por calificar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
