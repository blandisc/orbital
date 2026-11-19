import Foundation
import OrbitalCore
import OrbitalModels

/// La raíz de composición: aquí (y solo aquí) se decide con qué red, llavero, disco y transporte se arma `Services`,
/// de verdad o de demostración. El resto de la app recibe `Services` ya hecho.
@MainActor
enum AppComposition {
    static func makeServices(_ transport: BackgroundDownloadTransport) -> Services {
        #if DEBUG
        // Modo demostración: nada toca tu Keychain, tus ajustes ni tus descargas.
        if Demo.isOn {
            // `-demo-persist`: lo guardado sobrevive entre aperturas (como en tu iPhone), para medir abrir la app de nuevo.
            let kv: KeyValueStore = Demo.persist ? UserDefaultsKeyValueStore(prefix: "orbital-demo.") : InMemoryKeyValueStore()
            SettingsStore(kv).update {
                if let language = Demo.language { $0.uiLanguage = language }
                if !Demo.noTV { $0.orbitalAddress = "tv.demo.invalid"; $0.orbitalEnabled = true }
                // `-demo-trakt-builtin`: sin Client ID en Ajustes (el incluido en la app), como un iPhone sin consola.
                if (Demo.scrobble || Demo.airings || Demo.because || Demo.trakt || Demo.firstRun) && !Demo.traktBuiltIn { $0.traktClientID = "demo" }
                if let style = Demo.value(after: "-demo-because-style") { $0.becauseStyle = style }
                if let state = Demo.oneDrive, state != "off" { $0.oneDriveClientID = "demo" }
                if Demo.oneDrive == "linked" { $0.oneDriveFolder = "Películas" }
            }
            Demo.prefillScrobble(kv)
            if Demo.coach { kv.set(LearnModel.guideDoneKey, data: Data("1".utf8)) }
            let pending = InMemoryPendingStore()
            Demo.seedTraktDiscards(pending)   // `-demo-trakt-discards`: lo que no llegó a Trakt, para Ajustes
            let services = Services(http: DemoHTTPClient(), secrets: Demo.secrets(), kv: kv, pending: pending,
                                    downloadTransport: transport, downloadsRoot: Demo.demoDownloadsRoot,
                                    savedDownloads: Demo.downloads, freeSpace: { DiskSpace.freeBytes() },
                                    cacheRoot: Demo.persist ? AppFiles.swrCache.appendingPathComponent("demo") : nil,
                                    deviceName: ThisDevice.name, platform: ThisDevice.platform, capabilities: ThisDevice.capabilities,
                                    // La demostración no escribe en la memoria de TMDB de tu iPhone (era global hasta el 31 oct 2026).
                                    detailsMemo: Demo.persist ? TmdbDetailsMemo(file: AppFiles.swrCache.appendingPathComponent("demo/tmdb-details.json")) : nil)
            services.forYouFromConsole = Demo.console   // la ruta de la consola, para verla con la Orbital de mentira
            Demo.seedLibrary(services)    // «Seguir viendo» de la demo (antes llegaba con Stremio)
            Demo.seedRequests(services)   // `-demo-rd-request`: tus pedidos a Real-Debrid de mentira
            DemoLatinoNube.seed(services)   // `-demo-latino-nube refused`: Real-Debrid ya rechazó el latino (LN2)
            Demo.seedDebrid(services)     // `-demo-rd revoked`: una cuenta confirmada ayer cuya clave ya no sirve
            DemoViento.seed(services)     // `-demo-viento ready`: el pedido de «El viento tiene miedo» ya listo
            Demo.seedAddons(services)     // `-demo-addons`, `-demo-torrentio`: Complementos y Torrentio de mentira
            Demo.seedTVAddons(services)   // `-demo-tv-addons`: tu lista y la de tu TV de mentira (S6)
            services.isOnline = { !Demo.offline }
            return services
        }
        #endif
        let services = Services(
            http: Perf.isOn ? PerfHTTPClient(inner: URLSessionHTTPClient()) : URLSessionHTTPClient(), secrets: KeychainSecrets(service: Bundle.main.bundleIdentifier ?? "mx.iracheta.orbital"),
            kv: UserDefaultsKeyValueStore(), pending: FilePendingStore(url: AppFiles.pendingWork), library: LocalLibrary(url: AppFiles.library),
            downloadTransport: transport,
            downloadsRoot: AppFiles.downloadsRoot, savedDownloads: DownloadIndex.load(), freeSpace: { DiskSpace.freeBytes() },
            cacheRoot: AppFiles.swrCache, onDownloadsChange: { DownloadIndex.save($0) }, device: ThisDevice.forOrbital, deviceName: ThisDevice.name,
            platform: ThisDevice.platform, capabilities: ThisDevice.capabilities,
            // Lo de TMDB ya pedido (el mismo archivo de Caches de antes): no se pide otra vez en cada arranque.
            detailsMemo: TmdbDetailsMemo(file: AppFiles.swrCache.deletingLastPathComponent().appendingPathComponent("tmdb-details.json")))
        services.isOnline = { Connectivity.shared.isOnline }
        services.audioProbe = .shared   // «revisar por dentro»: corta en cuanto llegan los bytes del encabezado
        // Prendida con el OK de Fernando (12 nov 2026: «Sí, préndelo»). Leer una versión la agrega a su Real-Debrid; si da
        // problemas se apaga con `services.audioProbe.turnOff()`.
        return services
    }

    /// La guía de práctica (Aprende › «Ver la guía otra vez»): unos `Services` aparte con la red de la demo (Trakt se
    /// «aprueba» solo, la nube acepta claves de mentira) y todo en memoria. Lo que hagas ahí no llega a tus cuentas, tu TV,
    /// tus ajustes ni tu biblioteca, y se olvida al cerrarla. La misma versión (Ultra, Plus u Orbital) que la app.
    static func practiceServices(_ transport: BackgroundDownloadTransport) -> Services {
        Demo.practice = true
        let kv = InMemoryKeyValueStore()
        SettingsStore(kv).update { $0.traktClientID = "demo"; $0.uiLanguage = AppEnvironment.shared.services.settings.value.uiLanguage }
        let services = Services(http: DemoHTTPClient(), secrets: InMemorySecrets(), kv: kv, pending: InMemoryPendingStore(),
                                downloadTransport: transport, downloadsRoot: FileManager.default.temporaryDirectory.appendingPathComponent("practica"),
                                savedDownloads: [], freeSpace: { DiskSpace.freeBytes() },
                                deviceName: ThisDevice.name, platform: ThisDevice.platform, capabilities: ThisDevice.capabilities)
        services.isOnline = { true }
        return services
    }
}
