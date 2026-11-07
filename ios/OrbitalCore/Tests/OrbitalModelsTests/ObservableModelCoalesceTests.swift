import Testing
@testable import OrbitalModels

@MainActor
private final class CoalesceProbe: ObservableModel {
    var a = 0 { didSet { changed() } }
    var b = 0 { didSet { changed() } }
}

/// Varios campos puestos dentro de `coalescing` avisan una sola vez (la ficha se repinta una vez, no una por campo).
@MainActor @Test func coalescingAvisaUnaSolaVez() {
    let model = CoalesceProbe()
    var calls = 0
    let sub = model.onChange { calls += 1 }
    model.coalescing { model.a = 1; model.b = 2; model.coalescing { model.a = 3 } }
    #expect(calls == 1)
    model.coalescing { }
    #expect(calls == 1)
    model.a = 4
    #expect(calls == 2)
    sub.cancel()
}
