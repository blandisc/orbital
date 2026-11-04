import SwiftUI

// Escenas de «Aprende Orbital»: encontrar qué ver (H3) y ver a tu manera (H4). Ver `StoryScenes.swift`.

private let sampleTitles = ["Dune", "The Bear", "Interestelar", "Coco", "Severance", "Roma", "Fargo", "Arrival", "Barbie"]
private let sampleTints = [DS.ListTint.flame, DS.ListTint.series, DS.ListTint.spark, DS.ListTint.list, DS.ListTint.bookmark,
                           DS.ListTint.trend, DS.ListTint.library, DS.ListTint.calendar, DS.ListTint.watching]

/// El mosaico de Explorar que deriva lento; con `zoom`, el dedo toca un cartel que crece, y el segundo toque abre su ficha.
struct SceneMosaic: View {
    let zoom: Bool

    var body: some View {
        SceneLoop(steps: 4) { step in
            ZStack {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s1), count: 3), spacing: DS.Space.s1) {
                    ForEach(0..<9, id: \.self) { i in
                        ScenePoster(title: sampleTitles[i], tint: sampleTints[i])
                            .scaleEffect(zoom && i == 4 && step >= 1 ? DS.Scene.lifted * DS.Scene.lifted : 1)
                            .zIndex(i == 4 ? 1 : 0)   // ds-exception: el que se acerca va encima
                    }
                }
                .padding(DS.Space.s2)
                .offset(y: zoom ? 0 : -CGFloat(step) * DS.Space.s3)
                if zoom {
                    SceneFinger(pressed: step == 1 || step == 2, shown: step == 1 || step == 2)
                    if step == 3 {
                        VStack(spacing: DS.Space.s2) {
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(sampleTints[4].opacity(DS.Opacity.dimmed))
                                .overlay { Text(verbatim: sampleTitles[4]).recipe(.title, color: DS.paper) }
                            SceneButton(title: "Ver", symbol: "play.fill")
                        }
                        .padding(DS.Space.s3).background(DS.bg)
                        .transition(.scale(scale: DS.Motion.leaveScale).combined(with: .opacity))
                    }
                }
            }
        }
    }
}

/// «¿Qué vemos hoy?»: una carta sale a la izquierda (no) y la siguiente a la derecha (sí).
struct SceneDeck: View {
    var body: some View {
        SceneLoop(steps: 3, beat: DS.Scene.beat * 0.8) { step in
            ZStack {
                ForEach((0..<3).reversed(), id: \.self) { i in
                    let away = i < step
                    ScenePoster(title: sampleTitles[i + 1], tint: sampleTints[i + 1])
                        .padding(DS.Space.s6)
                        .overlay(alignment: .top) {
                            if away { Image(systemName: i == 0 ? "xmark.circle.fill" : "checkmark.circle.fill").font(DS.TextRecipe.title.font).foregroundStyle(i == 0 ? DS.danger : DS.success).padding(DS.Space.s8) }
                        }
                        .rotationEffect(.degrees(away ? (i == 0 ? -14 : 14) : 0))   // ds-exception: la inclinación de la carta al volar
                        .offset(x: away ? (i == 0 ? -DS.Scene.maxHeight / 2 : DS.Scene.maxHeight / 2) : 0, y: CGFloat(i - step) * DS.Space.s1)
                        .opacity(away ? 0 : 1)
                }
            }
        }
    }
}

/// «Decide por mí»: tres carteles con su porqué; el dedo baraja y salen otros.
struct SceneDecide: View {
    var body: some View {
        SceneLoop(steps: 3) { step in
            VStack(spacing: DS.Space.s3) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(0..<3, id: \.self) { i in
                        let k = step == 2 ? i + 4 : i
                        VStack(spacing: DS.Space.s1) {
                            ScenePoster(title: sampleTitles[k], tint: sampleTints[k])
                            Text("Porque viste Coco").recipe(.footnote, color: DS.eyebrow).lineLimit(2).multilineTextAlignment(.center)
                        }
                        .rotation3DEffect(.degrees(step == 1 ? 90 : 0), axis: (x: 0, y: 1, z: 0))   // ds-exception: giran como cartas al barajar
                    }
                }
                SceneButton(title: "Barajar", symbol: "shuffle", prominent: false, pressed: step == 1)
                    .overlay { SceneFinger(pressed: step == 1, shown: step == 1) }
            }
            .padding(DS.Space.s3)
        }
    }
}

/// Los cuadros de filtros de Buscar: se encienden uno a uno y el contador baja; quitar uno lo hace subir.
struct SceneFilters: View {
    private let tiles: [(LocalizedStringKey, String)] = [("Comedia", "theatermasks.fill"), ("Años 90", "calendar"), ("Netflix", "play.tv.fill"), ("Más de 7", "star.fill")]
    private let counts = ["2 400", "640", "92", "37", "92"]

