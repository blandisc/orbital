// El ícono de la app de iPhone con la marca de la TV (orbital/web/js/core/icons.js · mark), igual al de Windows
// (scripts/make_icon.py): el planeta de contorno, el anillo
// que lo cruza por delante y la luna como un punto aparte arriba a la derecha (el mismo gesto que el punto de «orbital»).
// Sin la palabra. Tres variantes para iOS: la de siempre (papel sobre grafito), la oscura (fondo transparente: iOS pone el
// suyo) y la teñida (grises sobre negro: iOS la tiñe).
//
//   swift scripts/app_icon.swift
import AppKit
import CoreGraphics

let side = 1024
let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("ios/App/Resources/Assets.xcassets/AppIcon.appiconset")

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// La misma composición que el ícono de Windows (scripts/make_icon.py, caja de 256): su cuadro útil (8…248) llena el ícono
// de iOS, que pone las esquinas él solo. La marca centrada en (124, 130) a 5.2 veces su caja de 32; la luna en (196, 62).
let box = (origin: 8.0, side: 240.0)
let px = CGFloat(side) / CGFloat(box.side)

func render(_ name: String, background: (top: CGColor, bottom: CGColor)?, ink: CGColor, cut: CGColor?) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // De la caja de 256 (y hacia abajo) a píxeles (y hacia arriba).
    ctx.translateBy(x: 0, y: CGFloat(side)); ctx.scaleBy(x: px, y: -px); ctx.translateBy(x: -box.origin, y: -box.origin)
    if let background {
        // Grafito, de #1e1e23 arriba a la izquierda a #0c0c0e (el radial de make_icon.py: centro 40 % · 30 %, radio 80 %).
        let gradient = CGGradient(colorsSpace: space, colors: [background.top, background.bottom] as CFArray, locations: [0, 1])!
        let center = CGPoint(x: box.origin + 0.4 * box.side, y: box.origin + 0.3 * box.side)
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 0.8 * box.side,
                               options: [.drawsAfterEndLocation])
    }
    ctx.saveGState()
    ctx.translateBy(x: 124, y: 130); ctx.scaleBy(x: 5.2, y: 5.2); ctx.translateBy(x: -16, y: -16)
    ctx.setLineCap(.round)
    func ring() {
        ctx.move(to: CGPoint(x: 3.2, y: 20.4))
        ctx.addCurve(to: CGPoint(x: 29.2, y: 11.6), control1: CGPoint(x: 7.0, y: 23.5), control2: CGPoint(x: 24.4, y: 18.0))
    }
    // El planeta.
    ctx.setStrokeColor(ink); ctx.setLineWidth(2.8)
    ctx.strokeEllipse(in: CGRect(x: 16 - 7.2, y: 16 - 7.2, width: 14.4, height: 14.4))
    // El corte bajo el anillo (del color del fondo; sin fondo, transparente): se lee que pasa por delante.
    if let cut { ctx.setStrokeColor(cut) } else { ctx.setBlendMode(.clear) }
    ctx.setLineWidth(5); ring(); ctx.strokePath()
    ctx.setBlendMode(.normal)
    // El anillo.
    ctx.setStrokeColor(ink); ctx.setLineWidth(2.1); ring(); ctx.strokePath()
    ctx.restoreGState()
    // La luna.
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: 196 - 11, y: 62 - 11, width: 22, height: 22))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

let paper = rgb(0xf5f4f0)
try render("AppIcon.png", background: (rgb(0x1e1e23), rgb(0x0c0c0e)), ink: paper, cut: rgb(0x141417))
try render("AppIcon-Dark.png", background: nil, ink: paper, cut: nil)
try render("AppIcon-Tinted.png", background: (rgb(0x000000), rgb(0x000000)), ink: rgb(0xffffff), cut: rgb(0x000000))
print("Ícono listo en \(out.path)")
