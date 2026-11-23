import SwiftUI
import OrbitalCore
import OrbitalModels

/// MA1 (Fernando, 16 nov 2026): en la Mac, Ajustes es lista y detalle, como Ajustes del Sistema. La lista a la izquierda y la
/// página elegida a la derecha: cambias varias cosas sin ir y volver (antes, una columna angosta al centro con dos tercios
/// vacíos). Lo que se abre desde una página (Probar la velocidad, Lo que recuerda cada título…) se empuja como siempre.
/// AJ-A (22 nov 2026): la lista es una barra lateral angosta (un renglón por página, sin su valor) y la página llena lo
/// demás; igual en el iPad ancho (donde la barra de arriba también va en el renglón del logo). iPhone e iPad angosto, la lista.
extension SettingsView {
    @ViewBuilder func macSplit(_ list: some View, _ model: SettingsModel) -> some View {
        if TopRow.tabsInLogoRow {
            HStack(spacing: 0) {
                list
                    .frame(width: DS.Mac.settingsListWidth)
                    .environment(\.settingsPane, SettingsPane(current: macPage, open: { macPage = $0; macStack = [] }))
                    .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: DS.Stroke.hairline) }
                // MA2: su nombre arriba y, si vino de otra página, «‹» para volver; lo que abre se queda aquí (`PaneLink`).
                VStack(spacing: 0) {
                    SettingsPaneHeader(title: macStack.last?.title ?? macPage.title,
                                       back: macStack.isEmpty ? nil : { macStack.removeLast() })
                    Group {
                        if let top = macStack.last {
                            top.make().id(top.id)
                        } else {
                            destination(macPage, model).id(macPage)   // cada página empieza arriba y con su propio estado
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .environment(\.settingsSubPane, SettingsSubPane { title, make in macStack.append(SettingsSubPage(title: title, make: make)) })
                .environment(\.readableWidth, DS.Mac.settingsPageWidth)   // AJ-A: la página llena el ancho, no una columna de 720
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Backdrop())
            .dsFeedback(.selection, trigger: macPage)
            .dsFeedback(.selection, trigger: macStack.count)
        } else {
            list
        }
    }
}
