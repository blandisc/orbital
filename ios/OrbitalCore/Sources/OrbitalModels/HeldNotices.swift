import Foundation

/// Avisos que llegan mientras otro ocupa su sitio. Se encolan y salen en el orden en que llegaron.
/// `hold()` retiene: `next` no entrega y lo que falte sigue en la cola. `resume` suelta esa retención
/// para ir sacándolos de uno en uno. `release` suelta y devuelve todo de una vez.
/// Con clave (subtítulos, zoom) solo se queda el último de esa clase, en el mismo puesto.
public struct HeldNotices<Element> {
    private struct Slot {
        var key: AnyHashable?
        var element: Element
    }

    private var slots: [Slot] = []
    /// Mientras es cierto, `next` no entrega. La cola no se vacía.
    public private(set) var isHolding = false

    public init() {}

    /// Empieza a retener. Lo que ya estaba encolado se queda.
    public mutating func hold() {
        isHolding = true
    }

    /// Encola al final. Si `key` ya está, ese puesto se queda con el nuevo y no se mueve.
    public mutating func hold(_ element: Element, key: AnyHashable? = nil) {
        if let key, let index = slots.firstIndex(where: { $0.key == key }) {
            slots[index].element = element
            return
        }
        slots.append(Slot(key: key, element: element))
    }

    /// Suelta la retención y devuelve la cola entera, en orden. Queda vacía.
    public mutating func release() -> [Element] {
        isHolding = false
        let waiting = slots.map(\.element)
        slots.removeAll()
        return waiting
    }

    /// Suelta la retención sin vaciar: a partir de aquí `next` entrega. Un `hold()` posterior
    /// vuelve a frenar lo que todavía no se haya sacado.
    public mutating func resume() {
        isHolding = false
    }

    /// El siguiente, si no se está reteniendo. nil si se retiene o no queda nada.
    public mutating func next() -> Element? {
        guard !isHolding, !slots.isEmpty else { return nil }
        return slots.removeFirst().element
    }

    public var isEmpty: Bool { slots.isEmpty }
}
