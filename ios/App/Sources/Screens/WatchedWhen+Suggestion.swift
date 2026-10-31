import SwiftUI
import OrbitalCore
import OrbitalModels

extension View {
    /// «¿Cuándo la viste?» para una película suelta (Colecciones, Premios, el menú de un póster): `item` abre la hoja y
    /// `onPick` recibe la fecha (`Trakt.unknownDate` para «No sé cuándo»).
    func askingWhenWatched(_ item: Binding<Suggestion?>, onPick: @escaping (Suggestion, Date) -> Void) -> some View {
        modifier(SuggestionWatchedWhen(item: item, onPick: onPick))
    }
}

private struct SuggestionWatchedWhen: ViewModifier {
    @Binding var item: Suggestion?
    let onPick: (Suggestion, Date) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var released: Date?

    func body(content: Content) -> some View {
        content.sheet(item: $item) { s in
            let language = env.services.appSettings.uiLanguage
            WatchedWhenSheet(title: Text(verbatim: s.title), detail: s.year.map { Text(verbatim: "\(Strings.kind(s.kind, language: env.services.appSettings.uiLanguage)) · \($0)") } ?? Text(verbatim: Strings.kind(s.kind, language: env.services.appSettings.uiLanguage)),
                             poster: s.poster, releaseTitle: Text("El día que se estrenó"),
                             releaseDetail: released.map { Text(verbatim: Strings.longDay($0, language: language)) }, language: language) { when, _ in
                let now = Date()
                switch when {
                case .now: onPick(s, now)
                case .day(let d): onPick(s, d)
                case .unknown: onPick(s, Trakt.unknownDate)
                case .release:
                    if let released { onPick(s, min(released, now)) }
                    else { Task { onPick(s, min(await env.releaseDate(s) ?? now, now)) } }
                }
            }
            .task { released = await env.releaseDate(s) }
        }
    }
}
