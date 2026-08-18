import Foundation

/// How a body moves while it is doing something.
///
/// The figures on the canvas have always been drawn parametrically — a leg is a
/// stroke whose end swings by `sin(gait) × amplitude`, a walker leans into the
/// walk and rises on each step — but every one of those numbers lived in
/// `SettlementFigures` as a literal, and every new way of moving meant a new
/// `case` in an enum and a new branch in the drawing code. So the simulation
/// could grow a hunt that stalks, closes, kills and carries the carcass home,
/// and the canvas could only show somebody standing near a deer.
///
/// This is that switch turned into content. A motion states what each part of
/// the body does as a wave — how far it travels, how fast, and how far behind
/// the legs it runs — and the renderer plays it. Adding a way of moving is
/// adding an entry, which is the rule the rest of this repository already
/// follows for buildings, techs and meals.
///
/// The vocabulary is not new — every number here was already in
/// `SettlementFigures`, as a literal. **The values are, for some activities.**
/// Walking, travelling, working and sleeping were copied across unchanged and
/// look exactly as they did. Fighting, hauling, playing, talking and resting
/// were given their own numbers in the same change, because "every activity
/// swings its legs 1.7" was the limitation this file exists to remove. If one
/// of those five looks wrong, it is a value to tune in the JSON, not a
/// regression to hunt in here.
public struct MotionDefinition: Codable, Sendable, Identifiable, Equatable {

    /// One part of the body, as a wave.
    public struct Wave: Codable, Sendable, Equatable {
        /// How far it travels, in body-scale units at each end of the swing.
        public let amplitude: Double
        /// Cycles per unit of the driving clock. `1` follows the walk cycle
        /// exactly; a hammer arm runs at its own rate regardless of the feet.
        public let frequency: Double
        /// Radians behind the driver. `π` is dead against it, which is what
        /// makes arms counter-swing legs rather than flail with them.
        public let phase: Double

        public init(amplitude: Double, frequency: Double = 1, phase: Double = 0) {
            self.amplitude = amplitude
            self.frequency = frequency
            self.phase = phase
        }

        public static let still = Wave(amplitude: 0)

        /// `amplitude` is the only part a clip must state. The synthesised
        /// decoder demanded all three, so `{"amplitude": 1.7, "frequency": 1}`
        /// — which is what nearly every clip in the bank looks like, and what
        /// the generator is told to write — threw `keyNotFound("phase")` and
        /// took the entire bank down with it.
        ///
        /// It did that silently for a while, because the registry swallowed the
        /// error and handed back an empty table: the bank was loading nothing
        /// at all while the build was green. Defaults here, and a loud loader
        /// there, are the two halves of not letting that happen again.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            amplitude = try c.decode(Double.self, forKey: .amplitude)
            frequency = try c.decodeIfPresent(Double.self, forKey: .frequency) ?? 1
            phase = try c.decodeIfPresent(Double.self, forKey: .phase) ?? 0
        }

        /// Where this wave is at `t`, in body-scale units.
        public func offset(at t: Double) -> Double {
            amplitude == 0 ? 0 : sin(t * frequency + phase) * amplitude
        }
    }

    public let id: String
    public let name: LocalizedText

    /// What this clip is *for*: the activities and the trades it may be chosen
    /// for. A clip that names neither is only ever reached by its id.
    ///
    /// This is the difference between a bank that grows and a bank that does
    /// not. Without it every new clip needs a line of Swift to select it, and a
    /// generated `stalking` sits in the file forever while hunters keep doing
    /// the generic work animation — content that loads and can never be seen,
    /// which is the oldest bug in this repository.
    public let servesActivities: [String]
    public let servesWork: [String]

    /// The legs, driven by the walk cycle and scaled by how much the colonist
    /// is actually moving.
    public let legs: Wave
    /// The hand that holds the tool. A worker's arm at the bench, a hunter's
    /// arm drawing back — this is the one that does the job.
    public let toolArm: Wave
    /// How hard the free arm swings against the legs. A fraction of the leg
    /// swing, negated: `0.55` is a walk, `0` is arms full.
    public let freeArmCounterSwing: Double

    /// How far the body tips the way it is going, in body-scale units per unit
    /// of facing. A runner leans; somebody standing at a bench does not.
    public let lean: Double
    /// How far the whole body rises on each step.
    public let bob: Double
    /// Bent over it: illness, exhaustion, butchering something on the ground.
    public let slouch: Double

    /// Where the tool hand sits when the wave is at rest — out from the body,
    /// and above (negative) or below the hip.
    public let reach: Double
    public let handHeight: Double

    /// How solidly the figure is drawn. Sleep and sickness dim it.
    public let opacity: Double
    /// Multiplies how fast this colonist crosses the ground while the motion
    /// runs. Presentation only — it never feeds back into the simulation
    /// (`AgentMotion` derives position from `(pawn.id, frame clock)` and
    /// nothing the renderer does may write `WorldState`).
    public let speed: Double

    public let description: LocalizedText

    public init(
        id: String,
        name: LocalizedText,
        servesActivities: [String] = [],
        servesWork: [String] = [],
        legs: Wave = .still,
        toolArm: Wave = .still,
        freeArmCounterSwing: Double = 0,
        lean: Double = 0,
        bob: Double = 0,
        slouch: Double = 0,
        reach: Double = 2.1,
        handHeight: Double = 0.8,
        opacity: Double = 1,
        speed: Double = 1,
        description: LocalizedText = ""
    ) {
        self.id = id
        self.name = name
        self.servesActivities = servesActivities
        self.servesWork = servesWork
        self.legs = legs
        self.toolArm = toolArm
        self.freeArmCounterSwing = freeArmCounterSwing
        self.lean = lean
        self.bob = bob
        self.slouch = slouch
        self.reach = reach
        self.handHeight = handHeight
        self.opacity = opacity
        self.speed = speed
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, legs, description, lean, bob, slouch, reach, opacity, speed
        case servesActivities = "serves_activities"
        case servesWork = "serves_work"
        case toolArm = "tool_arm"
        case freeArmCounterSwing = "free_arm_counter_swing"
        case handHeight = "hand_height"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(LocalizedText.self, forKey: .name)
        servesActivities = try c.decodeIfPresent([String].self, forKey: .servesActivities) ?? []
        servesWork = try c.decodeIfPresent([String].self, forKey: .servesWork) ?? []
        legs = try c.decodeIfPresent(Wave.self, forKey: .legs) ?? .still
        toolArm = try c.decodeIfPresent(Wave.self, forKey: .toolArm) ?? .still
        freeArmCounterSwing = try c.decodeIfPresent(Double.self, forKey: .freeArmCounterSwing) ?? 0
        lean = try c.decodeIfPresent(Double.self, forKey: .lean) ?? 0
        bob = try c.decodeIfPresent(Double.self, forKey: .bob) ?? 0
        slouch = try c.decodeIfPresent(Double.self, forKey: .slouch) ?? 0
        reach = try c.decodeIfPresent(Double.self, forKey: .reach) ?? 2.1
        handHeight = try c.decodeIfPresent(Double.self, forKey: .handHeight) ?? 0.8
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        description = try c.decodeIfPresent(LocalizedText.self, forKey: .description) ?? ""
    }

    /// What a body does when the bank has nothing to say — a plain stand.
    /// Never nil, because a missing clip must read as a person standing there
    /// and not as a colonist who failed to draw.
    public static let standing = MotionDefinition(
        id: "standing", name: LocalizedText(values: [.en: "Standing", .cs: "Stání"])
    )
}