    var body: some View {
        SceneLoop(steps: 5) { step in
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("Buscar").recipe(.cardTitle, color: DS.text)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s2), GridItem(.flexible())], spacing: DS.Space.s2) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { i, tile in
                        let on = step == 4 ? i < 2 || i == 3 : i < step
                        Label(tile.0, systemImage: tile.1).recipe(.footnote, color: on ? DS.text : DS.textMuted)
                            .padding(DS.Space.s2).frame(maxWidth: .infinity, alignment: .leading)
                            .dsCard(.row, fill: on ? DS.ListTint.spark.opacity(DS.Opacity.selectedFill * 2) : nil)
                            .scaleEffect(i == step - 1 ? DS.Scene.pressed : 1)
                    }
                }
                Text("\(counts[step]) títulos").recipe(.cardTitle, color: DS.fresh).contentTransition(.numericText())
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
        }
    }
}

// MARK: H4 · Ver a tu manera

/// El reproductor: sin controles (ondas donde caen los dedos), doble toque que suma 10 s, pellizcar para llenar o el candado.
struct ScenePlayer: View {
    enum Gesture { case none, doubleTap, pinch, lock }
    let gesture: Gesture

    var body: some View {
        SceneLoop(steps: 4) { step in
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    ScenePlayerFrame(playing: true, progress: gesture == .doubleTap ? Double(step) / 6 : DS.Opacity.faint, filled: gesture == .pinch && step >= 2)
                    switch gesture {
                    case .none:
                        ForEach(0..<3, id: \.self) { i in
                            Circle().strokeBorder(DS.paper.opacity(step == i ? DS.Opacity.dimmed : 0), lineWidth: DS.Stroke.selected)
                                .frame(width: DS.Scene.finger * 2, height: DS.Scene.finger * 2)
                                .position(x: w * [0.2, 0.5, 0.8][i], y: h / 2)   // ds-exception: las tres zonas del reproductor
                        }
                    case .doubleTap:
                        SceneFinger(pressed: step >= 1, shown: step >= 1).position(x: w * 0.82, y: h / 2)   // ds-exception: la orilla derecha
                        if step >= 1 { Text(verbatim: "+\(step * 10)").recipe(.title, color: DS.paper).position(x: w * 0.82, y: h / 2 - DS.Scene.finger * 1.6).id(step).transition(.scale.combined(with: .opacity)) }
                    case .pinch:
                        let spread = step >= 1 ? DS.Scene.finger * 2 : DS.Scene.finger / 2
                        SceneFinger(pressed: true, shown: step >= 1 && step < 3).position(x: w / 2 - spread, y: h / 2 - spread)
                        SceneFinger(pressed: true, shown: step >= 1 && step < 3).position(x: w / 2 + spread, y: h / 2 + spread)
                    case .lock:
                        VStack(spacing: DS.Space.s2) {
                            Spacer()
                            Label(step >= 2 ? "Bloqueado" : "Más", systemImage: step >= 2 ? "lock.fill" : "ellipsis.circle").recipe(.label, color: DS.paper)
                                .padding(DS.Space.s2).background(DS.scrim, in: Capsule())
                                .scaleEffect(step == 1 ? DS.Scene.pressed : 1)
                        }
                        .padding(DS.Space.s4)
                        SceneFinger(pressed: step == 1 || step == 3, shown: step == 1 || step == 3)
                            .position(x: w / 2, y: step == 3 ? h * 0.4 : h - DS.Space.s8)   // ds-exception: el toque que ya no hace nada
                    }
                }
            }
        }
    }
}

/// Descargar: el anillo se llena y aparece en Biblioteca, y aquí sí sube el espacio; con `next`, el siguiente episodio baja solo.
struct SceneDownload: View {
    let next: Bool

    var body: some View {
        SceneLoop(steps: 4) { step in
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("Biblioteca").recipe(.cardTitle, color: DS.text)
                SceneRow(title: next ? Text(verbatim: "T1 · E4") : Text(verbatim: "Dune")) {
                    if next || step >= 2 { Image(systemName: next && step >= 1 ? "checkmark.circle.fill" : "arrow.down.circle.fill").foregroundStyle(next && step >= 1 ? DS.success : DS.fresh) }
                    else { SceneRing(progress: Double(step) / 2) }
                }
                .overlay { if !next { SceneFinger(pressed: step == 0, shown: step == 0) } }
                if next {
                    SceneRow(title: Text(verbatim: "T1 · E5")) { SceneRing(progress: step >= 2 ? Double(step - 1) / 2 : 0) }
                        .opacity(step >= 1 ? 1 : DS.Opacity.dimmed)
                } else {
                    Text("Espacio en tu iPhone").recipe(.footnote, color: DS.textMuted)
                    GeometryReader { geo in
                        Capsule().fill(DS.fill).overlay(alignment: .leading) {
                            Capsule().fill(DS.text).frame(width: geo.size.width * (DS.Opacity.faint + (step >= 2 ? DS.Opacity.selectedFill * 2 : 0)))
                        }
                    }
                    .frame(height: DS.Scene.line)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
        }
    }
}

/// Un anillo de descarga que se llena.
struct SceneRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(DS.fill, lineWidth: DS.Stroke.selected)
            Circle().trim(from: 0, to: progress).stroke(DS.fresh, style: StrokeStyle(lineWidth: DS.Stroke.selected, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .frame(width: DS.Scene.finger * 0.7, height: DS.Scene.finger * 0.7)
    }
}
