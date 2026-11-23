import XCTest

/// Nada que espere sin soltar el hilo corre en los hilos de Swift (Fernando, 22 nov 2026: «sigue lentísima… tardan mucho en
/// cargar las imágenes»). Vision ocupaba todos los hilos de Swift esperando y la ficha se quedaba en «Cargando la ficha».
/// Regla en `docs/ios-interfaz.md` § «En la Mac nada se mueve solo».
extension DesignRulesTests {
    func testBlockingVisionRunsOffTheSwiftThreads() throws {
        let files = try sources(["Platform", "Design", "Screens", "Support"]).filter { $0.lines.contains { $0.contains("VNImageRequestHandler(") } }
        XCTAssertFalse(files.isEmpty, "¿Dónde quedó Vision? (FocalPoint)")
        for file in files {
            let text = file.lines.joined(separator: "\n")
            XCTAssertTrue(text.contains("DispatchQueue(label:") && text.contains("withCheckedContinuation"),
                          "\(file.path): Vision espera sin soltar el hilo; va en su propia DispatchQueue, no en Task.detached")
            XCTAssertFalse(file.lines.contains { $0.contains("Task.detached") && $0.contains("locate(") },
                           "\(file.path): Vision dentro de Task.detached ocupa los hilos de Swift")
        }
    }
}
