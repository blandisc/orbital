import XCTest

/// Una espera dentro de un `.task(id:)` que se cancela no sigue (19 nov 2026: la primera pantalla de una lección salía vacía).
/// Cuando cambia el `id`, SwiftUI cancela la tarea vieja; `try? await Task.sleep` se traga la cancelación y lo de abajo corre
/// igual, tarde, encima de lo nuevo (congelaba la escena, apagaba «¿Seguro?» antes de tiempo, borraba un salto recién pedido).
/// Se escribe `guard (try? await Task.sleep(…)) != nil else { return }` (o `break` en un ciclo), o se revisa
/// `Task.isCancelled` en el renglón siguiente (o la espera es lo último de un ciclo que lo revisa). Regla en `docs/ios-interfaz.md` § «Esperas que se cancelan».
extension DesignRulesTests {
    func testTaskIDWaitsStopWhenCancelled() throws {
        var problems: [String] = []
        for file in try sources(["Design", "Screens", "Platform", "Support", "App"]) {
            for (i, line) in file.lines.enumerated() where line.contains(".task(id:") {
                let window = file.lines[i..<min(file.lines.count, i + 8)]
                for (j, wait) in zip(window.indices, window) where wait.contains("try? await Task.sleep") {
                    let after = j + 1 < file.lines.count ? file.lines[j + 1] : ""
                    let stops = wait.contains("guard (try? await Task.sleep") || wait.contains(", (try? await Task.sleep")
                        || after.contains("isCancelled")
                        || after.trimmingCharacters(in: .whitespaces) == "}"   // lo último del ciclo: la vuelta revisa `isCancelled`
                    if !stops { problems.append("\(file.path):\(j + 1): \(wait.trimmingCharacters(in: .whitespaces).prefix(120))") }
                }
            }
        }
        check(problems, "Espera en .task(id:) que sigue aunque la cancelen: guard (try? await Task.sleep(…)) != nil else { return }")
    }
}

/// En una escena de lección, la escala y el giro de una pieza puesta con `sceneAt` van antes de `sceneAt` (19 nov 2026: los
/// tres pósters que quedaban en «Junta filtros» crecían alrededor de la esquina del lienzo y se salían de la cuadrícula).
/// `scenePut` con escala o giro (4.º o 5.º valor) solo en piezas que vuelan con `dx`/`dy`, sin `sceneAt` en su cadena.
extension DesignRulesTests {
    func testScaledScenePiecesScaleBeforeTheirPlace() throws {
        var problems: [String] = []
        for file in try sources(["Design"]) where file.path.contains("Lessons/") {
            for (i, line) in file.lines.enumerated() {
                guard let r = line.range(of: ".scenePut(") else { continue }
                var depth = 1, commas = 0
                for ch in line[r.upperBound...] {
                    if ch == "(" || ch == "[" { depth += 1 } else if ch == ")" || ch == "]" { depth -= 1; if depth == 0 { break } }
                    else if ch == ",", depth == 1 { commas += 1 }
                }
                guard commas >= 3 else { continue }
                var chain = String(line[..<r.lowerBound])
                var k = i - 1
                while k >= 0, file.lines[k].trimmingCharacters(in: .whitespaces).hasPrefix(".") { chain += file.lines[k]; k -= 1 }
                if k >= 0 { chain += file.lines[k] }   // el renglón donde empieza la pieza
                if chain.contains(".sceneAt(") { problems.append("\(file.path):\(i + 1): \(line.trimmingCharacters(in: .whitespaces).prefix(120))") }
            }
        }
        check(problems, "Escala o giro después de sceneAt: la pieza se sale de su lugar; pon .scaleEffect/.rotationEffect antes de sceneAt")
    }
}
