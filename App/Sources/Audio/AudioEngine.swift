import Foundation
import AVFoundation
import os

/// **The valley, made audible — with no audio files at all.**
///
/// Every sound in the game is generated a sample at a time: wind is filtered
/// noise, rain is brighter filtered noise, a cricket is a short burst of a high
/// sine, a fire is noise with pops in it, a bell is three inharmonic partials
/// ringing out. There is not one asset in the repository and there does not need
/// to be.
///
/// That is not a shortcut, it is the right shape for *this* game. The world is
/// continuous — the weather moves, the day turns, the colony grows — and a
/// looped recording can only be crossfaded between states. A generator can be
/// *told* the state and follow it: the wind genuinely rises as the cold comes
/// on, and the crickets genuinely stop when the season turns.
///
/// **Presentation only** (rule 5). Sound reads the world; nothing here can write
/// to it.
///
/// Threading: the render callback runs on a real-time audio thread and must not
/// allocate, lock or wait. It reads its targets from `Voices`, a small class of
/// plain doubles written from the main actor — an 8-byte aligned load or store
/// is atomic on every device this ships to, and the worst a race can do is use
/// last frame's gain for one buffer. Stings go through a fixed-size ring buffer
/// with a lock held *only* on the writing side.
@MainActor
final class AudioEngine {

    static let shared = AudioEngine()

    /// Master volume, 0…1. Everything is scaled by this.
    var volume: Double = 0.7 {
        didSet { voices.master = enabled ? min(1, max(0, volume)) : 0 }
    }
    var enabled: Bool = true {
        didSet {
            voices.master = enabled ? min(1, max(0, volume)) : 0
            if enabled { start() } else { stop() }
        }
    }

    private let engine = AVAudioEngine()
    private let voices = Voices()
    private var source: AVAudioSourceNode?
    private var running = false

    private init() {}

    // MARK: - What the world sounds like

    /// Hands the mix to the audio thread. Called about once a second; the
    /// generator glides to it rather than jumping, so a season turning is a
    /// season turning and not a switch being thrown.
    func apply(_ scape: Soundscape) {
        voices.windTarget = scape.wind
        voices.rainTarget = scape.rain
        voices.cricketTarget = scape.crickets
        voices.villageTarget = scape.village
        voices.fireTarget = scape.fire
    }

    /// Something just happened.
    func play(_ sting: Sting) {
        guard enabled else { return }
        voices.enqueue(sting)
    }

    // MARK: - The device

    func start() {
        guard enabled, !running else { return }
        do {
            // `.ambient` on purpose: the game respects the silent switch and
            // does not stop whatever the player is already listening to. A
            // colony sim that kills your music is a colony sim you play muted.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return   // No session, no sound. Never a reason to fail a launch.
        }
        let format = engine.outputNode.inputFormat(forBus: 0)
        let rate = format.sampleRate > 0 ? format.sampleRate : 44_100
        voices.sampleRate = rate

        // **Built outside the actor, deliberately.** A closure formed inside a
        // `@MainActor` method is itself main-actor isolated, so Swift plants an
        // executor check in it — and that check runs on the *audio* thread,
        // hits `dispatch_assert_queue` and takes the process out with SIGILL
        // before the app has finished launching. `Voices.makeNode()` is
        // `nonisolated`, so the render block is too.
        let node = voices.makeNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        source = node
        do {
            try engine.start()
            running = true
        } catch {
            engine.detach(node)
            source = nil
        }
    }

