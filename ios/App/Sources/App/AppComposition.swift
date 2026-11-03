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
            let services = Services(http: DemoHTTPClient(), secrets: Demo.secrets(), kv: kv, pending: InMemoryPendingStore(),
                                    downloadTransport: transport, downloadsRoot: Demo.demoDownloadsRoot,
                                    savedDownloads: Demo.downloads, freeSpace: { DiskSpace.freeBytes() },
                                    cacheRoot: Demo.persist ? AppFiles.swrCache.appendingPathComponent("demo") : nil,
                                    deviceName: ThisDevice.name, allowsOrbital: ThisDevice.talksToOrbital,
                                    // La demostración no escribe en la memoria de TMDB de tu iPhone (era global hasta el 31 oct 2026).
                                    detailsMemo: Demo.persist ? TmdbDetailsMemo(file: AppFiles.swrCache.appendingPathComponent("demo/tmdb-details.json")) : nil)
            services.forYouFromConsole = Demo.console   // la ruta de la consola, para verla con la Orbital de mentira
            Demo.seedRequests(services)   // `-demo-rd-request`: tus pedidos a Real-Debrid de mentira
            services.isOnline = { !Demo.offline }
            return services
        }
        #endif
        let services = Services(
            http: Perf.isOn ? PerfHTTPClient(inner: URLSessionHTTPClient()) : URLSessionHTTPClient(), secrets: KeychainSecrets(service: Bundle.main.bundleIdentifier ?? "com.example.orbital.ios"),
            kv: UserDefaultsKeyValueStore(), pending: FilePendingStore(url: AppFiles.pendingWork), library: LocalLibrary(url: AppFiles.library),
            downloadTransport: transport,
            downloadsRoot: AppFiles.downloadsRoot, savedDownloads: DownloadIndex.load(), freeSpace: { DiskSpace.freeBytes() },
            cacheRoot: AppFiles.swrCache, onDownloadsChange: { DownloadIndex.save($0) }, device: ThisDevice.forOrbital, deviceName: ThisDevice.name,
            allowsOrbital: ThisDevice.talksToOrbital,
            // Lo de TMDB ya pedido (el mismo archivo de Caches de antes): no se pide otra vez en cada arranque.
            detailsMemo: TmdbDetailsMemo(file: AppFiles.swrCache.deletingLastPathComponent().appendingPathComponent("tmdb-details.json")))
        services.isOnline = { Connectivity.shared.isOnline }
        return services
    }
}
