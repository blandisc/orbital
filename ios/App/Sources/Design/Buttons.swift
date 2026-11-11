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

    /// El botón principal chico (Listo, Usar, Cambiar): el mismo vidrio con el tinte de Orbital, en tamaño chico.
    func dsPrimaryButton(size: ControlSize) -> some View {
        buttonStyle(.glassProminent).controlSize(size).tint(DS.primary).foregroundStyle(DS.onPrimary)
    }

    /// El botón principal de un título con arte (Ver, Continuar): toma el color claro del arte, con texto oscuro, como
    /// `--color-primary-art` en la TV. Sin colores, el neutro casi papel de la TV.
    func dsArtButton(_ colors: ArtColors?) -> some View { modifier(ArtButton(colors: colors)) }

    /// El botón principal sólido: negro en claro y blanco en oscuro (`DS.solidPrimary`). A todo lo ancho (Ver, Continuar, Ver
    /// resultados, Ver tu Wrapped) con esquinas de tarjeta; `shape: .circle` para el principal de una fila de íconos (el ▶
    /// del mazo). El nativo `.borderedProminent` con otro tinte: sin estilo propio.
    func dsSolidPrimaryButton(shape: ButtonBorderShape = .roundedRectangle(radius: DS.Radius.lg)) -> some View {
        buttonStyle(.borderedProminent).buttonBorderShape(shape)
            .tint(DS.solidPrimary).foregroundStyle(DS.onSolidPrimary)
    }

    /// El botón secundario: con borde, en cápsula y del color del texto (Corregir, Más recientes, Desde el principio). Uno solo
    /// en toda la app; el tamaño lo pone `controlSize`.
    func dsSecondaryButton() -> some View {
        buttonStyle(.bordered).buttonBorderShape(.capsule).tint(DS.text)
    }

    /// El botón de vidrio sin tinte (Reintentar, Conectar, una acción junto a un aviso): el secundario sobre arte o sobre una
    /// superficie de vidrio. Antes cada pantalla escribía `.buttonStyle(.glass)`.
    func dsGlassButton() -> some View { buttonStyle(.glass) }

    /// Los botones dentro de un aviso pintado en el papel sólido (`DS.solidPrimary`: «¿Van a tiempo los subtítulos?»): el
    /// principal, lleno del color de la letra del aviso; el otro, con su relleno tenue. En cápsula y a tamaño de dedo. Antes
    /// cada aviso los pintaba a mano (D9).
    func dsOnSolidButton(primary: Bool) -> some View { modifier(OnSolidButton(primary: primary)) }
}

private struct OnSolidButton: ViewModifier {
    let primary: Bool
    func body(content: Content) -> some View {
        Group {
            if primary { content.buttonStyle(.borderedProminent).tint(DS.onSolidPrimary).foregroundStyle(DS.solidPrimary) }
            else { content.buttonStyle(.bordered).tint(DS.onSolidPrimary) }
        }
        .buttonBorderShape(.capsule).controlSize(.large)
    }
}

/// Botones sólidos (sin vidrio) donde el vidrio no se lleva bien (lo que se gira o se deforma en 3D).
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

/// Un botón redondo con un ícono (más, descargar, cerrar): el botón nativo con vidrio de iOS 26. El único círculo de vidrio
/// de la app (D7): cerrar una hoja, el ✕ y el ♥ del mazo, una flecha. Tres tamaños: `small` (junto a un texto chico),
/// `regular` (cerrar una hoja) y `large` (lo de siempre, 44 pt táctiles); el ícono crece con él.
struct DSIconButton: View {
    enum Size {
        case small, regular, large
        var control: ControlSize { switch self { case .small: .small; case .regular: .regular; case .large: .large } }
    }
    let symbol: String
    let label: LocalizedStringKey
    var prominent = false
    var size: Size = .large
    let action: () -> Void

    /// Un dibujo del catálogo en vez de un símbolo (la dona de «Un Simpson al azar»), con sus colores.
    var asset: String?

    init(symbol: String, label: LocalizedStringKey, prominent: Bool = false, size: Size = .large, action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.prominent = prominent; self.size = size; self.action = action
    }

    init(asset: String, label: LocalizedStringKey, size: Size = .large, action: @escaping () -> Void) {
        self.init(symbol: "", label: label, size: size, action: action)
        self.asset = asset
    }

    private var glyph: Image { asset.map { Image($0).renderingMode(.original) } ?? Image(systemName: symbol) }

    var body: some View {
        Group {
            if prominent { Button(action: action) { glyph }.dsPrimaryButton() }
            else { Button(action: action) { glyph }.dsIconButtonLook() }
        }
        .buttonBorderShape(.circle).controlSize(size.control)
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
        .dsFeedback(.selection, trigger: asking)
        .task(id: asking) {
            guard asking else { return }
            try? await Task.sleep(nanoseconds: DS.Timing.confirm)
            withAnimation(DS.Motion.base(reduceMotion)) { asking = false }
        }
    }
}

/// Todo interruptor de la app (Fernando, 2 nov 2026, J3): prendido en el turquesa de la marca (`DS.switchOn`), apagado en el
/// gris del sistema. Se pone una vez arriba (`OrbitalApp`) y llega a todas las pantallas y hojas: así ningún interruptor
/// hereda el tinte de la app (casi blanco, con la bolita blanca no se notaba si estaba prendido) ni trae un verde suelto.
/// `Toggle(configuration)` respeta el estilo de su lugar (en un menú sigue siendo palomita; `.button` sigue siendo botón).
struct DSSwitchStyle: ToggleStyle {   // ds-exception: no dibuja nada propio, es el interruptor nativo con el tinte de la marca
    func makeBody(configuration: Configuration) -> some View { Toggle(configuration).tint(DS.switchOn) }
}

extension ToggleStyle where Self == DSSwitchStyle {
    static var orbital: DSSwitchStyle { DSSwitchStyle() }
}

/// Un interruptor con nombre corto y, si hace falta, su explicación abajo en gris (Fernando, 2 nov 2026, J2: «Bajar el
/// siguiente episodio» y abajo «Cuando acabas de ver uno», en vez de un nombre largo que se parte en dos renglones). El ícono,
/// opcional, como en los renglones de Ajustes.
struct DSToggleRow: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    var symbol: String?
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, symbol: String? = nil, isOn: Binding<Bool>) {
        self.title = title; self.detail = detail; self.symbol = symbol; _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            if let symbol {
                Label { text } icon: { Image(systemName: symbol) }
            } else { text }
        }
    }

    @ViewBuilder private var text: some View {
        VStack(alignment: .leading, spacing: 0) {   // como el subtítulo de un renglón del sistema
            Text(title).foregroundStyle(DS.text)
            if let detail { Text(detail).recipe(.footnote, color: DS.textMuted) }
        }
    }
}
