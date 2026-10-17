// El ícono de la app de iPhone con la marca de la TV (orbital/web/js/core/icons.js · mark): el planeta de contorno, el anillo
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

// La caja de 32 de la marca, la luna y cuánto ocupa todo: centrado, ~62 % del ancho del ícono.
let moon = (x: 26.0, y: 6.6, r: 1.9)
let bounds = CGRect(x: 2.15, y: 4.7, width: 30.25 - 2.15, height: 24.6 - 4.7)
let scale = CGFloat(side) * 0.62 / bounds.width

func render(_ name: String, background: [CGColor]?, ink: CGColor, ring: CGColor) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let background {
        // Un degradado muy leve de arriba abajo (grafito): profundidad sin dibujar nada más.
        let gradient = CGGradient(colorsSpace: space, colors: background as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: [])
    }
    // De la caja de 32 (y hacia abajo) a píxeles (y hacia arriba), centrado.
    ctx.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: -bounds.midX, y: -bounds.midY)
    ctx.setLineCap(.round)
    // El planeta.
    ctx.setStrokeColor(ink); ctx.setLineWidth(2.8)
    ctx.strokeEllipse(in: CGRect(x: 16 - 7.2, y: 16 - 7.2, width: 14.4, height: 14.4))
    // El anillo, por delante.
    ctx.setStrokeColor(ring); ctx.setLineWidth(2.1)
    ctx.move(to: CGPoint(x: 3.2, y: 20.4))
    ctx.addCurve(to: CGPoint(x: 29.2, y: 11.6), control1: CGPoint(x: 7.0, y: 23.5), control2: CGPoint(x: 24.4, y: 18.0))
    ctx.strokePath()
    // La luna.
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: moon.x - moon.r, y: moon.y - moon.r, width: 2 * moon.r, height: 2 * moon.r))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

let paper = 0xf5f4f0
// El anillo al 70 % sobre el fondo, ya mezclado (sin transparencia: así no se ve el planeta a través donde se cruzan).
try render("AppIcon.png", background: [rgb(0x18181c), rgb(0x0c0c0e)], ink: rgb(paper), ring: rgb(0xb0afac))
try render("AppIcon-Dark.png", background: nil, ink: rgb(paper), ring: rgb(paper, 0.7))
try render("AppIcon-Tinted.png", background: [rgb(0x000000), rgb(0x000000)], ink: rgb(0xffffff), ring: rgb(0xb3b3b3))
print("Ícono listo en \(out.path)")
