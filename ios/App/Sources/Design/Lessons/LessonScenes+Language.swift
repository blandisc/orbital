import SwiftUI

// «En tu idioma» (prototipo `scenes.js`, i-pick … i-try): cómo elige «Ver», el orden de tus idiomas, otra versión y el
// panel de audio y subtítulos dentro del video, y «Pruébalo». Medidas del lienzo de 402 × 330.

/// Un idioma de tu lista: su lugar, su bandera y su nombre; el de arriba se marca en turquesa cuando «Ver» lo elige.
struct LessonLanguageRow: View {
    let place: Int
    let flag: String?
    let name: Text
    var marked = false
    var lifted = false
    var handle = false

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Text(verbatim: "\(place)").font(DS.TextRecipe.badge.font).monospacedDigit().foregroundStyle(DS.textMuted)
                .sceneBox(DS.Lesson.placeDot, DS.Lesson.placeDot).background(DS.fillStrong, in: Circle())
            HStack(spacing: DS.Space.s1) {
                if let flag, let mark = Text.flagMark(flag) { mark }
                name
            }
            .font(DS.TextRecipe.secondary.font).foregroundStyle(DS.text).lineLimit(1)
            Spacer(minLength: 0)
            if handle { Image(systemName: "line.3.horizontal").font(DS.TextRecipe.label.font).foregroundStyle(DS.textFaint) }
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(height: DS.Lesson.languageRow)
        .dsCard(fill: lifted ? DS.surfaceRaised : DS.fill)
        .overlay(RoundedRectangle(cornerRadius: DSCardLevel.row.radius, style: .continuous)
            .strokeBorder(DS.fresh, lineWidth: DS.Stroke.selected).opacity(marked || lifted ? 1 : 0))
        .shadow(lifted ? DS.Elevation.floating : DS.Elevation.floating.color(.clear))
    }
}

/// Cómo decide «Ver»: tu lista de idiomas en orden y el primero que haya gana; el hilo une tu primer idioma con lo que va a
/// sonar.
struct LessonLanguagePick: View {
    let t: Double
    static let end = 1.9
    static let ranks: [(String?, LocalizedStringKey)] = [("es-MX", "Latino"), (nil, "Idioma original"), ("en-US", "Inglés"), ("es-ES", "Castellano")]

    var body: some View {
        let M = LessonMotion.self
        let ver = M.enter(t, 0.1), chip = M.spring(t - 1.2, 0.5, 0.2)
        ZStack(alignment: .topLeading) {
            Text("Tus idiomas").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text).sceneAt(24, 24).opacity(M.clamp(t / 0.25))
            ForEach(0..<3, id: \.self) { i in
                let e = M.enter(t, 0.05 + Double(i) * 0.04)
                LessonLanguageRow(place: i + 1, flag: Self.ranks[i].0, name: Text(Self.ranks[i].1), marked: i == 0 && t > 0.75)
                    .sceneBox(190, DS.Lesson.languageRow).sceneAt(24, CGFloat(60 + i * 58))
                    .scenePut(e.o * (i == 0 ? 1 : DS.Lesson.backup), 0, e.y)
            }
            LessonPlayButton(title: Text("Ver"), symbol: "play.fill").sceneBox(140, 40).sceneAt(238, 92).scenePut(ver.o, 0, ver.y)
            LessonThread(a: CGPoint(x: 214, y: 85), c: CGPoint(x: 226, y: 160), b: CGPoint(x: 252, y: 178), drawn: M.smooth(0.8, 1.2, t), dashed: false)
            LessonChip { Text.flagMark("es-MX"); Text("Latino · 1080p") }
                .scaleEffect(M.lerp(0.85, 1, chip)).sceneAt(252, 160).scenePut(M.clamp((t - 1.15) / 0.2), 0, (1 - chip) * -8)
            LessonFinger(t: t, x: 308, y: 112, at: 0.6)
        }
    }
}

/// Reordenar con el dedo, como en Ajustes › Tus idiomas: mantienes presionado «Idioma original» (se hunde el dedo y se
/// levanta el renglón), sube al primer lugar y los demás le hacen espacio.
struct LessonLanguageOrder: View {
    let t: Double
    static let end = 2.4

