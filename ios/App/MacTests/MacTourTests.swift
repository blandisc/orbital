import XCTest
import SwiftUI
import UIKit
@testable import Orbital

/// Recorrido de la Mac («Diseñada para iPad»), sin manos. Xcode no corre pruebas de interfaz (XCUITest) en la Mac con una app
/// de iPad («UI tests are not supported on My Mac (Designed for iPad)»), pero sí pruebas dentro de la app: esta corre adentro de
/// Orbital abierta en modo demostración (el esquema `OrbitalMac` le pasa `-demo`), cambia el tamaño de la ventana, va de
/// pantalla en pantalla por los mismos caminos que usan la barra de menús y los enlaces, y guarda una captura de la ventana en
/// cada paso, en la carpeta temporal de la app (la ruta sale en la bitácora como `MAC-TOUR folder`).
///
///   xcodebuild test -scheme OrbitalMac -destination 'platform=macOS,arch=arm64,variant=Designed for iPad' \
///     -derivedDataPath /tmp/dd-orbital-ipad -allowProvisioningUpdates
///
/// Necesita la sesión de la Mac **desbloqueada**: con la pantalla bloqueada macOS deja la app de iPad suspendida antes de
/// arrancar (RunningBoard: «running-suspended-NotVisible») y la prueba no avanza (10 nov 2026). En el iPad y el iPhone no corre.
@MainActor
final class MacTourTests: XCTestCase {
    private var folder: URL { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mac-tour") }
    private var env: AppEnvironment { AppEnvironment.shared }

    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.isiOSAppOnMac, "solo en la Mac")
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        print("MAC-TOUR folder \(folder.path)")
        for _ in 0..<60 where window == nil { await wait(0.5) }
        await wait(5)   // la portada y los pósters de la demo
    }

    private var window: UIWindow? { AppWindows.all.first(where: \.isKeyWindow) ?? AppWindows.all.first }

    private func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    /// La ventana tal como se ve (con lo que esté encima: hojas, avisos).
    private func shot(_ name: String) {
        guard let window else { return XCTFail("sin ventana para \(name)") }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try? image.pngData()?.write(to: folder.appendingPathComponent("\(name).png"))
        print("MAC-TOUR shot \(name) \(Int(window.bounds.width))x\(Int(window.bounds.height))")
    }

    /// Fija la ventana a ese tamaño (en la Mac, `sizeRestrictions` con mínimo = máximo) y la deja libre otra vez.
    private func resize(_ size: CGSize, settle: Double = 1.5) async {
        guard let limits = AppWindows.scene?.sizeRestrictions else { return XCTFail("sin escena") }
        limits.minimumSize = size
        limits.maximumSize = size
        await wait(settle)
        limits.minimumSize = WindowMetrics.minimum
        limits.maximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    }

    private func tab(_ index: Int) async {
        env.ui.openTab = index
        await wait(2)
    }

    private func closeSheets() async {
        window?.rootViewController?.dismiss(animated: false)
        await wait(1)
    }

    private static let sizes: [(String, CGSize)] = [
        ("chica", CGSize(width: 420, height: 720)),
        ("mediana", CGSize(width: 960, height: 680)),
        ("grande", CGSize(width: 1440, height: 900)),
    ]

    /// Las cuatro pestañas, la ficha de una película y de una serie, Ajustes y la guía, en tres tamaños de ventana.
    func testTourAtThreeSizes() async {
        for (label, size) in Self.sizes {
            await resize(size)
            for (index, name) in [(0, "inicio"), (1, "explorar"), (2, "buscar"), (3, "biblioteca")] {
                await tab(index)
                shot("\(label)-\(name)")
            }
            await tab(0)
            env.pendingTitle = TitleRoute(kind: "movie", metaID: "tt1160419", title: "", poster: nil)
            await wait(4)
            shot("\(label)-ficha-pelicula")
            env.ui.goBack = true
            await wait(1.5)
            env.pendingTitle = TitleRoute(kind: "series", metaID: "tt0386676", title: "", poster: nil)
            await wait(4)
            shot("\(label)-ficha-serie")
            env.ui.goBack = true
            await wait(1.5)
            env.ui.openSettings = true
            await wait(2.5)
            shot("\(label)-ajustes")
            await closeSheets()
            env.ui.showDownloads = true
            env.openTab = AppEnvironment.downloadsTab
            await wait(2.5)
            shot("\(label)-descargas")
        }
    }

    /// Redimensionar en vivo: a media carga de la ficha, de grande a chica y de regreso, sin esperar a que acabe de pintar.
    func testLiveResizeWhileLoading() async {
        await resize(CGSize(width: 1280, height: 820), settle: 1)
        env.pendingTitle = TitleRoute(kind: "series", metaID: "tt0386676", title: "", poster: nil)
        for step in 0..<6 {
            await resize(step.isMultiple(of: 2) ? CGSize(width: 420, height: 700) : CGSize(width: 1280, height: 820), settle: 0.4)
        }
        await wait(3)
        shot("vivo-ficha-tras-redimensionar")
        XCTAssertNotNil(window, "la ventana se cerró al redimensionar")
        env.ui.goBack = true
    }

    /// El reproductor (con la demostración): abierto, con «Audio y subtítulos», y redimensionando la ventana con él encima.
    func testPlayerAndResize() async {
        await resize(CGSize(width: 1280, height: 800))
        await env.play(kind: "movie", metaID: "tt1160419", videoID: "tt1160419", title: "Dune", originalTitle: "Dune", episodeLabel: "", poster: nil)
        await wait(6)
        shot("reproductor-grande")
        await resize(CGSize(width: 480, height: 760), settle: 2)
        shot("reproductor-chica")
        await resize(CGSize(width: 1280, height: 800), settle: 2)
        shot("reproductor-de-regreso")
        env.playing = nil
        await wait(2)
        shot("reproductor-cerrado")
    }

    /// Modo claro y oscuro de la misma pantalla (Orbital es oscura por omisión; el claro también tiene que verse bien).
    func testLightAndDark() async {
        await resize(CGSize(width: 1200, height: 800))
        await tab(0)
        for style in [UIUserInterfaceStyle.dark, .light] {
            AppWindows.all.forEach { $0.overrideUserInterfaceStyle = style }
            await wait(2)
            shot("apariencia-\(style == .dark ? "oscuro" : "claro")-inicio")
            await tab(3)
            shot("apariencia-\(style == .dark ? "oscuro" : "claro")-biblioteca")
            await tab(0)
        }
        env.applyAppearance()
    }
}
