import XCTest

/// Un solo nombre por título (revisión 2 del 11 nov 2026): «Dune / Duna», «The Office / La Oficina» e «Interstellar /
/// Interestelar» convivían, a veces en la misma pantalla. Toda vista que pinta el nombre de una película o serie pasa por la
/// puerta `titleName(…)` (`Design/TitleName.swift`, regla en `OrbitalModels.TitleNames`, la misma de la TV). Esta prueba
/// falla si una vista pinta crudo `x.title`, `x.name`, `x.show` o `x.displayTitle` en un texto, una etiqueta de VoiceOver o
/// el `title:` de una pieza. Un renglón que no es un título y no cabe en `notATitle` lleva `// no-es-título: <motivo>`.
extension DesignRulesTests {
    /// Lo que se llama `title`/`name` y no es el nombre de una película o serie (cada uno con su porqué).
    static let notATitle: [String: String] = [
        "addon": "un complemento", "app": "una app de la TV", "device": "un aparato", "source": "una fuente o su lista",
        "service": "una plataforma", "option": "una opción de un menú", "section": "una sección", "region": "un país",
        "words": "un texto fijo de la app", "coach": "un consejo de la app",
        "game": "un juego (no tiene traducción)", "list": "una lista tuya", "hub": "una plataforma", "choice": "una opción",
        "version": "una versión (archivo)", "plan": "un plan", "notice": "un aviso", "file": "un archivo", "cause": "una causa",
        "c": "una colección", "clip": "un video corto", "studio": "un estudio", "saga": "una saga de TMDB",
        "p.name": "una plataforma de TMDB", "s.name": "en filtros: un estudio o una plataforma", "target": "un destino de Guardar",
        "second": "la segunda acción de un aviso", "e": "un elemento de la repisa (premio)",
        "ep": "un episodio (su nombre lo marca el punto del idioma colado)", "episode": "un episodio",
        "chosen.episode": "un episodio de Los Simpson", "air.episode": "un episodio de un canal", "row.title": "un episodio (sus renglones)",
        "context.state": "la actividad en vivo (ya trae el nombre de la app)", "last": "lo último que se mandó a Trakt (sin id)",
        "flight": "el póster que vuela (solo arte, sin texto)", "title": "un título de TMDB: ya llega en tu idioma (sin id de IMDb)",
        "route.name": "una persona (reparto)", "studio.name": "un estudio", "air.episode.name": "un episodio de un canal",
        "model.name": "en la conexión con la TV: el nombre de este aparato",
    ]

    /// Lo que solo lleva el nombre como dato (abrir la ficha, pedir a la TV, descargar): la vista que lo pinta lo cruza.
    static let carriesTheName = #"TitleRoute\(|Suggestion\(|ViewingsTarget\(|playOnTV\(|queueDownload\(|BecauseSeed\(|addMovie\(|playEpisode\(|\.watch\(kind:|\.selectable\(|out\.append\(|ShelfMoment\(|PosterFlight\(|addingPercentEncoding|closeApp\("#

    func testTitlesGoThroughOneDoor() throws {
        let files = try sources(["Design", "Screens"])
        let receiver = #"(?<who>[A-Za-z_][A-Za-z0-9_]*(?:\??\.[A-Za-z_][A-Za-z0-9_]*)*)"#
        let read = #"(?:Text\((?:verbatim: )?|accessibilityLabel\((?:Text\((?:verbatim: )?)?|subject: Text\(verbatim: |[(,] *title: | \? |\{ return |\\\()"#
        let pattern = read + receiver + #"\??\.(?<what>title|name|show|showTitle|displayTitle|originalTitle)\b(?!\s*[({])"#
        let regex = try NSRegularExpression(pattern: pattern)
        var raw: [String] = []
        for file in files where file.name != "TitleName.swift" && !file.path.contains("Support/") {
            for (i, line) in file.lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || line.contains("no-es-título:") || line.range(of: Self.carriesTheName, options: .regularExpression) != nil { continue }
                for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                    guard let range = Range(match.range(withName: "who"), in: line),
                          let what = Range(match.range(withName: "what"), in: line) else { continue }
                    let who = String(line[range]).replacingOccurrences(of: "?", with: "")
                    let last = who.components(separatedBy: ".").last ?? who
                    if Self.notATitle[who] != nil || Self.notATitle["\(who).\(line[what])"] != nil || (who.contains(".") && Self.notATitle[last] != nil) { continue }
                    raw.append("\(file.path):\(i + 1): \(code.prefix(140))")
                }
            }
        }
        XCTAssertEqual(raw, [], "Estas vistas pintan el nombre de un título sin pasar por `titleName(…)` (un solo nombre por título):\n" + raw.joined(separator: "\n"))
    }
}
