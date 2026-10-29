import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// Botones del catálogo: sobre arte, de ícono, el menú «Más» y el botón que pide confirmar.
extension View {
    /// El botón principal: vidrio nativo con el tinte de Orbital (papel) y la letra oscura encima. Sin esto, iOS pone letra
    /// blanca sobre el tinte claro y no se lee.
    func dsPrimaryButton() -> some View { buttonStyle(.glassProminent).foregroundStyle(DS.onPrimary) }

    /// El botón principal de un título con arte (Ver, Continuar): toma el color claro del arte, con texto oscuro, como
    /// `--color-primary-art` en la TV. Sin colores, el neutro casi papel de la TV.
    func dsArtButton(_ colors: ArtColors?) -> some View { modifier(ArtButton(colors: colors)) }

    /// El botón principal de la ficha: sólido, a todo lo ancho, negro en claro y blanco en oscuro (`DS.solidPrimary`), con
    /// esquinas de tarjeta. El nativo `.borderedProminent` con otro tinte: sin estilo propio.
    func dsSolidPrimaryButton() -> some View {
        buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: DS.Radius.lg))
            .tint(DS.solidPrimary).foregroundStyle(DS.onSolidPrimary)
    }
}

/// Botones sólidos (sin vidrio) en lo que se gira en 3D: el carrusel de Inicio en coverflow deformaba el vidrio.
private struct SolidButtonsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var solidButtons: Bool {
        get { self[SolidButtonsKey.self] }
        set { self[SolidButtonsKey.self] = newValue }
    }
}

private struct ArtButton: ViewModifier {
    let colors: ArtColors?
    func body(content: Content) -> some View {
        // Sólido siempre: el vidrio dejaba pasar el arte y el botón se veía deslavado (texto oscuro sobre un tono pálido y
        // translúcido). Lleno, el color del arte con el texto oscuro guarda el contraste mínimo.
        content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint((colors ?? .neutral).accent).foregroundStyle(DS.backdropDeep)
    }
}

/// El botón de ícono secundario: de vidrio; sólido donde el vidrio no se lleva bien (`solidButtons`).
private struct IconButtonLook: ViewModifier {
    @Environment(\.solidButtons) private var solid
    func body(content: Content) -> some View {
        if solid { content.buttonStyle(.bordered).tint(DS.paper) } else { content.buttonStyle(.glass) }
    }
}

extension View {
    func dsIconButtonLook() -> some View { modifier(IconButtonLook()) }
}

/// «Más»: el mismo menú en toda la app, un círculo con «…» (vidrio; sólido donde el vidrio no se lleva bien). Antes había cuatro
/// (con texto, borde, otro ícono…).
struct DSMoreMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu { content() } label: { Image(systemName: "ellipsis") }
            .dsIconButtonLook().buttonBorderShape(.circle).controlSize(.large)
            .accessibilityLabel(Text("Más"))
    }
}

/// Un botón redondo con un ícono (más, descargar, cerrar): el botón nativo con vidrio de iOS 26, ya con su tamaño táctil de 44 pt.
struct DSIconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var prominent = false
    let action: () -> Void

    var body: some View {
        Group {
            if prominent { Button(action: action) { Image(systemName: symbol) }.dsPrimaryButton() }
            else { Button(action: action) { Image(systemName: symbol) }.dsIconButtonLook() }
        }
        .buttonBorderShape(.circle).controlSize(.large)
        .accessibilityLabel(Text(label))
    }
}

/// Un botón de ícono que pide confirmación: el primer toque lo abre en una cápsula que dice qué hará («¿Ver en la TV?»),
/// el segundo lo hace; si no lo tocas otra vez, se cierra solo.
struct ConfirmIconButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let symbol: String
    let prompt: LocalizedStringKey
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var asking = false

    var body: some View {
        Button {
            if asking { asking = false; action() } else { withAnimation(DS.Motion.base(reduceMotion)) { asking = true } }
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: symbol)
                if asking { Text(prompt).lineLimit(1).fixedSize().transition(.opacity.combined(with: .move(edge: .leading))) }
            }
        }
        .dsIconButtonLook()
        .buttonBorderShape(asking ? .capsule : .circle).controlSize(.large)
        .accessibilityLabel(Text(label))
        .accessibilityHint(asking ? Text("Toca otra vez para confirmar") : Text(prompt))
        .sensoryFeedback(.selection, trigger: asking)
        .task(id: asking) {
            guard asking else { return }
            try? await Task.sleep(nanoseconds: DS.Timing.confirm)
            withAnimation(DS.Motion.base(reduceMotion)) { asking = false }
        }
    }
}
