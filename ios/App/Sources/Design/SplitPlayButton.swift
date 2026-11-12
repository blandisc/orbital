import SwiftUI
import OrbitalCore

/// El botón principal de la ficha, partido (L3, Fernando, 11 nov 2026: «Vamos L3»): a la izquierda (la mayor) reproduce; a la
/// derecha, más angosta, la versión que va a sonar («🇲🇽 1080p ⌄») abre «Versión». Es el único lugar de la ficha donde se
/// elige idioma y calidad: no hay renglón de versión aparte (docs/ios-interfaz.md § «La versión vive en el botón»;
/// `DesignRulesTests.testVersionLivesInThePlayButton`).
///
/// Una sola forma con una división fina; cada lado es un botón nativo con su propia pulsación (se hunde solo el que tocas).
/// Si el nombre de «Ver» no cabe en un renglón (iPhone SE, letra grande), la derecha se queda con la bandera y la flechita: el
/// nombre de «Ver» nunca se corta. Mientras se busca la versión, la derecha va en gris con la forma y el ancho que tendrá
/// (`VersionSummary.searching`): el botón no cambia de ancho cuando llega. Aire parejo: cada lado centra su contenido en el
/// alto del botón (los dos miden lo mismo) y la división deja el mismo aire arriba que abajo (`DS.SplitPlay`).
struct SplitPlayButton<Title: View>: View {
    let title: Title
    let version: VersionSummary
    let enabled: Bool
    let play: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(version.compact)
            row(version.mark)
        }
    }

    private func row(_ shown: Text) -> some View {
        HStack(spacing: 0) {
            Button(action: play) { title.frame(maxHeight: .infinity) }
                .dsSolidPrimaryButton(shape: .roundedRectangle(radius: .zero)).disabled(!enabled)
                .accessibilityIdentifier("title-play")
                .coachAnchor("title-play")   // F3: el aviso con foco de la ficha señala este lado
            Button(action: version.open) {
                HStack(spacing: DS.SplitPlay.gap) {
                    shown.font(DS.TextRecipe.label.font).lineLimit(1)
                    Image(systemName: "chevron.down").font(DS.TextRecipe.caption.font).accessibilityHidden(true)
                }
                .fixedSize()
                // Mientras se busca: la letra invisible ocupa su ancho y encima va una placa gris del mismo tamaño
                // (`.redacted` dibujaba la bandera más angosta y el botón brincaba al llegar la versión).
                .opacity(version.searching ? 0 : 1)
                .overlay { if version.searching { placeholder } }
                .frame(minWidth: DS.Size.touchTarget, maxHeight: .infinity)
            }
            // Mientras se busca no se apaga (apagado, el sistema la pintaba de otro gris): el toque no hace nada todavía.
            // Los dos lados se apagan juntos: uno gris y otro blanco se ve roto (regla «Un botón, un estado»).
            .dsSolidPrimaryButton(shape: .roundedRectangle(radius: .zero)).disabled(!enabled)
            .accessibilityLabel(version.accessibilityLabel)
            .accessibilityIdentifier("title-sources")
            .overlay(alignment: .leading) { divider }
        }
        .fixedSize(horizontal: false, vertical: true)   // los dos lados, del mismo alto
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    /// El esqueleto de la zona derecha mientras se busca: una placa gris del alto de la letra.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: DS.Radius.tag, style: .continuous)
            .fill(DS.onSolidPrimary.opacity(DS.SplitPlay.dividerOpacity))
            .accessibilityHidden(true)
    }

    /// La división: fina, del color de la letra del botón, con el mismo aire arriba que abajo.
    private var divider: some View {
        Rectangle().fill(DS.onSolidPrimary.opacity(DS.SplitPlay.dividerOpacity))
            .frame(width: DS.SplitPlay.divider)
            .padding(.vertical, DS.SplitPlay.dividerInset)
            .accessibilityHidden(true)
    }
}

/// La versión que va a sonar, ya armada por la ficha (`TitleView.playVersion`).
struct VersionSummary {
    /// «🇲🇽 1080p»: la bandera (la mitad España, mitad México, dibujada) y la resolución.
    let compact: Text
    /// Lo mínimo que la identifica (la bandera; sin bandera conocida, el idioma): cuando no cabe más.
    let mark: Text
    /// «Español, 1080p», sin banderas: VoiceOver dice «Versión: Español, 1080p. Cambiar».
    let spoken: String
    /// Aún buscando la versión: la letra de la zona en gris con su forma (el toque no hace nada todavía).
    var searching = false
    let open: () -> Void

    var accessibilityLabel: Text { searching ? Text("Buscando versión") : Text("Versión: \(spoken). Cambiar") }

    /// Mientras se busca: el mismo ancho que tendrá la más común (la bandera de español y «1080p»), en gris.
    static var searchingPlaceholder: VersionSummary {
        VersionSummary(compact: Text.withFlagImages(LanguageFlags.mixedSpanish + " 1080p"), mark: Text.withFlagImages(LanguageFlags.mixedSpanish),
                       spoken: "", searching: true, open: {})
    }
}
