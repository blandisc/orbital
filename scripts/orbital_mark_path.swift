// La marca de Orbital como trazo para el símbolo: el mismo dibujo de `OrbitalMark` (ios/App/Sources/Design/Brand.swift) y de
// scripts/make_icon.py: el planeta de contorno con el hueco limpio donde le cruza el anillo, el anillo como pincelada que
// engorda al frente y termina en punta, y la luna sobre su órbita. Los recortes los hace CoreGraphics (macOS 14 o más).
//
// Uso: swift scripts/orbital_mark_path.swift <planeta> <anillo-afuera> <anillo-adentro> <hueco> <luna>
// Imprime los comandos del trazo (JSON) en la caja de 32; scripts/orbital_symbol.py los pone en la hoja de SF Symbols.
import CoreGraphics
import Foundation

let a = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard a.count == 5 else { FileHandle.standardError.write("Faltan medidas\n".data(using: .utf8)!); exit(1) }
let (planetW, outer, inner, gap, moonR) = (a[a.startIndex], a[a.startIndex + 1], a[a.startIndex + 2], a[a.startIndex + 3], a[a.startIndex + 4])

// Las medidas de DS.Brand (Tokens.swift): caja de 32, planeta de 7.2, anillo de 14.51 inclinado -18.8°.
let center = 16.0, planetR = 7.2, ringR = 14.51, tilt = -18.8 * Double.pi / 180
func point(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: center + x * cos(tilt) - y * sin(tilt), y: center + x * sin(tilt) + y * cos(tilt))
}

let ring = CGMutablePath()
let c = 0.55 * ringR
ring.move(to: point(-ringR, 0))
ring.addCurve(to: point(ringR, 0), control1: point(-c, outer / 0.75), control2: point(c, outer / 0.75))
ring.addCurve(to: point(-ringR, 0), control1: point(c, inner / 0.75), control2: point(-c, inner / 0.75))
ring.closeSubpath()

let circle = CGPath(ellipseIn: CGRect(x: center - planetR, y: center - planetR, width: 2 * planetR, height: 2 * planetR), transform: nil)
let hole = ring.copy(strokingWithWidth: gap, lineCap: .round, lineJoin: .round, miterLimit: 10).union(ring)
let planet = circle.copy(strokingWithWidth: planetW, lineCap: .butt, lineJoin: .miter, miterLimit: 10).subtracting(hole)

// La luna principal de make_icon.py (a -49° de la órbita 570 × 223 del cuadro de 1024), en la escala de la caja de 32.
let k = planetR / 160, t = -49 * Double.pi / 180
let moon = point(570 * cos(t) * k, 223 * sin(t) * k)
let moonPath = CGPath(ellipseIn: CGRect(x: moon.x - moonR, y: moon.y - moonR, width: 2 * moonR, height: 2 * moonR), transform: nil)

let mark = planet.union(ring).union(moonPath)
var out: [[Any]] = []
mark.applyWithBlock { element in
    let p = element.pointee.points
    switch element.pointee.type {
    case .moveToPoint: out.append(["M", p[0].x, p[0].y])
    case .addLineToPoint: out.append(["L", p[0].x, p[0].y])
    case .addQuadCurveToPoint: out.append(["Q", p[0].x, p[0].y, p[1].x, p[1].y])
    case .addCurveToPoint: out.append(["C", p[0].x, p[0].y, p[1].x, p[1].y, p[2].x, p[2].y])
    case .closeSubpath: out.append(["Z"])
    @unknown default: break
    }
}
print(String(data: try! JSONSerialization.data(withJSONObject: out), encoding: .utf8)!)