    var body: some View {
        let M = LessonMotion.self
        let up = M.smooth(1.0, 1.6, t), lift = M.smooth(0.6, 0.8, t) * (1 - M.smooth(1.6, 1.8, t))
        let k = up, press = M.smooth(0.6, 0.7, t) * (1 - M.smooth(1.6, 1.7, t))
        ZStack(alignment: .topLeading) {
            Text("Tus idiomas").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text).sceneAt(24, 4)
            ForEach([0, 1, 3, 2], id: \.self) { i in
                let e = M.enter(t, 0.05 + Double(i) * 0.03, 10)
                let dy: CGFloat = i == 1 ? -60 * up : i == 0 ? 60 * up : 0
                let place = i == 1 ? (up > 0.5 ? 1 : 2) : i == 0 ? (up > 0.5 ? 2 : 1) : i + 1
                LessonLanguageRow(place: place, flag: LessonLanguagePick.ranks[i].0, name: Text(LessonLanguagePick.ranks[i].1),
                                  lifted: i == 1 && lift > 0.05, handle: true)
                    .sceneBox(354, DS.Lesson.languageRow).scaleEffect(1 + 0.04 * lift).sceneAt(24, CGFloat(40 + i * 60))
                    .scenePut(e.o, 0, e.y + dy)
            }
            Circle().fill(DS.paper.opacity(DS.Lesson.fingerFill))
                .overlay(Circle().strokeBorder(DS.paper.opacity(DS.Lesson.fingerRim), lineWidth: DS.Stroke.regular))
                .sceneBox(DS.Lesson.finger, DS.Lesson.finger)
                .scenePut(M.clamp((t - 0.4) / 0.2) * (1 - M.smooth(1.75, 1.95, t)) * DS.Lesson.fingerOpacity,
                          CGFloat(348) - DS.Lesson.finger / 2, CGFloat(125) - DS.Lesson.finger / 2 - CGFloat(60 * k), 1 - DS.Lesson.fingerPress * CGFloat(press))
        }
    }
}

/// Dónde está «otra versión»: la bandera junto a «Ver». Se marca con un anillo, se toca y sube la hoja de versiones.
struct LessonLanguageOther: View {
    let t: Double
    let art: LessonArt
    static let end = 2.2

    var body: some View {
        let M = LessonMotion.self
        let e = M.enter(t, 0.05), sheet = M.spring(t - 0.95, 0.5, 0.05)
        let ring = M.smooth(0.55, 0.75, t) * (1 - M.smooth(1.05, 1.25, t))
        ZStack(alignment: .topLeading) {
            LessonPoster(item: art.movie(0), w: 120, h: 180).sceneAt(40, 24).scenePut(e.o, 0, e.y)
            LessonPlayButton(title: Text("Ver"), symbol: "play.fill").sceneBox(136, 40).sceneAt(178, 92).scenePut(e.o, 0, e.y)
            (Text.flagMark("es-MX") ?? Text(verbatim: "")).font(DS.TextRecipe.cardTitle.font)
                .sceneBox(40, 40).background(DS.fillStrong, in: Circle())
                .overlay(Circle().stroke(DS.fresh, lineWidth: DS.Lesson.tryRing * 1.5 * ring).padding(-DS.Lesson.tight))
                .sceneAt(324, 92).scenePut(e.o, 0, e.y)
            // Al subir la hoja, lo de atrás se oscurece: se lee «se abrió una hoja», no una tarjeta más.
            DS.scrim.sceneBox(402, 330).opacity(M.smooth(0.95, 1.15, t))
            LessonCard(title: Text("Versión"), w: 378) {
                LessonRow(title: Text("Latino")) { Text.flagMark("es-MX") } trailing: {
                    Image(systemName: "checkmark").font(DS.TextRecipe.label.font).foregroundStyle(DS.fresh)
                }
                LessonRow(title: Text("Inglés")) { Text.flagMark("en-US") } trailing: { EmptyView() }
            }
            .sceneAt(12, 170).scenePut(M.clamp((t - 0.95) / 0.1), 0, (1 - sheet) * 160)
            LessonFinger(t: t, x: 344, y: 112, at: 0.85)
        }
    }
}

/// El panel de audio y subtítulos dentro del video (en miniatura): dos grupos de opciones, la elegida en turquesa.
struct LessonAudioPanel: View {
    var audio: Int
    var subs: Int
    var pickAudio: ((Int) -> Void)?
    var pickSubs: ((Int) -> Void)?
    static let audios: [LocalizedStringKey] = ["Latino", "Inglés"]
    static let subtitles: [LocalizedStringKey] = ["Ninguno", "Español", "Inglés"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(Text("Audio"))
            ForEach(Self.audios.indices, id: \.self) { i in option(Text(Self.audios[i]), on: audio == i, id: "audio-\(i)") { pickAudio?(i) } }
            header(Text("Subtítulos")).padding(.top, DS.Space.s1)
            ForEach(Self.subtitles.indices, id: \.self) { i in option(Text(Self.subtitles[i]), on: subs == i, id: "subs-\(i)") { pickSubs?(i) } }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s2)
        .sceneBox(DS.Lesson.panel, 208)
        .background(.ultraThinMaterial)
    }

    private func header(_ text: Text) -> some View {
        text.font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).padding(.leading, DS.Space.s2).frame(height: DS.Lesson.panelHeader)
    }

    private func option(_ name: Text, on: Bool, id: String, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack {
                name
                Spacer(minLength: 0)
                Image(systemName: "checkmark").opacity(on ? 1 : 0)
            }
            // Como el panel real: la elegida con palomita, sin relleno; el turquesa queda para lo que se toca y lo logrado.
            .font(on ? DS.TextRecipe.label.font : DS.TextRecipe.secondary.font)
            .foregroundStyle(DS.text)
            .padding(.horizontal, DS.Space.s2)
            .frame(height: DS.Lesson.panelRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pickAudio == nil)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("lesson-try-\(id)")
    }
}

