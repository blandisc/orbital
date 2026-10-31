import SwiftUI

// Vistas previas de las piezas centrales del catálogo (`Components.swift`): claro, oscuro y letra de accesibilidad.
// Solo para Xcode; no cambian la app.

/// Las piezas sueltas, una debajo de otra, sobre el fondo de la app.
private struct CatalogSample: View {
    @State private var kind = ""
    @State private var segment = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DSSectionHead(title: "Seguir viendo", chevron: true, eyebrow: Text("Lo que dejaste pendiente"))
                DSSectionHead(title: "Descargas", count: 3)
                HStack(spacing: DS.Space.s2) {
                    DSChip(verbatim: "2,1 GB")
                    DSChip(text: "Al instante", tone: .good)
                    DSChip(verbatim: "34 GB", tone: .warn)
                }
                HStack(spacing: DS.Space.s2) {
                    DSBadge(text: "Recomendada")
                    PosterView(url: nil, title: "Nuevo").frame(width: DS.HomeTimeline.width).overlay(alignment: .topLeading) { DSCornerRibbon(text: "Nuevo") }
                    DSIconBadge(symbol: "bookmark.fill", label: "En tu lista")
                    DSRankBadge(rank: 1)
                }
                HStack(spacing: DS.Space.s2) {
                    PlatformBadge(name: "Netflix")
                    PlatformBadge(name: "Disney+", rank: 1)
                    PlatformBadge(name: "Otra", rank: 8)
                }
                DSProgress(fraction: 0.4)
                DSKindFilter(kind: $kind)
                DSSegmented(options: [(0, "Películas"), (1, "Series")], selection: $segment)
                HStack(spacing: DS.Space.s3) {
                    FavoriteButton(isFavorite: false) {}
                    FavoriteButton(isFavorite: true) {}
                }
                RatingStars(value: 3.5) { _ in }
                RatingReminder(title: "Moonlight", poster: nil, more: 2, onRate: { _ in }, onDismiss: {}, onOpenQueue: {})
                HStack(spacing: DS.Space.s3) {
                    DSIconButton(symbol: "plus", label: "Agregar") {}
                    DSIconButton(symbol: "play.fill", label: "Ver", prominent: true) {}
                    DSMoreMenu { Button("Compartir") {} }
                }
                DSNotice(text: "Sin conexión", tone: .warn)
                DSNotice(text: "No se pudo cargar", tone: .error)
                DSNotice(text: "Listo", tone: .success)
                HStack(spacing: DS.Space.s3) {
                    DSSpeedPill()
                    DSToastPill(text: "Llenar", detail: Text(verbatim: "Español · 2 de 7"))
                }
                HStack(spacing: DS.Space.s3) {
                    DSGestureIndicator(symbol: "sun.max.fill", value: 0.6)
                    DSSeekBubble(time: "1:24:10", delta: "+1:20")
                    DSLoader()
                }
            }
            .padding(DS.Space.gutter)
        }
        .background(DS.bg)
    }
}

#Preview("Catálogo · claro") { CatalogSample().preferredColorScheme(.light) }
#Preview("Catálogo · oscuro") { CatalogSample().preferredColorScheme(.dark) }
#Preview("Catálogo · letra grande") { CatalogSample().dynamicTypeSize(.accessibility5) }

#Preview("Vacío · claro") {
    DSEmptyState(symbol: "arrow.down.circle", title: Text("Sin descargas"), message: Text("Lo que bajes para ver sin conexión aparece aquí."))
        .background(DS.bg).preferredColorScheme(.light)
}
#Preview("Vacío · oscuro") {
    DSEmptyState(symbol: "arrow.down.circle", title: Text("Sin descargas"), message: Text("Lo que bajes para ver sin conexión aparece aquí."))
        .background(DS.bg).preferredColorScheme(.dark)
}
#Preview("Vacío · letra grande") {
    DSEmptyState(symbol: "arrow.down.circle", title: Text("Sin descargas"), message: Text("Lo que bajes para ver sin conexión aparece aquí."))
        .background(DS.bg).dynamicTypeSize(.accessibility5)
}
