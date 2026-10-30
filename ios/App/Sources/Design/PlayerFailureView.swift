import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas del reproductor: los botones con nombre, «Audio y subtítulos» (`SubtitleDock`) y sus partes.

/// Cuando el video no abre: cada caso con su pantalla y sus salidas.

/// Cuando el reproductor no puede: una pantalla propia (no un aviso rojo encima de los controles), con lo que pasó dicho
/// desde tu lado y solo las salidas que sirven en ese caso.
struct PlayerFailureView: View {
    let failure: PlayerModel.Failure
    /// Un episodio (no una película): para decir «este episodio».
    let isEpisode: Bool
    let retry: () -> Void
    let infuse: (() -> Void)?
    /// Hay otras versiones: elegir una ahí mismo (antes había que cerrar y volver a abrir).
    var chooseVersion: (() -> Void)? = nil
    /// ¿El iPhone tiene internet? Con red, «no pude pedir las fuentes» es que tus complementos no contestaron (antes decía
    /// «Sin conexión» igual).
    var online = true
    /// Sin internet, lo que sí se puede ver: tus descargas.
    var openDownloads: (() -> Void)? = nil
    let close: () -> Void

    var body: some View {
        // En vertical, todo en una columna; en horizontal (poco alto) no cabían los tres botones bajo el texto y el último
        // quedaba cortado: ahí el texto va a la izquierda y las salidas a la derecha.
        GeometryReader { geo in
            // `ViewThatFits` daba por bueno el renglón vertical (el texto se puede comprimir) y los botones se cortaban abajo:
            // se decide por la forma de la pantalla.
            let wide = geo.size.width > geo.size.height
            Group {
                if wide { HStack(spacing: DS.Space.s8) { info; options } }
                else { VStack(spacing: DS.Space.s4) { info; options } }
            }
            .padding(DS.Space.gutter)
            .frame(width: geo.size.width, height: geo.size.height)
            // Si ni así cabe (letra muy grande), se desliza en vez de cortar el texto.
            .modifier(ScrollIfNeeded())
        }
        .background(DS.backdropDeep.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }

    /// El ícono y lo que pasó, dicho desde tu lado.
    private var info: some View {
        VStack(spacing: DS.Space.s4) {
            Image(systemName: symbol).font(DS.TextRecipe.display.font).foregroundStyle(DS.textMuted)
            VStack(spacing: DS.Space.s2) {
                title.recipe(.section).multilineTextAlignment(.center)
                message.recipe(.secondary, color: DS.textMuted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: DS.Size.cardMax)
        }
    }

    /// Solo las salidas que sirven en ese caso.
    private var options: some View {
        VStack(spacing: DS.Space.s2) {
            switch failure {
            case .noSources, .localFile:
                option(Text("Cerrar"), primary: true, action: close)
            case .network:
                option(Text("Reintentar"), primary: true, action: retry)
                if !online, let openDownloads { option(Text("Ver tus descargas"), primary: false, action: openDownloads) }
                option(Text("Cerrar"), primary: false, action: close)
            case .noneWorked, .sourceDied:
                option(Text("Reintentar"), primary: true, action: retry)
                if let chooseVersion { option(Text("Elegir otra versión"), primary: false, action: chooseVersion) }
                if let infuse { option(Text("Abrir en Infuse"), primary: false, action: infuse) }
                option(Text("Cerrar"), primary: false, action: close)
            }
        }
        .frame(maxWidth: DS.Size.cardMax)
    }

    private var symbol: String {
        switch failure {
        case .noSources: "film.stack"
        case .noneWorked, .sourceDied: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .network: online ? "exclamationmark.icloud" : "wifi.slash"
        case .localFile: "externaldrive.badge.exclamationmark"
        }
    }

    private var title: Text {
        switch failure {
        case .noSources: Text("Todavía no hay dónde verlo")
        case .noneWorked: Text("No pude reproducirlo")
        case .sourceDied: Text("Se cortó el video")
        case .network: online ? Text("Tus complementos no contestan") : Text("Sin conexión")
        case .localFile: Text("No se puede abrir la descarga")
        }
    }

    private var message: Text {
        switch failure {
        case .noSources: isEpisode ? Text("Real-Debrid aún no tiene este episodio. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.")
            : Text("Real-Debrid aún no tiene esta película. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.")
        case .noneWorked: Text("Probamos las versiones que hay y ninguna respondió. A veces es momentáneo.")
        case .sourceDied: Text("La versión dejó de responder. Al intentar de nuevo seguimos donde ibas, con otra si hace falta.")
        case .network: online ? Text("Hay internet, pero ninguno respondió. Suele ser momentáneo; intenta de nuevo en un rato.")
            : Text("Revisa tu conexión a internet e intenta de nuevo. Lo que descargaste sí se puede ver.")
        case .localFile: Text("El archivo descargado no se puede leer. Bórralo en Descargas y bájalo otra vez.")
        }
    }

    private func option(_ label: Text, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(primary ? DS.onPrimary : DS.text)
                .frame(maxWidth: .infinity, minHeight: DS.Remote.keyHeight)
                .background(primary ? DS.primary : DS.fillStrong, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
