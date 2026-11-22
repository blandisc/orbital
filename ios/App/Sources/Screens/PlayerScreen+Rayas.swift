import SwiftUI
import OrbitalCore
import OrbitalModels

/// Las rayas negras pintadas a los lados dentro del archivo (un 4:3 rellenado a 16:9). Se miran unos cuadros del video que suena;
/// si todos traen la misma raya pareja a los dos lados, en vertical el recuadro toma la forma de la imagen de verdad y el motor
/// la llena (las rayas quedan fuera), como un 4:3 de verdad (Los Simpson). Acostado no cambia nada: la imagen completa ya las
/// muestra igual que a un 4:3. (Parte de `PlayerScreen`, separada por responsabilidad.)
extension PlayerScreen {
    /// El tamaño del cuadro que se mira: chico basta para encontrar una orilla y no gasta memoria.
    private static let barsSample = CGSize(width: 192, height: 108)

    func watchPictureBars() async {
        pictureAspect = nil   // cada versión trae (o no) sus rayas
        var samples: [PictureBars.Sides] = []
        for _ in 0..<DS.Timing.pictureBarsTries {
            guard (try? await Task.sleep(for: DS.Timing.pictureBarsGap)) != nil else { return }
            let engine = holder.engine
            guard appActive, holder.model.phase == .playing, holder.model.snapshot.state == .playing, engine.showsVideo,
                  let frameAspect = engine.videoAspect,
                  let image = await engine.stillFrame(maxSize: Self.barsSample),
                  let sides = Self.sides(of: image) else { continue }
            samples.append(sides)
            guard samples.count >= PictureBars.samplesNeeded else { continue }
            if let aspect = PictureBars.pictureAspect(frameAspect: frameAspect, samples: samples) {
                PlayerModel.note(String(format: "rayas pintadas a los lados (%.0f %% y %.0f %%): la imagen es %.2f, no %.2f",
                                        samples.map(\.left).min()! * 100, samples.map(\.right).min()! * 100, aspect, frameAspect))
                withAnimation(DS.Motion.base(reduceMotion)) { pictureAspect = aspect }
            }
            return
        }
    }

    /// El cuadro en grises, renglón por renglón, y lo negro de cada lado.
    private static func sides(of image: UIImage) -> PictureBars.Sides? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var luma = [UInt8](repeating: 0, count: width * height)
        let drawn = luma.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? PictureBars.sides(luma: luma, width: width, height: height) : nil
    }
}
