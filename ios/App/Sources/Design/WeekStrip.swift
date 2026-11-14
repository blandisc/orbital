import SwiftUI

/// Un mapa de semanas que se desliza de lado (el «Día por día» de «Lo que ves» y el de «Tu año»): una columna por semana, de
/// lunes a domingo, el mes arriba de la semana en que empieza y las letras de los días fijas a la izquierda.
///
/// Regla «Lo que se desplaza a lo ancho abre mostrando lo importante completo, y dice que hay más» (Fernando, 13 nov 2026:
/// «aparece como rota, o sea, no se ve completa, tienes que darle a la derecha cuando la abres»; `docs/ios-interfaz.md`):
/// - Las casillas salen del ancho que le queda (`available`, de `WindowMetrics.column`): caben semanas enteras, nunca una a
///   medias en la orilla.
/// - Si todas caben (iPad, Mac), se ven todas y no se desliza.
/// - Si no, abre en la semana de hoy, por su id (no con `defaultScrollAnchor`, que con una lista perezosa o con semanas que
///   llegan después del historial abría en el otro extremo), y se detiene por semanas.
/// - Lo que queda atrás se desvanece en la orilla izquierda (`edgeFade`): dice que hay más.
struct DSWeekStrip<Cell: View>: View {
    let weeks: Int
    /// El ancho que le queda (la columna menos sus márgenes), con las letras de los días incluidas.
    let available: CGFloat
    /// Lo que va arriba de cada semana («oct», «2026» en enero, o nada).
    let label: (Int) -> String
    /// Las siete letras de los días, del lunes al domingo (se dicen lunes, miércoles, viernes y domingo: Fernando, 14 nov 2026).
    let weekdays: [String]
    @ViewBuilder let cell: (_ week: Int, _ day: Int, _ size: CGFloat) -> Cell
    @State private var position: ScrollPosition
    @ScaledMetric(relativeTo: .caption) private var dayColumn = DS.WeekStrip.dayColumn

    init(weeks: Int, available: CGFloat, weekdays: [String], label: @escaping (Int) -> String,
         @ViewBuilder cell: @escaping (_ week: Int, _ day: Int, _ size: CGFloat) -> Cell) {
        self.weeks = weeks; self.available = available; self.weekdays = weekdays; self.label = label; self.cell = cell
        _position = State(initialValue: ScrollPosition(id: max(weeks - 1, 0), anchor: .trailing))
    }

    var body: some View {
        let fit = DS.WeekStrip.fit(available: available - dayColumn - DS.WeekStrip.gap, weeks: weeks)
        HStack(alignment: .top, spacing: DS.WeekStrip.gap) {
            days(fit.cell)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.WeekStrip.gap) {
                    ForEach(0..<weeks, id: \.self) { w in
                        VStack(spacing: DS.WeekStrip.gap) {
                            // El mes se sale a la derecha de su semana (cabe en las siguientes); el de la última, a la izquierda.
                            Text(verbatim: label(w).isEmpty ? " " : label(w)).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted)
                                .lineLimit(1).fixedSize()
                                .frame(width: fit.cell, alignment: w == weeks - 1 ? .trailing : .leading)
                                .accessibilityHidden(true)
                            ForEach(0..<7, id: \.self) { d in cell(w, d, fit.cell).frame(width: fit.cell, height: fit.cell) }
                        }
                        .id(w)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollClipDisabled()   // lo que crece al picarlo (o al dejarlo apretado) no se corta en la orilla del listón
            .scrollPosition($position, anchor: .trailing)
            .scrollTargetBehavior(.viewAligned)
            .scrollDisabled(!fit.scrolls)
            .onChange(of: weeks) { _, now in position.scrollTo(id: now - 1, anchor: .trailing) }   // llegó más historial: sigue en hoy
            .edgeFade()   // lo que queda atrás (y adelante, si te regresas) se desvanece en la orilla: hay más
            .frame(width: fit.width, alignment: .leading)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // los rótulos de una gráfica: crecen, pero no más que sus casillas
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// L, X, V y D a la izquierda, a la altura de su renglón (debajo del renglón de los meses).
    private func days(_ size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DS.WeekStrip.gap) {
            Text(verbatim: " ").font(DS.TextRecipe.caption.font).lineLimit(1).fixedSize()
            ForEach(0..<7, id: \.self) { d in
                Text(verbatim: d % 2 == 0 && weekdays.indices.contains(d) ? weekdays[d] : "")
                    .font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                    .frame(width: dayColumn, height: size, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }

    /// «oct» al empezar octubre; «2026» en la semana de enero; nada si el mes no empieza esa semana.
    static func monthLabel(_ monday: Date, calendar: Calendar, locale: Locale) -> String {
        guard let sunday = calendar.date(byAdding: .day, value: 6, to: monday),
              let first = calendar.dateInterval(of: .month, for: sunday)?.start, first >= monday else { return "" }
        if calendar.component(.month, from: first) == 1 { return String(calendar.component(.year, from: first)) }
        return first.formatted(.dateTime.month(.abbreviated).locale(locale)).replacingOccurrences(of: ".", with: "")
    }

    /// Las letras de los días del lunes al domingo, en el idioma de la app («L M X J V S D»).
    static func weekdayLetters(locale: Locale) -> [String] {
        var c = Calendar(identifier: .gregorian)
        c.locale = locale
        let symbols = c.veryShortStandaloneWeekdaySymbols   // empieza en domingo
        return Array(symbols.dropFirst()) + symbols.prefix(1)
    }
}

/// La leyenda de un mapa de calor: «Hoy» a la izquierda y «Menos ▢▢▢▢ Más» a la derecha, chiquita y gris.
struct DSHeatLegend: View {
    /// Los tonos de menos a más (los mismos de las casillas).
    let steps: [Color]

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous).fill(DS.fill)
                .overlay { DSWeekStripToday() }
                .frame(width: DS.WeekStrip.swatch, height: DS.WeekStrip.swatch)
            Text("Hoy").recipe(.caption, color: DS.textMuted)
            Spacer(minLength: DS.Space.s3)
            Text("Menos").recipe(.caption, color: DS.textMuted)
            ForEach(steps.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous).fill(steps[i])
                    .frame(width: DS.WeekStrip.swatch, height: DS.WeekStrip.swatch)
            }
            Text("Más").recipe(.caption, color: DS.textMuted)
        }
        .lineLimit(1)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // como los rótulos del mapa: crece, sin aplastar sus cuadritos
        .accessibilityHidden(true)   // cada casilla ya dice su día y cuánto viste
    }
}

/// El borde de la casilla de hoy (en el mapa y en la leyenda).
struct DSWeekStripToday: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous).strokeBorder(DS.text, lineWidth: DS.Stroke.regular)
    }
}
