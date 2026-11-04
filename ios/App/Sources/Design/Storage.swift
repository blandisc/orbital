import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// Los tamaños («2,4 GB») salen de `ByteSize` (OrbitalCore), el mismo formato en toda la app.

/// El espacio del iPhone como en Ajustes › Almacenamiento: una barra con lo de Orbital (series y películas, en su color),
/// lo demás del teléfono en gris y lo libre vacío; abajo, la leyenda. Con poco espacio libre, el dato se pone en ámbar.
struct StorageBar: View {
    struct Part: Identifiable { let id: String; let label: Text; let bytes: Int64; let color: Color }
    let parts: [Part]
    let free: Int64
    let total: Int64
    let format: (Int64) -> String

    /// Lo de Orbital (la suma de sus partes) y lo de las otras apps (lo que no es de Orbital ni está libre).
    private var mine: Int64 { parts.reduce(0) { $0 + $1.bytes } }
    private var others: Int64 { max(0, total - free - mine) }

    var body: some View {
        let low = total > 0 && Double(free) / Double(total) < DS.Storage.lowFraction
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // Arriba, las dos cifras que importan: cuánto usa Orbital y cuánto queda (Fernando, 2 nov 2026, I1). Lo de Orbital
            // casi no se ve en la barra frente a todo el teléfono; dicho con su número, sí.
            HStack(alignment: .firstTextBaseline) {
                Text("Orbital usa \(format(mine))").recipe(.cardTitle)
                Spacer()
                Text("\(format(free)) libres").recipe(.footnote, color: low ? DS.warning : DS.textMuted)
            }
            GeometryReader { geo in
                HStack(spacing: DS.Storage.gap) {
                    ForEach(parts) { part in segment(part.bytes, width: geo.size.width, color: part.color) }
                    segment(others, width: geo.size.width, color: DS.textFaint)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.fill)
                .clipShape(Capsule())
            }
            .frame(height: DS.Storage.height)
            // En renglón; si no cabe (letra grande, iPhone chico), uno debajo del otro: sin «Series…».
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s3) { legends }
                VStack(alignment: .leading, spacing: DS.Space.s1) { legends }
            }
        }
        .padding(.vertical, DS.Space.s1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var legends: some View {
        ForEach(parts) { part in legend(Text("\(part.label)\(Text(verbatim: " \(format(part.bytes))"))"), color: part.color) }
        legend(Text("\(Text("Otras apps"))\(Text(verbatim: " \(format(others))"))"), color: DS.textFaint)
    }

    private func segment(_ bytes: Int64, width: CGFloat, color: Color) -> some View {
        let fraction = total > 0 ? CGFloat(bytes) / CGFloat(total) : 0
        return Rectangle().fill(color).frame(width: bytes > 0 ? max(DS.Storage.minSegment, width * fraction) : 0)
    }

    private func legend(_ text: Text, color: Color) -> some View {
        HStack(spacing: DS.Space.s1) {
            Circle().fill(color).frame(width: DS.Storage.dot, height: DS.Storage.dot)
            text.recipe(.caption, color: DS.textMuted).lineLimit(1)
        }
    }
}

/// El anillo de una descarga con lo que hace al tocarlo (Descargas y la fila de un episodio): bajando, ‖ para pausar; en pausa,
/// la flecha y «Seguir» debajo; si falló, ↻ y «Reintentar». Fernando, 2 nov 2026 (I3): la flecha sola no decía que reanuda.
struct DownloadRingButton: View {
    enum Action { case pause, resume, retry }
    let fraction: Double
    let action: Action
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            VStack(spacing: DS.Space.s1) {
                ZStack {
                    DownloadRing(fraction: fraction, tint: action == .retry ? DS.warning : DS.accent, lineWidth: DS.TitleAction.ringSmallLine)
                    Image(systemName: symbol).font(DS.TextRecipe.badge.font).foregroundStyle(DS.text)
                }
                .frame(width: DS.TitleAction.ringSmall, height: DS.TitleAction.ringSmall)
                if let name { name.recipe(.caption, color: DS.textMuted).lineLimit(1).fixedSize() }
            }
            .frame(minWidth: DS.Size.touchTarget, minHeight: DS.Size.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name ?? Text("Pausar"))
    }

    private var symbol: String {
        switch action { case .pause: "pause.fill"; case .resume: DS.Symbol.resumeDownload; case .retry: "arrow.clockwise" }
    }

    /// El nombre bajo el anillo: solo cuando el ícono no lo dice solo (‖ es pausar en todos lados).
    private var name: Text? {
        switch action { case .pause: nil; case .resume: Text("Seguir"); case .retry: Text("Reintentar") }
    }
}
