import SwiftUI
import AVFoundation
import OrbitalCore
import OrbitalModels

/// El modo iPod (la pantalla y la rueda). (Parte de `PlayerScreen`, separada por responsabilidad.)
extension PlayerScreen {
    // MARK: modo iPod
    /// El iPod: arriba ✕, AirPlay y «⋯» (los de siempre); la pantalla con el video, el nombre, la versión y el avance; la rueda.
    func ipodChrome(_ model: PlayerModel, face: IPodFace) -> some View {
        GeometryReader { geo in
            let layout = IPodLayout(in: geo.size, aspect: portraitAspect)
            let shown = wheelTarget ?? (dragAxis == .horizontal ? seekPreview : nil) ?? pendingSeek ?? model.snapshot.position
            let state = model.snapshot.state
            ZStack(alignment: .topLeading) {
                HStack(spacing: DS.Space.s3) {
                    PlayerCircleButton(symbol: "xmark", label: "Cerrar") { Task { await close() } }
                        .accessibilityIdentifier("player-close")
                    Spacer()
                    AirPlayButton().frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).glassEffect(.regular, in: Circle())
                        .accessibilityLabel(Text("AirPlay"))
                    PlayerCircleButton(symbol: "ellipsis", label: "Más opciones") {
                        withAnimation(DS.Motion.base(reduceMotion)) { moreOpen.toggle() }
                    }
                    .accessibilityIdentifier("player-more")
                }
                .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s2)
                .frame(width: geo.size.width)
                IPodScreen(face: face, status: state == .playing ? "Reproduciendo" : state == .loading || state == .buffering || model.phase == .preparing ? "Cargando" : "En pausa",
                           playing: state == .playing, title: current.displayTitle, detail: ipodDetail(model),
                           position: shown, duration: model.snapshot.duration)
                    .frame(width: layout.screen.width, height: layout.screen.height)
                    .offset(x: layout.screen.minX, y: layout.screen.minY)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                    .accessibilityAdjustableAction { d in
                        Task { await model.skip(d == .increment ? PlaybackRules.skipSeconds : -PlaybackRules.skipSeconds) }
                    }
                // «Saltar intro», en la esquina del video.
                skipIntro(model).padding(DS.Space.s2)
                    .frame(width: layout.video.width, height: layout.video.height, alignment: .bottomTrailing)
                    .offset(x: layout.video.minX, y: layout.video.minY)
                IPodWheel(face: face,
                          menu: { Task { await close() } },
                          hold: { lock() },
                          back: { Task { await model.skip(-PlaybackRules.skipSeconds) } },
                          forward: { Task { await model.skip(PlaybackRules.skipSeconds) } },
                          playPause: { userTogglePlay(model) },
                          center: { openDock(.subtitles) },
                          turn: { turnWheel($0, model) },
                          turned: { releaseWheel(model) })
                    .frame(width: layout.wheel.width, height: layout.wheel.height)
                    .offset(x: layout.wheel.minX, y: layout.wheel.minY)
                    .disabled(model.phase == .preparing)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .environment(\.colorScheme, face.scheme)
        .allowsHitTesting(!locked)
    }

    /// Una muesca de la rueda: 10 s (de a minuto si giras rápido); el avance enseña a dónde vas.
    func turnWheel(_ notches: Int, _ model: PlayerModel) {
        let now = Date()
        let fast = lastNotch.map { now.timeIntervalSince($0) < DS.IPod.fastNotch } ?? false
        lastNotch = now
        let start = wheelTarget ?? model.snapshot.position
        let target = min(max(0, start + Double(notches) * (fast ? DS.IPod.fastStep : PlaybackRules.skipSeconds)), max(0, model.snapshot.duration))
        wheelTarget = target
        model.scrub(to: target)
    }

    func releaseWheel(_ model: PlayerModel) {
        lastNotch = nil
        guard let target = wheelTarget else { return }
        wheelTarget = nil; pendingSeek = target
        Task { await model.seek(to: target) }
    }

    /// Bajo el nombre: el episodio («T5 · E12») o, en una película, la versión («Latino · 1080p»).
    func ipodDetail(_ model: PlayerModel) -> String {
        if !current.episodeLabel.isEmpty { return current.episodeLabel }
        guard let src = model.source else { return "" }
        return versionText(src, model)
    }
}
