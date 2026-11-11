import SwiftUI
import OrbitalModels

/// Ajustes › Cuentas › «N cosas no se pudieron guardar en Trakt»: qué fue, cuándo y por qué, en palabras llanas, con
/// «Reintentar» para lo que venció (revisión del 11 nov 2026). Qué decir lo decide `TraktDiscardsModel`.
struct TraktDiscardsView: View {
    @Environment(AppEnvironment.self) private var env
    let model: TraktDiscardsModel

    var body: some View {
        let _ = model.track()
        let rows: [TraktDiscardsModel.Row] = model.rows
        let language: String = env.services.appSettings.uiLanguage
        Form {
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        TraktDiscardRow(row: row, language: language, episode: env.services.episodeLabel) {
                            Task { await model.retry(row) }
                        }
                    }
                } footer: { Text("Lo que vence puedes mandarlo otra vez. Lo que Trakt no aceptó, reintentarlo no lo arregla.") }
                .listRowBackground(DS.surface)
                Section {
                    Button("Borrar la lista", role: .destructive) { model.clear() }
                        .accessibilityIdentifier("trakt-discards-clear")
                }
                .listRowBackground(DS.surface)
            }
        }
        .overlay { if rows.isEmpty { DSEmptyState(symbol: "checkmark.seal", title: Text("Todo llegó a Trakt")) } }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text("No llegó a Trakt")).navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .onAppear { model.reload() }
    }
}

/// Un renglón: qué era y de qué título, cuándo y por qué; «Reintentar» si tiene sentido.
private struct TraktDiscardRow: View {
    let row: TraktDiscardsModel.Row
    let language: String
    let episode: @Sendable (Int, Int) -> String
    let retry: () -> Void

    private var title: String {
        guard let season = row.season, let number = row.episode else { return row.title }
        return "\(row.title) · \(episode(season, number))"
    }

    private var what: String {
        let action = Strings.tr(row.action, language: language)
        return row.count > 1 ? "\(action) · \(row.count)" : action
    }

    private var reason: String {
        let text = Strings.tr(row.reason, language: language)
        guard let status = row.status, row.reason.contains("%lld") else { return text }
        return String(format: text, status)
    }

    private var when: String {
        Strings.date(row.at, .dayMonthShort, language: language) + " · " + Strings.date(row.at, .time, language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: what).recipe(.label, color: DS.textMuted)
            Text(verbatim: title).recipe(.body, color: DS.text)
            Text(verbatim: "\(when) · \(reason)").recipe(.footnote, color: DS.textMuted)
            if row.canRetry {
                Button("Reintentar", systemImage: "arrow.clockwise", action: retry)
                    .font(DS.TextRecipe.label.font)
                    .buttonStyle(.borderless)
                    .foregroundStyle(DS.accent)
                    .padding(.top, DS.Space.s1)
                    .accessibilityIdentifier("trakt-discard-retry")
            }
        }
        .padding(.vertical, DS.Space.s1)
    }
}
