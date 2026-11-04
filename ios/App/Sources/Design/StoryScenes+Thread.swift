import SwiftUI

// Escenas de «Aprende Orbital»: no perder el hilo (H5) y tu TV (H6). Ver `StoryScenes.swift`.

/// La barrita de «Seguir viendo» al 40 % se despega del iPhone y cae en el iPad, en el mismo punto.
struct SceneHandoff: View {
    var body: some View {
        SceneLoop(steps: 3) { step in
            VStack(spacing: DS.Space.s4) {
                SceneDevice(symbol: "iphone", label: Text(verbatim: "iPhone"), progress: step == 0 ? DS.Opacity.faint + DS.Opacity.selectedFill : nil)
                Image(systemName: "arrow.down").font(DS.TextRecipe.section.font).foregroundStyle(step == 1 ? DS.fresh : DS.textFaint)
                SceneDevice(symbol: "ipad.landscape", label: Text(verbatim: "iPad"), progress: step == 2 ? DS.Opacity.faint + DS.Opacity.selectedFill : nil)
            }
            .padding(DS.Space.s3)
        }
    }
}

/// Un aparato con lo que ve: su ícono, su nombre y, si está viendo, la barrita de avance.
struct SceneDevice: View {
    let symbol: String
    let label: Text
    var progress: Double?

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: symbol).font(DS.TextRecipe.section.font).foregroundStyle(DS.text)
                label.recipe(.footnote, color: DS.textMuted)
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                Capsule().fill(DS.fill).overlay(alignment: .leading) {
                    if let progress { Capsule().fill(DS.fresh).frame(width: geo.size.width * progress).transition(.opacity) }
                }
            }
            .frame(height: DS.Scene.line)
        }
        .padding(DS.Space.s3)
        .dsCard(.card)
    }
}

