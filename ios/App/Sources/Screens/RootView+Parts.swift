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
    func body(content: Content) -> some View {
        // Con la ficha abierta, lo de atrás se ve pero no se toca: tampoco con VoiceOver o el teclado (el toque a «Guardar»
        // le llegaba a «Decide por mí», que estaba detrás).
        content.accessibilityHidden(item != nil).overlay(alignment: .trailing) {
            if let route = item {
                ZStack(alignment: .trailing) {
                    DS.scrim.ignoresSafeArea().onTapGesture { item = nil }.accessibilityHidden(true)
                    TitlePanel(route: route, close: { item = nil })
                        .frame(width: DS.TitleAction.sidePanelWidth)
                        .background(DS.backdropDeep.ignoresSafeArea())
                        .shadow(DS.Elevation.medium)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .animation(DS.Motion.spring(reduceMotion), value: item)
    }
}
