// AfterglowSparks.swift — the solve, in depth.
//
// The Afterglow's shockwave already leaves the winning cell on the Canvas
// (Afterglow.metal). On Vision Pro the same moment gets the one thing a flat
// screen cannot give it: a burst of light that leaves the glass and hangs in
// the air between the board and the player, then fades. It is one RealityKit
// particle emitter at the winning cell, burst once — no assets, no custom
// systems, nothing running between solves.
//
// Callers pass a nil `trigger` under Reduce Motion, so nothing is ever built.
#if os(visionOS)
import SwiftUI
import RealityKit
import CouchKit

struct AfterglowSparks: View {
    /// The solve instant. A new value bursts once; nil does nothing.
    let trigger: Date?
    /// The winning cell, 0…80.
    let origin: Int?
    let accent: Color

    @Environment(\.physicalMetrics) private var metrics
    /// The last instant that burst, so a re-render of the same solve never
    /// bursts twice. A reference type in `@State`: remembered, never observed.
    @State private var ledger = BurstLedger()

    var body: some View {
        RealityView { content in
            let emitter = Entity()
            emitter.name = "afterglow.sparks"
            content.add(emitter)
        } update: { content in
            guard let trigger, let origin, ledger.last != trigger,
                  let emitter = content.entities.first(where: { $0.name == "afterglow.sparks" })
            else { return }
            ledger.last = trigger
            emitter.position = position(of: origin)
            var burst = Self.emitter(accent: UIColor(accent))
            burst.burst()
            emitter.components.set(burst)
        }
        .frame(width: VisionBoardMetrics.card, height: VisionBoardMetrics.card)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The cell's centre in the RealityView's space: metres, origin at the
    /// view's centre, y up — where SwiftUI's is points, top-left, y down.
    private func position(of cell: Int) -> SIMD3<Float> {
        let point = BoardMetrics.center(of: cell, side: VisionBoardMetrics.side)
        let half = VisionBoardMetrics.card / 2
        let x = point.x + VisionBoardMetrics.inset - half
        let y = point.y + VisionBoardMetrics.inset - half
        return SIMD3(
            Float(metrics.convert(x, to: .meters)),
            Float(metrics.convert(-y, to: .meters)),
            // A hair proud of the glass, so the first frame is not inside it.
            Float(metrics.convert(6, to: .meters)))
    }

    private static func emitter(accent: UIColor) -> ParticleEmitterComponent {
        var sparks = ParticleEmitterComponent()
        sparks.emitterShape = .sphere
        sparks.emitterShapeSize = [0.01, 0.01, 0.01]
        sparks.birthLocation = .surface
        sparks.birthDirection = .normal
        sparks.speed = 0.22
        sparks.speedVariation = 0.12
        sparks.isEmitting = false
        sparks.burstCount = 360
        sparks.burstCountVariation = 40

        sparks.mainEmitter.lifeSpan = 1.8
        sparks.mainEmitter.lifeSpanVariation = 0.5
        sparks.mainEmitter.size = 0.0035
        sparks.mainEmitter.sizeVariation = 0.0015
        sparks.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.1
        // Damped hard, so the burst blooms and then *hangs* — an afterglow,
        // not a firework — with a slow rise like warm air.
        sparks.mainEmitter.dampingFactor = 3.2
        sparks.mainEmitter.acceleration = [0, 0.03, 0]
        sparks.mainEmitter.blendMode = .additive
        sparks.mainEmitter.opacityCurve = .linearFadeOut
        sparks.mainEmitter.color = .evolving(
            start: .single(.white),
            end: .single(accent))
        return sparks
    }
}

private final class BurstLedger {
    var last: Date?
}
#endif
