import Foundation

/// Los avisos de que tu Real-Debrid vence: a 14 días, a 3 días y el día que vence, a las 10 de la mañana. Cada uno se
/// programa una sola vez por fecha de vencimiento (si renuevas, la fecha cambia y vuelven a tocar los de la nueva).
public struct DebridReminder: Equatable, Sendable, Identifiable {
    public enum Kind: Int, Sendable, CaseIterable {
        case twoWeeks = 14, threeDays = 3, today = 0
    }
    public var kind: Kind
    public var fireAt: Date
    /// Una por fecha de vencimiento: «debrid.14.2027-03-21».
    public var id: String
    /// Cuántos días quedan cuando suena (14, 3 o 0).
    public var daysLeft: Int { kind.rawValue }
}

public enum DebridReminders {
    public static let hour = 10

    /// Los avisos que aún no suenan para este estado (solo con Premium y fecha de vencimiento).
    public static func upcoming(_ status: DebridStatus, now: Date, calendar: Calendar = .current) -> [DebridReminder] {
        guard status.isPremium, let expires = status.expires else { return [] }
        let day = calendar.startOfDay(for: expires)
        let stamp = Self.stamp(day, calendar: calendar)
        return DebridReminder.Kind.allCases.compactMap { kind in
            guard let date = calendar.date(byAdding: .day, value: -kind.rawValue, to: day),
                  let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date), fire > now else { return nil }
            return DebridReminder(kind: kind, fireAt: fire, id: "debrid.\(kind.rawValue).\(stamp)")
        }
    }

    private static func stamp(_ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Qué avisos ya se programaron (para no repetirlos cada vez que se abre la app).
public final class DebridReminderBook: @unchecked Sendable {
    private let vault: AddonVault
    private let lock = NSLock()
    public init(vault: AddonVault) { self.vault = vault }

    private var scheduled: Set<String> {
        get { Set(vault.data(AddonKeys.reminders).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []) }
        set { vault.setData(AddonKeys.reminders, try? JSONEncoder().encode(newValue.sorted())) }
    }

    /// Los que faltan por programar; quedan anotados como programados (quien llama los programa ya).
    public func toSchedule(_ status: DebridStatus, now: Date, calendar: Calendar = .current) -> [DebridReminder] {
        lock.withLock {
            let upcoming = DebridReminders.upcoming(status, now: now, calendar: calendar)
            let done = scheduled
            let fresh = upcoming.filter { !done.contains($0.id) }
            // Se guardan solo los de la fecha de ahora: los de un vencimiento anterior ya no sirven.
            scheduled = Set(upcoming.map(\.id)).intersection(done.union(fresh.map(\.id)))
            return fresh
        }
    }
}
