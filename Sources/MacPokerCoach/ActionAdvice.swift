import Foundation
import PokerCore
import TableRecognition

enum AdviceAvailability: String {
    case ready, cards, savedHand, controls, calculating, amounts, unsupported, calculationFailed
    var label: String {
        switch self {
        case .ready: return "Live suggestion"
        case .cards: return "Waiting for cards"
        case .savedHand: return "Saved hand only"
        case .controls: return "Reading action buttons"
        case .calculating: return "Calculating hand odds"
        case .amounts: return "Reading pot / call"
        case .unsupported: return "Decision needs more data"
        case .calculationFailed: return "Calculation interrupted"
        }
    }
}

struct ActionAdvice: Equatable {
    var title: String
    var reason: String
    var kind: SeatAction?
    var marginal = false
    var basis = "PRICE MODEL"
    var availability: AdviceAvailability = .unsupported
    var state: AdviceAvailability { kind == nil ? availability : .ready }
    static func priced(equity: Double,estimate: CallEstimate,call: Double) -> ActionAdvice {
        if call == 0 { return ActionAdvice(title:"CHECK",reason:"Checking costs nothing. Keep your hand without adding chips.",kind:.check) }
        let positive = estimate.value >= 0
        let marginal = estimate.lower <= 0 && estimate.upper >= 0
        let comparison = String(format:"%.1f%% equity vs %.1f%% needed",equity*100,estimate.requiredEquity*100)
        let value = String(format:"%+.2f USD",estimate.value)
        return ActionAdvice(title:positive ? "CALL" : "FOLD",
            reason:(marginal ? "Close choice, low confidence. " : "") + comparison + ". " +
                (positive ? "Call EV \(value)." : "Call EV \(value); folding adds $0.") +
                " Assumes random hands, no later bets or rake.",kind:positive ? .call : .fold,marginal:marginal)
    }
    /// These rules do not need a completed simulation or readable opponent stacks.
    /// Controls still need independent consecutive-frame confirmation in the model.
    static func immediate(hole: [Card],board: [Card],table: TableObservation,confirmedSize: Bool) -> ActionAdvice? {
        guard hole.count == 2, [0,3,4,5].contains(board.count), Set(hole+board).count == hole.count+board.count,
              table.hero?.activity == .active, table.hero?.stackCents != 0, let controls = table.controls, let call = table.callCents,
              call >= 0, call == 0 ? (controls.canCheck && !controls.canCall) : (controls.canCall && !controls.canCheck) else { return nil }
        if board.isEmpty, hole[0].rank == hole[1].rank, hole[0].rank >= 13,
           !table.sidePots, table.issue == nil, controls.canRaise,
           table.activeOpponents.allSatisfy({ $0.revealedCards.isEmpty }),
           table.activeOpponents.contains(where:{ $0.stackCents == nil || ($0.stackCents ?? 0) > 0 }),
           let stack = table.hero?.stackCents, stack > call, stack <= 100_000_000,
           raisePriceIsConsistent(table) {
            let name = hole[0].rank == 13 ? "KK" : "AA"
            if confirmedSize, let target = premiumRaiseTo(table) {
                return ActionAdvice(title:"RAISE",reason:"\(name): raise to \(String(format:"$%.2f",Double(target)/100)) for preflop value (displayed size). Premium-hand rule; very tight re-raises need caution.",kind:.raise,basis:"PREFLOP RULE")
            }
            return ActionAdvice(title:"RAISE",reason:"\(name): raise for preflop value. Size is not confirmed; choose a legal size offered by the table. Typical cash-game rule; very tight re-raises need caution.",kind:.raise,basis:"PREFLOP RULE")
        }
        if call == 0 {
            if let own = table.hero?.betCents, table.activeOpponents.contains(where:{ ($0.betCents ?? 0) > own }) { return nil }
            return ActionAdvice(title:"CHECK",reason:"Checking costs $0 and keeps your hand in the pot. Probabilities and other stacks can keep updating; this does not establish whether betting would earn more.",kind:.check)
        }
        return nil
    }
    private static func raisePriceIsConsistent(_ table: TableObservation) -> Bool {
        guard let call = table.callCents, let pot = table.potCents, pot > 0, pot >= call else { return false }
        let bets = table.seats.compactMap(\.betCents)
        guard bets.allSatisfy({ (0...100_000_000).contains($0) }), bets.reduce(0,+) <= pot else { return false }
        if let own = table.hero?.betCents {
            let foes = table.activeOpponents.compactMap(\.betCents), gap = max(0,(foes.max() ?? 0)-own)
            if gap > call || (foes.count == table.activeOpponents.count && gap != call) { return false }
        }
        return true
    }
    /// Strategy and a check-down pot-share calculation answer different questions.
    /// Premium preflop pairs must not be folded just because a many-way random
    /// simulation keeps every opponent in to showdown. This is an explicit,
    /// limited cash-game value rule, not a range-aware or solver EV calculation.
    static func recommend(hole: [Card],board: [Card],result: EquityResult,estimate: CallEstimate,call: Double,table: TableObservation?) -> ActionAdvice {
        guard hole.count == 2, [0,3,4,5].contains(board.count), Set(hole+board).count == hole.count+board.count else {
            return ActionAdvice(title:"WAIT",reason:"Confirming the current cards.",kind:nil,availability:.cards)
        }
        if let table {
            guard table.hero?.activity == .active else { return ActionAdvice(title:"WAIT",reason:"Confirming that your hand is still active.",kind:nil,availability:.cards) }
            guard table.activeOpponents.allSatisfy({ $0.revealedCards.isEmpty }) else {
                return ActionAdvice(title:"REVIEW",reason:"Opponent cards are visible. This random-hand model does not include those known cards, so it cannot support an action.",kind:nil)
            }
            if let controls = table.controls {
                guard call == 0 ? controls.canCheck : controls.canCall else {
                    return ActionAdvice(title:"WAIT",reason:"The call price and available actions disagree. Confirming fresh controls.",kind:nil,availability:.controls)
                }
            }
            if let advice = immediate(hole:hole,board:board,table:table,confirmedSize:true) { return advice }
        }
        if board.isEmpty, hole[0].rank == hole[1].rank, hole[0].rank >= 13 {
            let name = hole[0].rank == 13 ? "KK" : "AA"
            if call == 0 { return ActionAdvice(title:"CHECK",reason:"\(name) normally wants a value raise preflop; no supported raise size is readable. Checking is free.",kind:.check,basis:"PREFLOP RULE") }
            return ActionAdvice(title:"CALL",reason:"\(name) is a premium preflop pair: continue under the cash-game starting-hand rule. No supported value raise is available. Actual re-raising ranges can change this choice.",kind:.call,basis:"PREFLOP RULE")
        }
        if let table, let advice = riverRaise(hole:hole,board:board,result:result,table:table) { return advice }
        var advice = priced(equity:result.equity,estimate:estimate,call:call)
        if board.isEmpty, call > 0 {
            advice.basis = "PREFLOP PRICE"
            advice.reason = advice.reason.replacingOccurrences(of:"Assumes random hands, no later bets or rake.",with:"Random hands; position, betting ranges, later bets and rake are not modeled.")
        }
        return advice
    }
    /// Use only the quoted raise-to control, with a conservative full-raise
    /// bound and enough remaining chips on both sides. Never invent a size.
    private static func premiumRaiseTo(_ table: TableObservation) -> Int? {
        guard !table.sidePots, table.issue == nil, let controls = table.controls, controls.canRaise,
              let target = controls.raiseToCents, (1...100_000_000).contains(target),
              let call = table.callCents, (0...100_000_000).contains(call),
              let hero = table.hero, let ownBet = hero.betCents, (0...100_000_000).contains(ownBet),
              let stack = hero.stackCents, (1...100_000_000).contains(stack),
              ownBet+call > 0, target >= 2*(ownBet+call), target-ownBet <= stack,
              table.activeOpponents.allSatisfy({ ($0.betCents ?? 0) <= ownBet+call }),
              table.activeOpponents.contains(where:{ foe in
                  guard let bet = foe.betCents, let stack = foe.stackCents, bet >= 0, stack >= 0 else { return false }
                  return bet <= target && target-bet <= stack
              }) else { return nil }
        return target
    }
    /// Only a quoted full raise facing a first heads-up river wager with an unbeatable hand.
    /// Showdown equity alone is never used to infer a general raise EV.
    static func riverRaise(hole: [Card],board: [Card],result: EquityResult,table: TableObservation) -> ActionAdvice? {
        guard hole.count == 2, board.count == 5, Set(hole+board).count == 7,
              result.exact, result.outcomes?.lose == 0, (result.outcomes?.win ?? 0) > 0,
              table.activeOpponents.count == 1, !table.sidePots,
              Evaluator.evaluate(hole+board) > Evaluator.evaluate(board),
              let controls = table.controls, controls.canRaise,
              let target = controls.raiseToCents, let call = table.callCents, call > 0,
              let hero = table.hero, hero.activity == .active, let stack = hero.stackCents,
              let foe = table.activeOpponents.first, let foeStack = foe.stackCents, let foeBet = foe.betCents else { return nil }
        let ownBet = hero.betCents ?? (foeBet-call)
        guard ownBet == 0, foeBet-ownBet == call, target >= foeBet*2, target-ownBet <= stack,
              target-foeBet <= foeStack, target-foeBet > 0 else { return nil }
        let amount = String(format:"$%.2f",Double(target)/100)
        return ActionAdvice(title:"RAISE",reason:"Unbeatable river hand against one opponent. Raise to \(amount), as shown in the control, for value. Worse hands may call; calls are not guaranteed.",kind:.raise)
    }
}

