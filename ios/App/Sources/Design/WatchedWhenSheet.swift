import SwiftUI
import OrbitalCore
import OrbitalModels

/// «¿Cuándo la viste?» (Fernando, 31 oct 2026; propuesta en docs/producto/marcar-vista.html): una sola hoja para marcar
/// como vista una película, un episodio, una temporada o la serie completa, con las opciones de Trakt. Arriba dice qué
/// marcas; cada opción lleva su ícono y su fecha ya escrita; «Otro día…» abre el calendario ahí mismo; «No sé cuándo» la
/// marca sin fecha. Con episodios anteriores sin ver, pregunta si también los marca. Si ya la viste: «La vi otra vez» o
/// «Quitar de vistas». La fecha viaja a tu historial de Trakt.
struct WatchedWhenSheet: View {
    let title: Text
    let detail: Text
    var poster: String?
    /// «El día que se estrenó», «El día que salió» o «Cuando salió cada episodio», con su fecha (o rango) si se sabe.
    let releaseTitle: Text
    var releaseDetail: Text?
    var alreadyWatched = false
    /// Cuándo la viste la última vez (para «Quitar de vistas»).
    var watchedDetail: Text?
    /// Episodios anteriores que ya salieron y no has visto.
    var earlier = 0
    /// El idioma de la app (la hora y las fechas).
    var language = "es"
    let pick: (WatchedWhen, _ alsoEarlier: Bool) -> Void
    var again: (() -> Void)?
    var remove: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var calendar = false
    @State private var day = Date()
    /// La fecha ya elegida, esperando la respuesta de «¿también los anteriores?».
    @State private var asking: WatchedWhen?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(spacing: DS.Space.s3) {
                    if let poster {
                        PosterView(url: poster, title: "", maxPoints: DS.Watched.poster)
                            .frame(width: DS.Watched.poster * DS.Poster.aspect, height: DS.Watched.poster)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        (alreadyWatched ? Text("Ya la viste") : asking != nil ? Text("¿También los anteriores?") : Text("¿Cuándo la viste?")).recipe(.cardTitle)
                        Text("\(title) · \(detail)").recipe(.footnote, color: DS.textMuted).lineLimit(2)
                    }
                }
                if alreadyWatched {
                    WatchedOption(symbol: "arrow.counterclockwise", title: Text("La vi otra vez"), detail: Text("Otra vista en tu historial, ahora mismo")) { finish { again?() } }
                        .accessibilityIdentifier("watched-again")
                    WatchedOption(symbol: "xmark.circle", title: Text("Quitar de vistas"), detail: watchedDetail) { finish { remove?() } }
                        .accessibilityIdentifier("watched-remove")
                } else if let asking {
                    (earlier == 1 ? Text("El episodio anterior tampoco lo has visto.") : Text("Los \(earlier) episodios anteriores tampoco los has visto."))
                        .recipe(.body, color: DS.text)
                    WatchedOption(symbol: "checkmark.circle.fill", title: Text("Sí, márcalos también"), detail: Text("Con la misma fecha")) { finish { pick(asking, true) } }
                        .accessibilityIdentifier("watched-earlier-yes")
                    WatchedOption(symbol: "checkmark.circle", title: Text("Solo este"), detail: Text("Me salté los otros")) { finish { pick(asking, false) } }
                        .accessibilityIdentifier("watched-earlier-no")
                } else {
                    WatchedOption(symbol: "clock", title: Text("Ahora mismo"), detail: Text("Hoy, \(Strings.clock(Date(), language: language))")) { choose(.now) }
                        .accessibilityIdentifier("watched-now")
                    WatchedOption(symbol: "calendar.badge.checkmark", title: releaseTitle, detail: releaseDetail) { choose(.release) }
                        .accessibilityIdentifier("watched-release")
                    WatchedOption(symbol: "calendar", title: Text("Otro día…"), detail: Text("Elige en el calendario"), open: calendar) {
                        withAnimation(DS.Motion.base(reduceMotion)) { calendar.toggle() }
                    }
                    .accessibilityIdentifier("watched-other")
                    if calendar {
                        VStack(spacing: DS.Space.s2) {
                            DatePicker(selection: $day, in: ...Date(), displayedComponents: .date) { Text("El día que la viste") }
                                .datePickerStyle(.graphical).tint(DS.orbitalBlue)
                            Button { choose(.day(day)) } label: {
                                Text("Listo · \(Strings.date(day, .dayMonthShort, language: language))").frame(maxWidth: .infinity)
                            }
                            .dsSolidPrimaryButton().controlSize(.large)
                            .accessibilityIdentifier("watched-when-done")
                        }
                        .padding(DS.Space.s3)
                        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    WatchedOption(symbol: "questionmark.circle", title: Text("No sé cuándo"), detail: Text("Vista, sin fecha")) { choose(.unknown) }
                        .accessibilityIdentifier("watched-unknown")
                }
                Label("Se guarda en tu historial de Trakt", systemImage: "arrow.triangle.2.circlepath")
                    .recipe(.caption, color: DS.textMuted).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, DS.Space.gutter)
            .padding(.bottom, DS.Space.s4)
        }
        .dsSheetContent()
        .presentationDetents(calendar ? [.large] : [.medium, .large])
        .accessibilityElement(children: .contain)   // cada opción conserva su identificador
        .accessibilityIdentifier("watched-when")
    }

    private func choose(_ when: WatchedWhen) {
        if earlier > 0 { withAnimation(DS.Motion.base(reduceMotion)) { calendar = false; asking = when } }
        else { finish { pick(when, false) } }
    }

    private func finish(_ action: () -> Void) { action(); dismiss() }
}

/// Una opción de «¿Cuándo la viste?»: su ícono en el azul de Orbital, qué es y su fecha.
struct WatchedOption: View {
    let symbol: String
    let title: Text
    var detail: Text?
    var open = false
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: symbol).font(DS.TextRecipe.section.font).foregroundStyle(DS.orbitalBlue).frame(width: DS.Watched.icon)
                VStack(alignment: .leading, spacing: 0) {
                    title.recipe(.body, color: DS.text).fontWeight(.semibold)
                    if let detail { detail.recipe(.footnote, color: DS.textMuted) }
                }
                Spacer(minLength: 0)
                if open { Image(systemName: "chevron.up").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted) }
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(maxWidth: .infinity, minHeight: DS.Watched.row, alignment: .leading)
            .background(DS.surface, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointerHover(.highlight)
    }
}
