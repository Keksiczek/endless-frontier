import SwiftUI
import EndlessFrontierCore

/// **What time it is in the valley, and what that means.**
///
/// Keks, watching a town at night: *"teď všichni chodí spát, ale vypadá to
/// stejně jako přes den, klidně i hodiny k tomu, ať je přehled co se děje a lidé
/// dělají."*
///
/// The drawn day always existed — `AgentMotion.dayLength` is five real minutes,
/// the schedule sends people to bed, and `SettlementLight` puts the sun under
/// the horizon at `dusk`. What did not exist was any way for the *player* to
/// read it: no hour anywhere on the screen, and a night that was painted as
/// day. This is the reading half.
///
/// One clock for everything that asks. The canvas measures its day from the
/// reference date, so this does too (`epoch`) — two clocks for one day is
/// exactly the mistake rule 35 is about, and it would put the strip's midnight
/// somewhere in the middle of the canvas's afternoon.
enum DayClock {

    /// The instant every drawn day is measured from. Absolute, so nothing has
    /// to be handed around and a reload does not shift the sun.
    static let epoch = Date(timeIntervalSinceReferenceDate: 0)

    /// Seconds of drawn time at `date`.
    static func time(at date: Date = Date()) -> Double { date.timeIntervalSince(epoch) }

    /// Where in its day the valley is, `0…1`, midnight at 0.
    static func fraction(at time: Double) -> Double {
        let t = (time / AgentMotion.dayLength).truncatingRemainder(dividingBy: 1)
        return t < 0 ? t + 1 : t
    }

    /// The same, as a wall clock a person can read.
    static func hourAndMinute(at time: Double) -> (hour: Int, minute: Int) {
        let hours = fraction(at: time) * 24
        let hour = Int(hours) % 24
        let minute = min(59, Int((hours - Double(Int(hours))) * 60))
        return (hour, minute)
    }

    static func clockText(at time: Double) -> String {
        let (h, m) = hourAndMinute(at: time)
        return String(format: "%02d:%02d", h, m)
    }

    /// What part of the day it is — named off the **same** two numbers the sun
    /// and the schedule use, so "night" on the strip is night on the canvas and
    /// the hour the town goes quiet is the hour the label changes.
    enum Phase {
        case night, dawn, morning, midday, afternoon, dusk

        var czech: String {
            switch self {
            case .night: return "Noc"
            case .dawn: return "Svítání"
            case .morning: return "Dopoledne"
            case .midday: return "Poledne"
            case .afternoon: return "Odpoledne"
            case .dusk: return "Soumrak"
            }
        }
        var english: String {
            switch self {
            case .night: return "Night"
            case .dawn: return "Dawn"
            case .morning: return "Morning"
            case .midday: return "Midday"
            case .afternoon: return "Afternoon"
            case .dusk: return "Dusk"
            }
        }
        var symbol: String {
            switch self {
            case .night: return "moon.stars"
            case .dawn: return "sunrise"
            case .morning: return "sun.min"
            case .midday: return "sun.max"
            case .afternoon: return "sun.min"
            case .dusk: return "sunset"
            }
        }
    }

    static func phase(at time: Double, season: Season = .summer) -> Phase {
        let t = fraction(at: time)
        let shape = AgentMotion.dayShape(season)
        if t < SettlementLight.dawn || t >= SettlementLight.dusk + SettlementRenderer.nightFall {
            return .night
        }
        if t < shape.workStart { return .dawn }
        if t < shape.middayStart { return .morning }
        if t < shape.middayEnd { return .midday }
        if t < SettlementLight.dusk { return .afternoon }
        return .dusk
    }

    static func phaseName(at time: Double, season: Season, language: GameLanguage) -> String {
        let p = phase(at: time, season: season)
        return language == .cs ? p.czech : p.english
    }

    // MARK: - What the town is doing

    /// A short tally of what the colony is at, right now.
    ///
    /// Read off the **simulation** — the job a colonist holds, the load on their
    /// back, the errand that took them off their work — and off the hour, which
    /// is what decides whether the ones with nothing pressing are in bed or on
    /// their way to a field. Presentation only: it counts, it never assigns
    /// (rule 5).
    static func doing(_ settlement: Settlement, at time: Double,
                      season: Season, language: GameLanguage) -> [(count: Int, what: String)] {
        let cs = language == .cs
        let asleep = phase(at: time, season: season) == .night
        var fighting = 0, carrying = 0, onErrands = 0, working = 0, resting = 0, away = 0
        for pawn in settlement.pawns where pawn.health > 0 {
            if settlement.siege?.line.contains(pawn.id) == true { fighting += 1; continue }
            if pawn.isAway { away += 1; continue }
            if pawn.carrying != nil { carrying += 1; continue }
            if pawn.errand != nil { onErrands += 1; continue }
            if asleep || pawn.isBroken { resting += 1; continue }
            if pawn.currentJob != nil { working += 1; continue }
            resting += 1
        }
        var out: [(Int, String)] = []
        if fighting > 0 { out.append((fighting, cs ? "v boji" : "fighting")) }
        if working > 0 { out.append((working, cs ? "v práci" : "at work")) }
        if carrying > 0 { out.append((carrying, cs ? "nese náklad" : "hauling")) }
        if onErrands > 0 { out.append((onErrands, cs ? "po svém" : "on errands")) }
        if away > 0 { out.append((away, cs ? "na cestě" : "away")) }
        if resting > 0 {
            out.append((resting, asleep ? (cs ? "spí" : "asleep")
                                        : (cs ? "odpočívá" : "resting")))
        }
        return out.map { (count: $0.0, what: $0.1) }
    }
}
