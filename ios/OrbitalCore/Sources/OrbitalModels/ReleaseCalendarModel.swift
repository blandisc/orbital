import Foundation
import OrbitalCore

/// El calendario de «Sale hoy»: lo que sale cada día del mes de las series que sigues (Trakt), para pintarlo por día.
@MainActor
public final class ReleaseCalendarModel: ObservableModel {
    /// El primer día del mes que se ve.
    public private(set) var month: Date { didSet { changed() } }
    public private(set) var days: [Date: [Airing]] = [:] { didSet { changed() } }
    public private(set) var loading = false { didSet { changed() } }
    public var selected: Date { didSet { changed() } }

    private let services: Services
    private let calendar: Calendar
    /// Trakt da hasta 31 días por pedido; el mes se pide en dos mitades (también así cabe el día de antes por la hora universal).
    static let half = 16

    public init(_ services: Services, calendar: Calendar = .current) {
        self.services = services
        self.calendar = calendar
        let today = calendar.startOfDay(for: services.now())
        month = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        selected = today
        super.init()
    }

    public var today: Date { calendar.startOfDay(for: services.now()) }

    /// Los días del mes con sus huecos al principio (la semana empieza según tu región): nil es una casilla vacía.
    public var grid: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    public func airings(on day: Date) -> [Airing] { days[calendar.startOfDay(for: day)] ?? [] }

    public func load() async {
        loading = true
        defer { loading = false }
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let skip = calendar.dateComponents([.day], from: today, to: month).day ?? 0
        let forYou = services.forYou
        async let first = try? forYou.calendar(skip: skip, days: Self.half, calendar: calendar)
        async let second = try? forYou.calendar(skip: skip + Self.half, days: count - Self.half, calendar: calendar)
        let all = ((await first) ?? []) + ((await second) ?? [])
        var grouped: [Date: [Airing]] = [:]
        for a in all { grouped[a.day, default: []].append(a) }
        days = grouped
    }

    /// Otro mes (−1 el anterior, +1 el siguiente): se elige su primer día (o hoy, si es este mes).
    public func move(_ step: Int) async {
        guard let next = calendar.date(byAdding: .month, value: step, to: month) else { return }
        month = next
        selected = calendar.isDate(today, equalTo: next, toGranularity: .month) ? today : next
        days = [:]
        await load()
    }
}