extension HandAnalysisModel {
    var actionAdvice: ActionAdvice {
        guard let hand = currentHand else { return ActionAdvice(title:"WAIT",reason:"No current cards are confirmed. A decision starts automatically once a fresh hand and its action buttons are readable.",kind:nil,availability:.cards) }
        if hand.isReview { return ActionAdvice(title:"REVIEW",reason:"Only saved cards are available after your cards disappeared. What-if calculations continue; there is no live action for these saved cards.",kind:nil,basis:"SAVED CARDS",availability:.savedHand) }
        if automatic, actionControlsConfirmed, let table,
           let advice = ActionAdvice.immediate(hole:hand.hole.map(\.card),board:hand.board.map(\.card),table:table,confirmedSize:tableConfirmed) { return advice }
        if automatic, table?.controls != nil, !actionControlsConfirmed {
            return ActionAdvice(title:"WAIT",reason:"Confirming your current Call / Check buttons across two readings. New cards, disappearing buttons or a changed call price immediately clear the old action.",kind:nil,availability:.controls)
        }
        if calculating { return ActionAdvice(title:"WAIT",reason:"Calculating equity for the current cards and active players. A priced decision appears automatically when the calculation finishes.",kind:nil,availability:.calculating) }
        if let error { return ActionAdvice(title:"WAIT",reason:error,kind:nil,availability:.calculationFailed) }
        guard estimateIsCurrent, let estimate = callEstimate, let result,
              let call = display.decisionCallDollars else {
            let missingControls = automatic && table?.callCents == nil
            return ActionAdvice(title:"WAIT",reason:missingControls ? "No readable Call / Check buttons. They may be hidden between turns. Scanning continues; the suggestion returns when they reappear." : amountHelp,kind:nil,availability:missingControls ? .controls : .amounts)
        }
        return ActionAdvice.recommend(hole:hand.hole.map(\.card),board:hand.board.map(\.card),result:result,estimate:estimate,call:call,table:automatic && tableConfirmed ? table : nil)
    }
}
