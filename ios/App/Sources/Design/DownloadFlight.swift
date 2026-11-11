import SwiftUI

/// N1 (Fernando, 8 nov): al empezar una descarga, el póster se desprende, crece un instante («lo tomé»), viaja en curva a la
/// pestaña Biblioteca y se encoge; al llegar, una vibración suave y la marca de la pestaña sube. Con «Reducir movimiento» no
/// vuela: queda el aviso. https://claude.ai/artifact/S9FYxRhx7dzFDDEvE9ddB7
struct DownloadFlight: Equatable {
    let id = UUID()
    var poster: String?
}

struct DownloadFlightLayer: View {
    let flight: DownloadFlight?
    @State private var shown: DownloadFlight?
    @State private var arrived = false
    @State private var landed = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            if let shown, let url = shown.poster.flatMap(URL.init(string:)) {
                let start = CGPoint(x: geo.size.width / 2, y: geo.size.height * DS.Flight.startShare)
                let end = Self.libraryTab(in: geo.size)
                RemoteImage(url: url, maxPoints: DS.Flight.poster) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { DS.fillStrong }
                }
                .frame(width: DS.Flight.poster, height: DS.Flight.poster / DS.Poster.aspect)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .shadow(DS.Elevation.floating.color(DS.scrimStrong))
                .scaleEffect(arrived ? DS.Flight.endScale : DS.Flight.grabScale)
                .opacity(arrived ? 0 : 1)
                .position(arrived ? end : start)
                .id(shown.id)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .dsFeedback(.impact(flexibility: .soft), trigger: landed)
        .onChange(of: flight) { _, new in
            guard let new, !reduceMotion, new.poster != nil else { return }
            arrived = false; shown = new
            Task {
                try? await Task.sleep(for: DS.Flight.grab)
                withAnimation(DS.Flight.curve) { arrived = true }
                try? await Task.sleep(for: DS.Flight.travel)
                landed += 1
                if shown?.id == new.id { shown = nil }
            }
        }
    }

    /// Dónde queda la pestaña Biblioteca: la tercera de las tres de la cápsula izquierda (Buscar va aparte, a la derecha).
    static func libraryTab(in size: CGSize) -> CGPoint {
        let left = DS.Flight.tabInset, right = size.width - DS.Flight.searchReserve
        return CGPoint(x: left + (right - left) * DS.Flight.libraryShare, y: size.height - DS.Flight.tabFromBottom)
    }
}
