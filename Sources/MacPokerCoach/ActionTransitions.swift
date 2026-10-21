import Foundation
import TableRecognition

/// Estimated actions from consecutive stable states, not a claim of complete hand history.
/// No change alone implies a check; card disappearance alone implies no fold.
struct ActionTransitions {
    struct Event { var seatID: Int; var action: TrackedAction }
    private var round: UUID?
    private var street: Int?
    private var stable: TableObservation?
    private var stableTime = Date.distantPast
    private var pending: TableObservation?
    private var pendingTime = Date.distantPast
    private var knownBets = [Int:Int]()

    mutating func interrupt() { stable = nil; pending = nil; knownBets.removeAll() }
    mutating func accept(_ table: TableObservation,round nextRound: UUID,time: Date) -> [Event] {
        guard table.trackingUsable, table.issue == nil, !table.sidePots, let pot = table.potCents, pot > 0, table.seats.compactMap(\.betCents).reduce(0,+) <= pot,
              [0,3,4,5].contains(table.boardCards.count), table.seats.allSatisfy({ !$0.isNewPlayer && $0.activity != .unknown }),
              table.seats.filter({ $0.isHero || $0.activity == .active }).allSatisfy({ $0.stackCents != nil }) else { interrupt(); return [] }
        let nextStreet = table.boardCards.count
        if round != nextRound { self = ActionTransitions(); round = nextRound }
        if street != nextStreet {
            let old = stable
            knownBets.removeAll()
            // Observe the street sweep without any stack/pot movement to establish zeros.
            if nextStreet > 0, let old, old.boardCards.count < nextStreet, old.potCents == pot,
               sameSeats(old,table), zip(old.seats,table.seats).allSatisfy({ $0.stackCents == $1.stackCents }),
               !table.seats.contains(where:{ ($0.betCents ?? 0) > 0 }) {
                for seat in table.seats { knownBets[seat.id] = 0 }
            }
            street = nextStreet; stable = nil; pending = nil
        }
        guard let candidate = pending, sameState(candidate,table), time.timeIntervalSince(pendingTime) <= 1.5 else {
            pending = table; pendingTime = time; return []
        }
        let prior = stable
        var advance = true
        defer {
            if advance {
                stable = table; stableTime = time
                for seat in table.seats {
                    if let bet = seat.betCents { knownBets[seat.id] = bet }
                    else if let before = prior?.seats.first(where:{ $0.id == seat.id }), before.stackCents != seat.stackCents { knownBets[seat.id] = nil }
                }
            }
            pending = table; pendingTime = time
            if nextStreet > 0, table.controls?.canCheck == true, table.callCents == 0,
               knownBets.values.allSatisfy({ $0 == 0 }), !table.seats.contains(where:{ ($0.betCents ?? 0) > 0 }) {
                for seat in table.seats { knownBets[seat.id] = 0 }
            }
        }
        guard let old = prior, sameSeats(old,table), old.boardCards == table.boardCards,
              pendingTime.timeIntervalSince(stableTime) <= 1.5, old.potCents != nil else { return [] }
        if sameState(old,table) { return [] }
        let oldActive = old.seats.filter { $0.activity == .active }
        var highest: Int?
        if oldActive.allSatisfy({ knownBets[$0.id] != nil }) { highest = oldActive.compactMap { knownBets[$0.id] }.max() }
        if let hero = old.hero, let own = knownBets[hero.id], let call = old.callCents, call >= 0,
           old.controls?.canCheck == true || (old.controls?.canCall == true && (hero.stackCents ?? 0) > call) {
            let quoted = own+call
            guard quoted >= (old.seats.compactMap(\.betCents).max() ?? 0) else { return [] }
            highest = quoted
        }
        let changed = zip(old.seats,table.seats).filter { $0.stackCents != $1.stackCents }
        if changed.count == 1 {
            let (before,after) = changed[0]
            if let start = before.stackCents, let end = after.stackCents, start > end,
               let oldPot = old.potCents, (0...(start-end)).contains(pot-oldPot),
               (pot-oldPot != start-end || after.betCents == nil) {
                advance = false // allow a bounded chip/pot animation to settle
                return []
            }
            guard before.activity == .active, after.activity == .active,
                  let start = before.stackCents, let end = after.stackCents, start > end,
                  let wager = after.betCents, wager >= start-end,
                  let oldPot = old.potCents, pot-oldPot == start-end,
                  zip(old.seats,table.seats).allSatisfy({ $0.id == after.id || ($0.betCents == $1.betCents && $0.activity == $1.activity) }) else { return [] }
            let added = start-end, ownBefore = wager-added
            guard knownBets[after.id] == nil || knownBets[after.id] == ownBefore else { return [] }
            let action: SeatAction?
            if let highest, wager > highest { action = highest == 0 && nextStreet > 0 ? .bet : highest > 0 ? .raise : nil }
            else if end > 0, ownBefore < wager, oldActive.contains(where:{ $0.id != after.id && $0.betCents == wager }) { action = .call }
            else { action = nil }
            guard let action else { return [] }
            return [Event(seatID:after.id,action:TrackedAction(time:pendingTime,round:nextRound,street:nextStreet,kind:action,addedCents:added,wagerToCents:wager,evidence:.chips))]
        }
        guard changed.isEmpty, old.potCents == pot,
              zip(old.seats,table.seats).allSatisfy({ $0.betCents == $1.betCents }),
              old.seats.filter(\.isActing).count == 1, table.seats.filter(\.isActing).count == 1,
              let actor = old.seats.first(where: \.isActing), let next = table.seats.first(where: \.isActing), actor.id != next.id, next.activity == .active,
              let now = table.seats.first(where:{ $0.id == actor.id }), actor.activity == .active,
              (actor.stackCents ?? 0) > 0 else { return [] }
        let action: SeatAction?, evidence: ActionEvidence
        if now.activity == .folded, table.activeOpponents.count+(table.hero?.activity == .active ? 1 : 0) >= 2 {
            action = .fold; evidence = .cards
        } else if now.activity == .active, let highest, knownBets[actor.id] == highest {
            action = .check; evidence = .turn
        } else { action = nil; evidence = .turn }
        guard let action else { return [] }
        return [Event(seatID:actor.id,action:TrackedAction(time:pendingTime,round:nextRound,street:nextStreet,kind:action,addedCents:0,wagerToCents:now.betCents,evidence:evidence))]
    }
    private func sameSeats(_ a: TableObservation,_ b: TableObservation) -> Bool {
        a.seats.count == b.seats.count && zip(a.seats,b.seats).allSatisfy { x,y in
            x.id == y.id && x.isHero == y.isHero && x.seatNumber == y.seatNumber &&
            abs(x.bounds.rect.midX-y.bounds.rect.midX) < 0.015 && abs(x.bounds.rect.midY-y.bounds.rect.midY) < 0.015
        }
    }
    private func sameState(_ a: TableObservation,_ b: TableObservation) -> Bool {
        sameSeats(a,b) && a.boardCards == b.boardCards && a.potCents == b.potCents && zip(a.seats,b.seats).allSatisfy { x,y in
            x.stackCents == y.stackCents && x.betCents == y.betCents && x.activity == y.activity && x.isActing == y.isActing
        }
    }
}
