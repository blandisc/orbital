import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// Tamaños en bytes y la barra de almacenamiento de Descargas.
/// Un tamaño de archivo con un solo formato en toda la app: GB y TB con un decimal, MB y KB sin decimales
/// («2,4 GB», «350 MB»). Así la leyenda del espacio y las secciones de Descargas dicen lo mismo.
enum ByteSize {
    static func text(_ n: Int64, locale: Locale) -> String {
        let units: [(Double, String)] = [(1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB")]
        let value = Double(max(0, n))
        guard let (size, unit) = units.first(where: { value >= $0.0 }) else { return "0 KB" }
        let digits = size >= 1e9 ? 1 : 0
        return "\((value / size).formatted(.number.precision(.fractionLength(digits)).locale(locale))) \(unit)"
    }
}

/// El espacio del iPhone como en Ajustes › Almacenamiento: una barra con lo de Orbital (series y películas, en su color),
/// lo demás del teléfono en gris y lo libre vacío; abajo, la leyenda. Con poco espacio libre, el dato se pone en ámbar.
struct StorageBar: View {
    struct Part: Identifiable { let id: String; let label: Text; let bytes: Int64; let color: Color }
    let parts: [Part]
    let free: Int64
    let total: Int64
    let format: (Int64) -> String

    var body: some View {
        let others = max(0, total - free - parts.reduce(0) { $0 + $1.bytes })
        let low = total > 0 && Double(free) / Double(total) < DS.Storage.lowFraction
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Espacio").recipe(.cardTitle).fontWeight(.semibold)
                Spacer()
                Text("\(format(free)) libres de \(format(total))").recipe(.footnote, color: low ? DS.warning : DS.textMuted)
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
        ForEach(parts) { part in legend(part.label + Text(verbatim: " \(format(part.bytes))"), color: part.color) }
        legend(Text("Otras apps"), color: DS.textFaint)
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