/// El video de la escena del panel: el arte a lo ancho y, cuando hay subtítulos, la frase abajo (blanca, como en el
/// reproductor).
struct LessonSubtitledVideo: View {
    let item: LessonArt.Item
    let subs: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LessonVideo(item: item, w: 370, h: 208, showsBar: false)
            if subs > 0 {
                Text(verbatim: subs == 1 ? "—¿Lo ves? Ahí viene." : "—See it? Here it comes.")
                    .font(DS.TextRecipe.label.font).foregroundStyle(DS.subtitleText).shadow(DS.Elevation.low.color(DS.subtitleShadow))
                    .sceneBox(370 - DS.Lesson.panel, DS.Space.s6).padding(.bottom, DS.Space.s6)
                    .transition(.opacity.combined(with: .offset(y: DS.Space.s2)))
            }
        }
    }
}

/// Audio y subtítulos sin salir del video: el globo aparece, se toca, entra el panel y el dedo elige «Español»; el subtítulo
/// sale en el momento.
struct LessonLanguagePanel: View {
    let t: Double
    let art: LessonArt
    static let end = 2.2

    var body: some View {
        let M = LessonMotion.self
        let e = M.enter(t, 0.05, 14), panel = M.spring(t - 0.95, 0.5, 0.05)
        let on = t > 1.5
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                LessonSubtitledVideo(item: art.movie(0), subs: on ? 1 : 0)
                Image(systemName: "globe").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.paper)
                    .sceneBox(34, 34).background(DS.scrim, in: Circle())
                    .sceneAt(324, 12).opacity(M.smooth(0.5, 0.65, t) * (1 - M.smooth(0.95, 1.1, t)))
                DS.scrim.opacity(M.smooth(0.5, 0.65, t) * (1 - M.smooth(0.95, 1.1, t))).allowsHitTesting(false)
                LessonAudioPanel(audio: 0, subs: on ? 1 : 0)
                    .sceneAt(370 - DS.Lesson.panel, 0).scenePut(t > 0.95 ? 1 : 0, (1 - panel) * 180)
            }
            .sceneBox(370, 208).clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .sceneAt(16, 50).scenePut(e.o, 0, e.y)
            // Tocas la pantalla (salen los controles), luego el globo y luego «Español».
            LessonFinger(t: t, x: 201, y: 154, at: 0.45)
            LessonFinger(t: t, x: 357, y: 79, at: 0.9)
            LessonFinger(t: t, x: 301, y: 202, at: 1.45)
        }
    }
}

/// «Pruébalo»: el mismo panel, de verdad. Cambias el audio o pones subtítulos y lo ves en el video.
struct LessonLanguageTry: View {
    let t: Double
    let art: LessonArt
    let done: () -> Void
    @State private var audio = 0
    @State private var subs = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let e = LessonMotion.enter(t, 0.05, 14)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                LessonSubtitledVideo(item: art.movie(0), subs: subs)
                LessonAudioPanel(audio: audio, subs: subs,
                                 pickAudio: { i in withAnimation(DS.Motion.base(reduceMotion)) { audio = i }; if i != 0 { done() } },
                                 pickSubs: { i in withAnimation(DS.Motion.base(reduceMotion)) { subs = i }; if i != 0 { done() } })
                    .overlay(alignment: .top) {
                        if subs == 0 && audio == 0 { LessonTryRing().sceneBox(DS.Lesson.panel - DS.Space.s2, DS.Lesson.panelRow).offset(y: 136) }
                    }
                    .sceneAt(370 - DS.Lesson.panel, 0)
            }
            .sceneBox(370, 208).clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .sceneAt(16, 50).scenePut(e.o, 0, e.y)
            if subs > 0 || audio > 0 {
                LessonCaption(text: subs == 1 ? Text("Subtítulos en español") : subs == 2 ? Text("Subtítulos en inglés") : Text("Ahora suena en inglés"), w: 370)
                    .sceneAt(16, 272).id("\(audio)-\(subs)").transition(.opacity.combined(with: .offset(y: DS.Space.s1)))
            }
        }
    }
}
