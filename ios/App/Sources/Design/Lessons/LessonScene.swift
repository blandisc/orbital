import SwiftUI

/// La escena de una pantalla de lección: el lienzo con su reloj y la escena que toca. Las de «Pruébalo» (`practice`) siguen
/// vivas para animar lo que tocas y avisan con `tried` cuando lo lograste.
struct LessonScene: View {
    let id: LessonSceneID
    let art: LessonArt
    let start: Date
    var tried: () -> Void = {}

    var body: some View {
        LessonCanvas(end: Self.end(id), start: start, live: id.isPractice, label: Self.label(id)) { t in scene(t) }
    }

    @ViewBuilder private func scene(_ t: Double) -> some View {
        switch id {
        case .cloudPlay: LessonCloudPlay(t: t, art: art)
        case .cloudWhat: LessonCloudWhat(t: t, art: art)
        case .cloudAsk: LessonCloudAsk(t: t, art: art)
        case .cloudPrice: LessonCloudPrice(t: t, art: art)
        case .cloudOne: LessonCloudOne(t: t, art: art)
        case .cloudTry: LessonCloudTry(t: t, art: art, done: tried)
        case .langPick: LessonLanguagePick(t: t)
        case .langOrder: LessonLanguageOrder(t: t)
        case .langOther: LessonLanguageOther(t: t, art: art)
        case .langPanel: LessonLanguagePanel(t: t, art: art)
        case .langTry: LessonLanguageTry(t: t, art: art, done: tried)
        case .todayWhy: LessonTodayWhy(t: t, art: art)
        case .todayDecide: LessonTodayDecide(t: t, art: art)
        case .todaySwipe: LessonTodaySwipe(t: t, art: art)
        case .todayFilter: LessonTodayFilter(t: t, art: art)
        case .todayTry: LessonTodayTry(t: t, art: art, done: tried)
        case .yoursTrakt: LessonYoursTrakt(t: t, art: art)
        case .yoursHandoff: LessonYoursHandoff(t: t, art: art)
        case .yoursMark: LessonYoursMark(t: t, art: art)
        case .yoursAlert: LessonYoursAlert(t: t, art: art)
        case .yoursTry: LessonYoursTry(t: t, art: art, done: tried)
        case .tvSend: LessonTVSend(t: t, art: art)
        case .tvRemote: LessonTVRemote(t: t, art: art)
        case .tvVoice: LessonTVVoice(t: t, art: art)
        case .tvGame: LessonTVGame(t: t)
        case .tvTry: LessonTVTry(t: t, art: art, done: tried)
        }
    }

    /// Cuándo termina de moverse cada escena (luego el reloj se detiene).
    static func end(_ id: LessonSceneID) -> Double {
        switch id {
        case .cloudPlay: LessonCloudPlay.end
        case .cloudWhat: LessonCloudWhat.end
        case .cloudAsk: LessonCloudAsk.end
        case .cloudPrice: LessonCloudPrice.end
        case .cloudOne: LessonCloudOne.end
        case .langPick: LessonLanguagePick.end
        case .langOrder: LessonLanguageOrder.end
        case .langOther: LessonLanguageOther.end
        case .langPanel: LessonLanguagePanel.end
        case .todayWhy: LessonTodayWhy.end
        case .todayDecide: LessonTodayDecide.end
        case .todaySwipe: LessonTodaySwipe.end
        case .todayFilter: LessonTodayFilter.end
        case .yoursTrakt: LessonYoursTrakt.end
        case .yoursHandoff: LessonYoursHandoff.end
        case .yoursMark: LessonYoursMark.end
        case .yoursAlert: LessonYoursAlert.end
        case .tvSend: LessonTVSend.end
        case .tvRemote: LessonTVRemote.end
        case .tvVoice: LessonTVVoice.end
        case .tvGame: LessonTVGame.end
        case .cloudTry, .langTry, .todayTry, .yoursTry, .tvTry: 1
        }
    }

    /// Lo que dice VoiceOver de la escena (el titular y la línea ya se leen aparte).
    static func label(_ id: LessonSceneID) -> Text {
        switch id {
        case .cloudPlay: Text("Tocas «Ver» en la ficha y la película empieza al instante")
        case .cloudWhat: Text("Tu iPhone y tu nube; una película baja de la nube a tu pantalla")
        case .cloudAsk: Text("En Versión, la de Castellano dice «Por pedir»; al tocarla se pide y llega un aviso de que ya está")
        case .cloudPrice: Text("Los planes de la nube y el aviso de que te quedan tres días")
        case .cloudOne: Text("Dos iPhones con la misma cuenta: el segundo se corta")
        case .cloudTry: Text("La hoja de Versión de práctica")
        case .langPick: Text("Tu lista de idiomas; «Ver» elige el primero, Latino")
        case .langOrder: Text("En Tus idiomas, Idioma original sube al primer lugar")
        case .langOther: Text("La bandera junto a «Ver» abre la hoja de versiones")
        case .langPanel: Text("En el video, el globo abre el panel de audio y subtítulos y se elige Español")
        case .langTry: Text("El panel de audio y subtítulos de práctica")
        case .todayWhy: Text("El mosaico de sugerencias; una se levanta con su porqué")
        case .todayDecide: Text("Decide por mí abre tres en abanico, cada una con su porqué")
        case .todaySwipe: Text("Una por una: una se guarda a la derecha y otra se pasa a la izquierda")
        case .todayFilter: Text("Tres filtros se prenden y la lista baja de 2400 a 3 títulos")
        case .todayTry: Text("Decide por mí, de práctica")
        case .yoursTrakt: Text("Trakt guarda lo que viste, tu lista y dónde ibas")
        case .yoursHandoff: Text("El iPhone se pausa en el minuto 34 y el iPad sigue ahí")
        case .yoursMark: Text("Se marca visto el episodio 3 y se califica con estrellas")
        case .yoursAlert: Text("El aviso de que sale hoy un episodio y la semana del calendario")
        case .yoursTry: Text("Los episodios de práctica")
        case .tvSend: Text("Ver en la TV: la película pasa del iPhone a la TV")
        case .tvRemote: Text("Deslizas en el iPhone y el foco se mueve en la TV")
        case .tvVoice: Text("Le pides en voz alta el siguiente episodio y la TV lo pone")
        case .tvGame: Text("Mientras juegas, el iPhone enseña la guía, tus notas y el temporizador")
        case .tvTry: Text("Una TV de práctica para mandar una película y moverte")
        }
    }
}

extension LessonSceneID {
    /// La escena de «Pruébalo»: se toca de verdad, de práctica.
    var isPractice: Bool { rawValue.hasSuffix("Try") }
}
