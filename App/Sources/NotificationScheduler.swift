import Foundation
import UserNotifications
import EndlessFrontierCore

/// Local notifications: the colony reaching the player while they are away.
///
/// The world keeps running — up to thirty days of ticks are replayed on open —
/// and until now nothing ever told anyone. The rules this follows, in order of
/// how easy they are to get wrong:
///
/// 1. **App-side only.** `Core` stays offline-first and platform-agnostic; it
///    knows nothing about this file. The scheduler reads state and schedules.
/// 2. **Local only** (`UNUserNotificationCenter`) — no server, no push.
/// 3. **Asked for at a sensible moment.** Permission is requested when the
///    player *leaves* a session that lasted long enough to mean something, not
///    on the cold launch of a game they haven't decided about yet.
/// 4. **Rate-limited hard.** A civilisation sim generates something every few
///    ticks; one notification per event would be unusable. At most
///    `maxPerSpell` go out per absence, spaced by `minimumGap`, and the
///    day-after digest is one message, not a feed.
/// 5. **Bilingual**, like everything else the player reads.
/// 6. **Refused is fine.** The game must be exactly as playable with
///    notifications denied, so every call here is best-effort and silent.
@MainActor
enum NotificationScheduler {

    /// Category ids, so the scheduler can replace its own pending messages
    /// without touching anything else.
    private static let digestID = "ef.digest"
    private static let decisionID = "ef.decision"
    private static let dangerID = "ef.danger"

    /// The most messages a single absence may produce.
    static let maxPerSpell = 3
    /// The least time between two of them.
    static let minimumGap: TimeInterval = 6 * 3600
    /// How long a session has to run before it is worth asking to be let in.
    /// Long enough that the player has decided they like the game, short
    /// enough that they are still in the same sitting when the sheet appears —
    /// the ask happens in the foreground now, so it has to land while they are
    /// looking at the thing it is about.
    static let sessionBeforeAsking: TimeInterval = 2 * 60

    private static var cs: Bool { AppStrings.language == .cs }
    private static func s(_ en: String, _ cz: String) -> String { cs ? cz : en }

    // MARK: - Permission

    /// Asks, once, and only after the player has actually played for a while.
    /// Requesting on first launch is how an app gets denied for ever.
    ///
    /// **Called from the foreground, deliberately.** The first cut asked as the
    /// app went to the background, which is why not one notification ever
    /// arrived: iOS will not put the permission sheet in front of an app that
    /// is not on screen, so the status stayed `.notDetermined`, and
    /// `scheduleOnLeaving` — which runs a moment later and is gated on being
    /// authorised — queued nothing. Every session. For ever. The ask has to
    /// happen while the player is looking at the game.
    static func requestPermissionIfEarned(sessionLength: TimeInterval) async {
        guard sessionLength >= sessionBeforeAsking else { return }
        let centre = UNUserNotificationCenter.current()
        let settings = await centre.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await centre.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private static func isAllowed() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    // MARK: - Scheduling

    /// Lays out what the colony has to say next, and clears whatever was
    /// queued before (it was written for a world state that has moved on).
    ///
    /// **Armed while the game is running, not on the way out.** Backgrounding
    /// gives an app a few seconds and no promises; an `async` chain started
    /// there can simply never finish, and this one never did. A queued local
    /// notification costs nothing while the app is up — it only ever fires
    /// once the player has gone — so the queue is kept current *during* play
    /// and the exit path becomes a top-up rather than the only chance.
    static func arm(_ world: WorldState, registry: GameDataRegistry) async {
        let centre = UNUserNotificationCenter.current()
        guard await isAllowed() else {
            centre.removeAllPendingNotificationRequests()
            return
        }
        centre.removeAllPendingNotificationRequests()

        var messages: [(id: String, after: TimeInterval, title: String, body: String)] = []

        // The one that actually loses the player progress: something is waiting
        // on a decision only they can make.
        if let waiting = pendingDecisionLine(world) {
            messages.append((decisionID, 2 * 3600,
                             s("The council is waiting", "Rada čeká"), waiting))
        }
        // Something is going wrong that they would want to know about.
        if let trouble = troubleLine(world, registry: registry) {
            messages.append((dangerID, 8 * 3600,
                             s("Word from the colony", "Zpráva z osady"), trouble))
        }
        // And the day-after digest: a reason to come back, not a report. The
        // numbers are deliberately *not* predicted here — they are generated on
        // open, where they can't be wrong.
        messages.append((digestID, 22 * 3600,
                         s("A day has passed", "Uplynul den"),
                         digestLine(world)))

        // Rate limit: cap the count and keep them apart.
        //
        // `lastAt` starts far enough back that the **first** message keeps its
        // own time. Starting it at zero meant the gap was measured from the
        // moment the player left, so the one message that is actually urgent —
        // the council waiting on a decision, due at two hours — was quietly
        // pushed out to six every single time. A rate limit is for the space
        // *between* messages; there is nothing before the first one.
        var lastAt: TimeInterval = -minimumGap
        var sent = 0
        for message in messages.sorted(by: { $0.after < $1.after }) {
            guard sent < maxPerSpell else { break }
            let at = max(message.after, lastAt + minimumGap)
            schedule(id: message.id, after: at, title: message.title, body: message.body)
            lastAt = at
            sent += 1
        }
    }

    /// Anything already *delivered* is stale the moment the player is looking
    /// at the game. What is merely queued is left alone: it is the whole point,
    /// and re-arming will replace it.
    static func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    private static func schedule(id: String, after: TimeInterval, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(60, after), repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - What there is to say

    static func pendingDecisionLine(_ world: WorldState) -> String? {
        guard world.pendingLawProposal != nil else { return nil }
        return s("An assembly has voted and wants your word on it.",
                 "Sněm hlasoval a čeká na tvé slovo.")
    }

    static func troubleLine(_ world: WorldState, registry: GameDataRegistry) -> String? {
        guard let capital = world.settlements.first else { return nil }
        // Starvation first — it is the one that empties a colony.
        let food = capital.storage[.food]
        let mouths = Double(capital.pawns.count)
        if mouths > 0, food < mouths * 2 {
            return s("The stores are nearly out and there are mouths to feed.",
                     "Sklady jsou skoro prázdné a je koho živit.")
        }
        if capital.stats.morale < 30 {
            return s("Spirits in the colony have sunk badly.",
                     "Nálada v osadě klesla hluboko.")
        }
        if world.globalStats.threatLevel > 60 {
            return s("Something is gathering out beyond the fields.",
                     "Za poli se něco shromažďuje.")
        }
        return nil
    }

    static func digestLine(_ world: WorldState) -> String {
        let name = world.settlements.first?.name ?? s("The colony", "Osada")
        return s("\(name) has carried on without you. Come and see what changed.",
                 "\(name) žila dál i bez tebe. Přijď se podívat, co se změnilo.")
    }
}
