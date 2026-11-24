import SwiftUI
import OrbitalCore
import OrbitalModels

// Cómo se acomoda la barra de la raíz (aparte de RootView.swift por su presupuesto de 600 renglones).

/// La barra de pestañas arriba de entrada en el iPad (DK1); aparte, para que el cuerpo de la raíz compile a tiempo.
struct TabBarFirst: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        if Demo.isOn, Demo.has("-demo-sidebar") { return content.defaultAdaptableTabBarPlacement(.sidebar) }   // la barra lateral abierta (capturas)
        #endif
        return content.defaultAdaptableTabBarPlacement(.tabBar)
    }
}

/// La ficha en la Mac (FI-B): entra por la derecha, cerca de 40 % del ancho, sobre la pantalla oscurecida que sigue ahí.
/// Tocar afuera, la ✕ o Esc la cierran; tocar otro póster la cambia. Adentro, la ficha del iPhone (una columna).
struct SideTitle: ViewModifier {
    @Binding var item: TitleRoute?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.macTabs) private var tabs
    static let space = "side-title"
    func body(content: Content) -> some View {
        // Con la ficha abierta, lo de atrás se ve pero no se toca: tampoco con VoiceOver o el teclado (el toque a «Guardar»
        // le llegaba a «Decide por mí», que estaba detrás). Salvo el renglón de las pestañas: picar Inicio o Explorar cierra
        // la ficha y cambia de pestaña en un solo clic (antes el velo se comía el primero).
        content.accessibilityHidden(item != nil).overlay(alignment: .trailing) {
            if let route = item {
                ZStack(alignment: .trailing) {
                    DS.scrim.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
                    VStack(spacing: 0) {   // ds-exception: el hueco del renglón de pestañas va pegado a lo que cierra la ficha
                        Color.clear.frame(height: tabs?.stripBottom ?? 0).allowsHitTesting(false)
                        Color.clear.contentShape(Rectangle()).onTapGesture { item = nil }
                    }
                    .accessibilityHidden(true)
                    TitlePanel(route: route, close: { item = nil })
                        .frame(width: DS.TitleAction.sidePanelWidth)
                        .background(DS.backdropDeep.ignoresSafeArea())
                        .shadow(DS.Elevation.medium)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .coordinateSpace(.named(Self.space))
        .animation(DS.Motion.spring(reduceMotion), value: item)
        .onChange(of: tabs?.current) { if item != nil { item = nil } }   // otra pestaña: la ficha se cierra
    }
}