/// «Porque viste Interestelar» y tres carteles que caen en su fila, uno tras otro.
struct SceneBecause: View {
    var body: some View {
        SceneLoop(steps: 4) { step in
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Porque viste Interestelar").recipe(.footnote, color: DS.eyebrow)
                HStack(spacing: DS.Space.s2) {
                    ForEach(0..<3, id: \.self) { i in
                        ScenePoster(title: ["Arrival", "Dune", "Gravity"][i], tint: [DS.ListTint.spark, DS.ListTint.flame, DS.ListTint.series][i])
                            .offset(y: step > i ? 0 : -DS.Scene.maxHeight / 3)
                            .opacity(step > i ? 1 : 0)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
        }
    }
}

/// Sigues una serie y la escena pasa a la pantalla bloqueada con su aviso del día del estreno.
struct SceneLockAlert: View {
    var body: some View {
        SceneLoop(steps: 3) { step in
            ZStack(alignment: .top) {
                if step < 2 {
                    VStack(spacing: DS.Space.s2) {
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.ListTint.series.opacity(DS.Opacity.dimmed))
                            .overlay { Text(verbatim: "The Bear").recipe(.title, color: DS.paper) }
                        SceneButton(title: step == 1 ? "Siguiendo" : "Seguir", symbol: step == 1 ? "checkmark" : "plus", prominent: false, pressed: step == 1)
                            .overlay { SceneFinger(pressed: step == 1, shown: step == 1) }
                    }
                    .padding(DS.Space.s3)
                } else {
                    VStack(spacing: DS.Space.s3) {
                        Text(verbatim: "9:41").recipe(.display, color: DS.paper).padding(.top, DS.Space.s8)
                        SceneNotice(symbol: "calendar", text: Text("Sale hoy: The Bear T4 · E1")).transition(.move(edge: .top).combined(with: .opacity))
                    }
                    .padding(DS.Space.s2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(DS.backdropDeep)
                }
            }
        }
    }
}

/// El calendario del mes: los carteles caen en sus días como fichas.
struct SceneCalendar: View {
    var body: some View {
        SceneLoop(steps: 4) { step in
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Noviembre").recipe(.cardTitle, color: DS.text)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s1), count: 7), spacing: DS.Space.s1) {
                    ForEach(1...28, id: \.self) { day in
                        let release = [4: 1, 12: 2, 19: 3][day]
                        RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                            .fill(release.map { step >= $0 } == true ? DS.ListTint.calendar.opacity(DS.Opacity.dimmed) : DS.fill)
                            .aspectRatio(DS.Poster.aspect, contentMode: .fit)
                            .overlay { Text(verbatim: "\(day)").recipe(.footnote, color: DS.textMuted) }
                            .scaleEffect(release == step ? DS.Scene.lifted : 1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
        }
    }
}

/// Ajustes › Avisos: tres interruptores y el dedo apaga uno.
struct SceneToggles: View {
    var body: some View {
        SceneLoop(steps: 3) { step in
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Avisos").recipe(.cardTitle, color: DS.text)
                ForEach(["The Bear", "Severance", "Fargo"], id: \.self) { name in
                    SceneRow(title: Text(verbatim: name)) {
                        Capsule().fill(name == "Fargo" && step >= 1 ? DS.fill : DS.success)
                            .frame(width: DS.Scene.finger * 1.4, height: DS.Scene.finger * 0.8)
                            .overlay(alignment: name == "Fargo" && step >= 1 ? .leading : .trailing) {
                                Circle().fill(DS.paper).padding(DS.Space.s1 / 2)
                            }
                            .overlay { if name == "Fargo" { SceneFinger(pressed: step == 1, shown: step == 1) } }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
        }
    }
}

/// Lo que ves: las horas suben, salen tus tres géneros y se abre tu Wrapped.
struct SceneYear: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SceneLoop(steps: 4) { step in
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("Tu año").recipe(.footnote, color: DS.textMuted)
                Text(verbatim: ["0", "96", "214", "214"][step]).recipe(.display, color: DS.text).contentTransition(.numericText())
                Text("horas").recipe(.footnote, color: DS.textMuted)
                HStack(spacing: DS.Space.s2) {
                    ForEach(Array(["Drama", "Ciencia ficción", "Comedia"].enumerated()), id: \.offset) { i, g in
                        Text(LocalizedStringKey(g)).recipe(.footnote, color: DS.text).lineLimit(1)
                            .opacity(step >= 2 ? 1 : 0).offset(y: step >= 2 ? 0 : DS.Space.s2)
                            .animation(DS.Motion.spring(reduceMotion)?.delay(Double(i) * DS.Motion.entranceStep), value: step)
                    }
                }
                Spacer(minLength: 0)
                if step == 3 {
                    Label("Compartir", systemImage: "square.and.arrow.up").recipe(.label, color: DS.onPrimary)
                        .frame(maxWidth: .infinity).padding(DS.Space.s2).background(DS.primary, in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(DS.Space.s3)
        }
    }
}

// MARK: H6 · Tu TV

/// El control del iPhone al frente; atrás, fuera de foco, la TV responde a cada deslizamiento.
struct SceneRemote: View {
    var body: some View {
        SceneLoop(steps: 4) { step in
            ZStack {
                SceneTV(highlight: step % 3).blur(radius: DS.Space.s1).opacity(DS.Opacity.dimmed).padding(DS.Space.s2)
                Circle().fill(DS.surface).frame(width: DS.Scene.finger * 3.2, height: DS.Scene.finger * 3.2)
                    .overlay { SceneFinger(pressed: true).offset(x: CGFloat(step % 3 - 1) * DS.Scene.finger / 2) }
                    .offset(y: DS.Scene.finger * 2)
            }
        }
    }
}

/// La TV en miniatura con una fila de carteles (la que está enfocada, más grande).
struct SceneTV: View {
    var highlight: Int = -1
    var playing = false

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(DS.backdropDeep)
                if playing { ScenePlayerFrame(playing: true, progress: DS.Opacity.faint).padding(DS.Space.s1) }
                else {
                    HStack(spacing: DS.Space.s1) {
                        ForEach(0..<3, id: \.self) { i in
                            ScenePoster(title: "", tint: [DS.ListTint.flame, DS.ListTint.series, DS.ListTint.spark][i])
                                .scaleEffect(i == highlight ? DS.Scene.lifted : DS.Scene.pressed)
                        }
                    }
                    .padding(DS.Space.s2)
                }
            }
            .aspectRatio(DS.Poster.stillAspect, contentMode: .fit)
            Capsule().fill(DS.fill).frame(width: DS.Scene.finger * 2, height: DS.Scene.line / 2)
        }
    }
}

/// «Ver en la TV»: el cartel vuela en arco a la TV y empieza; con `back`, el video baja de la TV al iPhone en el mismo punto.
struct SceneSendToTV: View {
    let back: Bool

    var body: some View {
        SceneLoop(steps: 3) { step in
            VStack(spacing: DS.Space.s4) {
                SceneTV(playing: back ? step < 2 : step >= 2)
                Image(systemName: back ? "arrow.down" : "arrow.up").font(DS.TextRecipe.section.font).foregroundStyle(step == 1 ? DS.fresh : DS.textFaint)
                SceneDevice(symbol: "iphone", label: back ? Text("Sigue aquí") : Text("Ver en la TV"),
                            progress: back && step == 2 ? DS.Opacity.faint + DS.Opacity.selectedFill : nil)
                    .overlay { if !back { SceneFinger(pressed: step == 1, shown: step == 1) } }
            }
            .padding(DS.Space.s3)
        }
    }
}

/// Mantener el micrófono: la onda de voz se mueve y la TV abre el episodio.
struct SceneVoice: View {
    var body: some View {
        SceneLoop(steps: 4) { step in
            VStack(spacing: DS.Space.s4) {
                SceneTV(playing: step >= 3)
                HStack(spacing: DS.Space.s1) {
                    ForEach(0..<7, id: \.self) { i in
                        Capsule().fill(DS.fresh)
                            .frame(width: DS.Scene.line / 2, height: step == 1 || step == 2 ? DS.Scene.line * CGFloat([2, 4, 6, 3, 5, 2, 4][(i + step) % 7]) : DS.Scene.line)
                    }
                }
                Text("«Pon la siguiente de The Bear»").recipe(.footnote, color: step >= 1 ? DS.text : DS.textFaint)
                Image(systemName: "mic.fill").font(DS.TextRecipe.title.font).foregroundStyle(DS.paper)
                    .frame(width: DS.Scene.finger * 2, height: DS.Scene.finger * 2).background(DS.surface, in: Circle())
                    .overlay { SceneFinger(pressed: step == 1 || step == 2, shown: step == 1 || step == 2) }
            }
            .padding(DS.Space.s3)
        }
    }
}
