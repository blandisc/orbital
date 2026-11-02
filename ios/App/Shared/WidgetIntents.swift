import AppIntents
import Foundation
import WidgetKit

/// Los botones de los widgets: «Aquí» (abre la app y reproduce donde ibas) y «En la TV» (manda el título a tu Orbital sin abrir
/// la app). Viven en `Shared/` (la app y la extensión): los dos corren dentro de la app. «En la TV» es una `LiveActivityIntent`:
/// iOS despierta la app en segundo plano para ejecutarla, sin traerla al frente (una `AppIntent` normal correría en la extensión,
/// que no tiene la conexión con la consola).

/// «Aquí»: abre la app en el enlace del widget (reproducir o la ficha). La app pone `open` al arrancar.
struct OpenWidgetLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir en Orbital"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    @MainActor static var open: ((URL) -> Void)?

    @Parameter(title: "Enlace") var link: URL

    init() {}
    init(link: URL) { self.link = link }

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.open?(link)
        return .result()
    }
}

/// «En la TV»: pone el título en tu Orbital donde ibas. El widget enseña lo que pasó (`WidgetTVStatus`) unos minutos.
struct PlayOnTVIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Ver en la TV"
    static let isDiscoverable = false

    @Parameter(title: "Tipo") var kind: String
    @Parameter(title: "Título") var metaID: String
    @Parameter(title: "Episodio") var videoID: String?
    @Parameter(title: "Nombre") var name: String

    init() {}
    init(kind: String, metaID: String, videoID: String?, name: String) {
        self.kind = kind; self.metaID = metaID; self.videoID = videoID; self.name = name
    }

    /// Lo pone la app al arrancar: manda el título a la consola y dice si la consola lo aceptó.
    @MainActor static var send: ((_ kind: String, _ metaID: String, _ videoID: String?, _ name: String) async -> Bool)?

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetTVStatus.save(.init(metaID: metaID, state: .sending, at: Date()))
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.kind)
        let sent = await Self.send?(kind, metaID, videoID, name) ?? false
        WidgetTVStatus.save(.init(metaID: metaID, state: sent ? .sent : .failed, at: Date()))
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.kind)
        return .result()
    }
}

/// Lo último que pasó con «En la TV» desde un widget: va en camino, ya está en la TV o la TV no contestó. Vive en el App Group
/// para que el widget lo enseñe; después de `ttl` ya no cuenta.
struct WidgetTVStatus: Codable, Equatable {
    enum State: String, Codable { case sending, sent, failed }
    var metaID: String
    var state: State
    var at: Date

    static let ttl: TimeInterval = 300
    private static let key = "widget.tv.status"

    static func save(_ status: WidgetTVStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        UserDefaults(suiteName: WidgetStore.groupID)?.set(data, forKey: key)
    }

    /// Lo de `metaID` si pasó hace menos de `ttl` (y lo de «va en camino», solo un minuto: si la app no contestó, ya no va).
    static func current(for metaID: String, now: Date = Date()) -> State? {
        guard let data = UserDefaults(suiteName: WidgetStore.groupID)?.data(forKey: key),
              let status = try? JSONDecoder().decode(WidgetTVStatus.self, from: data), status.metaID == metaID else { return nil }
        let age = now.timeIntervalSince(status.at)
        if status.state == .sending { return age < 60 ? .sending : nil }
        return age < ttl ? status.state : nil
    }
}