    func stop() {
        guard running else { return }
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// The generator itself: state that the audio thread owns, and the DSP.
///
/// Kept out of `AudioEngine` so the real-time code is one small object with no
/// actor isolation on it — hopping to the main actor inside a render callback
/// is how an audio thread misses its deadline and clicks.
private final class Voices: @unchecked Sendable {

    var sampleRate: Double = 44_100

    // Targets, written from the main actor and read here. See the note on
    // `AudioEngine` for why plain doubles are safe for these.
    var master: Double = 0.7
    var windTarget: Double = 0
    var rainTarget: Double = 0
    var cricketTarget: Double = 0
    var villageTarget: Double = 0
    var fireTarget: Double = 0

    // …and where each one actually is, gliding toward its target.
    private var wind = 0.0, rain = 0.0, cricket = 0.0, village = 0.0, fire = 0.0

    /// How fast a voice reaches its target, per sample. About a second and a
    /// half to cross the whole range at 44.1k — weather that arrives.
    private let glide = 0.000_015

    // Filter state.
    private var windLP = 0.0, windBP = 0.0, windMod = 0.0
    private var rainLP = 0.0
    private var villageLP = 0.0, villageMod = 0.0
    private var fireLP = 0.0, firePop = 0.0, firePopDecay = 0.0
    private var cricketPhase = 0.0, cricketEnv = 0.0, cricketGap = 0.0
    private var rng: UInt64 = 0x2545_F491_4F6C_DD1D

    // MARK: - Stings

    /// A one-shot in flight: which sound, and how far through it is.
    private struct Shot {
        var kind: Sting
        var age: Double        // seconds
        var phase: [Double]    // per-partial phase
    }
    private var shots: [Shot] = []
    private let pending = OSAllocatedUnfairLock(initialState: [Sting]())

    /// The node that pulls on this generator.
    ///
    /// Lives here rather than in `AudioEngine` so the render block is formed in
    /// a non-isolated context — see the note at the call site.
    func makeNode() -> AVAudioSourceNode {
        AVAudioSourceNode { [unowned self] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            self.render(frames: Int(frameCount), into: buffers)
            return noErr
        }
    }

    func enqueue(_ sting: Sting) {
        pending.withLock { queue in
            // A flood of the same news is one sound, not forty.
            guard queue.count < 4 else { return }
            queue.append(sting)
        }
    }

    // MARK: - Render

    func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        // Take anything the main actor queued. `withLockIfAvailable` never
        // waits: if the main actor happens to hold it this instant, the sting
        // arrives one buffer later, which is five milliseconds.
        pending.withLockIfAvailable { queue -> Void in
            for sting in queue where shots.count < 8 {
                shots.append(Shot(kind: sting, age: 0, phase: [0, 0, 0]))
            }
            queue.removeAll()
        }

        let dt = 1 / sampleRate
        for frame in 0..<frames {
            wind += (windTarget - wind).clamped(to: glide)
            rain += (rainTarget - rain).clamped(to: glide)
            cricket += (cricketTarget - cricket).clamped(to: glide)
            village += (villageTarget - village).clamped(to: glide)
            fire += (fireTarget - fire).clamped(to: glide)

            var sample = 0.0
            sample += windSample()
            sample += rainSample()
            sample += cricketSample(dt: dt)
            sample += villageSample()
            sample += fireSample()
            sample += stingSample(dt: dt, frameIsLast: frame == frames - 1)

            let out = Float(tanh(sample * master * 1.2) * 0.6)
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                data.assumingMemoryBound(to: Float.self)[frame] = out
            }
        }
        // Age the shots by the whole buffer at once and retire the finished.
        let elapsed = Double(frames) * dt
        for i in shots.indices { shots[i].age += elapsed }
        shots.removeAll { $0.age > length(of: $0.kind) }
    }

    // MARK: - The voices

    /// Wind: noise pushed through a wandering band, with the band itself moving
    /// slowly. One filter would be a hiss; a *moving* filter is weather.
    private func windSample() -> Double {
        guard wind > 0.001 else { return 0 }
        windMod += 0.000_0021
        if windMod > 1 { windMod -= 1 }
        let gust = 0.5 + 0.5 * sin(windMod * 2 * .pi) * sin(windMod * 6.4 * .pi)
        let n = noise()
        windLP += (n - windLP) * (0.02 + gust * 0.05)
        windBP += (windLP - windBP) * 0.004
        return (windLP - windBP) * wind * (0.35 + gust * 0.65) * 0.5
    }

    /// Rain: the same noise, kept bright, with none of the wind's wander.
    private func rainSample() -> Double {
        guard rain > 0.001 else { return 0 }
        let n = noise()
        rainLP += (n - rainLP) * 0.35
        return (n - rainLP * 0.6) * rain * 0.22
    }

    /// Crickets: a short high burst, a gap, another burst. The gap is what
    /// makes it crickets rather than a tone.
    private func cricketSample(dt: Double) -> Double {
        guard cricket > 0.001 else { return 0 }
        cricketGap -= dt
        if cricketGap <= 0 {
            cricketGap = 0.18 + unit() * 0.5
            cricketEnv = 1
            cricketPhase = 0
        }
        guard cricketEnv > 0.001 else { return 0 }
        cricketEnv *= 0.9994
        cricketPhase += 4_600 * dt * 2 * .pi
        // Chirped: two close tones beating, which is the texture of the real
        // thing and costs one more sine.
        let tone = sin(cricketPhase) * 0.6 + sin(cricketPhase * 1.02) * 0.4
        return tone * cricketEnv * cricket * 0.06
    }

    /// A village: low, broad, and never quite steady. Voices, tools, animals,
    /// all of it too far off to make out — which is exactly what a low-passed
    /// noise with a slow wobble sounds like.
    private func villageSample() -> Double {
        guard village > 0.001 else { return 0 }
        villageMod += 0.000_011
        if villageMod > 1 { villageMod -= 1 }
        let stir = 0.6 + 0.4 * sin(villageMod * 2 * .pi * 3.1)
        villageLP += (noise() - villageLP) * 0.012
        return villageLP * village * stir * 0.9
    }

    /// Fire: a soft bed with pops on it. The pops are the whole sound — a fire
    /// without them is just more wind.
    private func fireSample() -> Double {
        guard fire > 0.001 else { return 0 }
        fireLP += (noise() - fireLP) * 0.05
        if unit() < 0.000_12 {
            firePop = 0.6 + unit() * 0.4
            firePopDecay = 0.9985 - unit() * 0.001
        }
        firePop *= firePopDecay
        let pop = firePop > 0.001 ? noise() * firePop : 0
        return (fireLP * 0.5 + pop) * fire * 0.5
    }

    // MARK: - Stings

    private func length(of sting: Sting) -> Double {
        switch sting {
        case .hammer: return 0.35
        case .bell: return 2.4
        case .horn: return 1.6
        case .chime: return 1.1
        case .knell: return 3.2
        }
    }

    private func stingSample(dt: Double, frameIsLast: Bool) -> Double {
        guard !shots.isEmpty else { return 0 }
        var sum = 0.0
        for i in shots.indices {
            let age = shots[i].age
            let life = length(of: shots[i].kind)
            guard age < life else { continue }
            let t = age / life
            switch shots[i].kind {
            case .hammer:
                // A struck nail: a click of noise over a short low thud.
                let env = exp(-t * 14)
                shots[i].phase[0] += 220 * dt * 2 * .pi
                sum += (noise() * 0.5 + sin(shots[i].phase[0]) * 0.5) * env * 0.5

            case .bell, .knell:
                // Inharmonic partials, which is what makes metal metal. The
                // knell is the same bell an octave down and slower to let go.
                let base = shots[i].kind == .bell ? 660.0 : 210.0
                let env = exp(-t * (shots[i].kind == .bell ? 3.4 : 2.0))
                for (k, ratio) in [1.0, 2.76, 5.4].enumerated() {
                    shots[i].phase[k] += base * ratio * dt * 2 * .pi
                    sum += sin(shots[i].phase[k]) * env * (0.34 / Double(k + 1))
                }

            case .horn:
                // A horn is a slow breath in and a long one out, with enough
                // harmonics to be brass rather than a flute.
                let env = min(1, t * 6) * exp(-max(0, t - 0.2) * 2.6)
                for (k, ratio) in [1.0, 2.0, 3.0].enumerated() {
                    shots[i].phase[k] += 172 * ratio * dt * 2 * .pi
                    sum += sin(shots[i].phase[k]) * env * (0.30 / Double(k + 1))
                }

            case .chime:
                // Two bright tones a fifth apart, gone almost at once.
                let env = exp(-t * 5.5)
                for (k, freq) in [1_320.0, 1_980.0].enumerated() {
                    shots[i].phase[k] += freq * dt * 2 * .pi
                    sum += sin(shots[i].phase[k]) * env * 0.18
                }
            }
        }
        _ = frameIsLast
        return sum
    }

    // MARK: - Noise

    /// xorshift — cheap, allocation-free, and nothing here needs it to be
    /// deterministic: this is the one place in the project where a different
    /// number every run is *correct*.
    private func noise() -> Double { unit() * 2 - 1 }

    private func unit() -> Double {
        rng ^= rng << 13
        rng ^= rng >> 7
        rng ^= rng << 17
        return Double(rng >> 11) / Double(1 << 53)
    }
}

private extension Double {
    /// A step toward zero of at most `limit` — the glide.
    func clamped(to limit: Double) -> Double {
        self > limit ? limit : (self < -limit ? -limit : self)
    }
}
