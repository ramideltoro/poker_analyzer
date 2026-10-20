import Foundation
import PokerCore
import TableRecognition

struct ActionAdvice: Equatable {
    var title: String
    var reason: String
    var kind: SeatAction?
    var marginal = false
    var basis = "PRICE MODEL"
    static func priced(equity: Double,estimate: CallEstimate,call: Double) -> ActionAdvice {
        if call == 0 { return ActionAdvice(title:"CHECK",reason:"Checking costs nothing. Keep your hand without adding chips.",kind:.check) }
        let positive = estimate.value >= 0
        let marginal = estimate.lower < estimate.upper && estimate.lower <= 0 && estimate.upper >= 0
        let comparison = String(format:"%.1f%% equity vs %.1f%% needed",equity*100,estimate.requiredEquity*100)
        let value = String(format:"%+.2f USD",estimate.value)
        if marginal { return ActionAdvice(title:"REVIEW",reason:"Too close to choose: \(comparison). Check-down call EV \(value); simulation uncertainty crosses zero.",kind:nil,marginal:true) }
        return ActionAdvice(title:positive ? "CALL" : "FOLD",
            reason:positive ? "\(comparison). Calling is \(value) if no more chips go in, against random hands. Later bets and tighter ranges can change this." :
                "Price model favors folding: \(comparison); check-down call EV \(value). Assumes random hands and no later betting.",kind:positive ? .call : .fold)
    }
    /// Strategy and a check-down pot-share calculation answer different questions.
    /// Premium preflop pairs must not be folded just because a many-way random
    /// simulation keeps every opponent in to showdown. This is an explicit,
    /// limited cash-game value rule, not a range-aware or solver EV calculation.
    static func recommend(hole: [Card],board: [Card],result: EquityResult,estimate: CallEstimate,call: Double,table: TableObservation?) -> ActionAdvice {
        guard hole.count == 2, [0,3,4,5].contains(board.count), Set(hole+board).count == hole.count+board.count else {
            return ActionAdvice(title:"WAIT",reason:"Confirming the current cards.",kind:nil)
        }
        if let table {
            guard table.hero?.activity == .active else { return ActionAdvice(title:"WAIT",reason:"Confirming that your hand is still active.",kind:nil) }
            guard table.activeOpponents.allSatisfy({ $0.revealedCards.isEmpty }) else {
                return ActionAdvice(title:"REVIEW",reason:"Opponent cards are visible. This random-hand model does not include those known cards, so it cannot support an action.",kind:nil)
            }
            if let controls = table.controls {
                guard call == 0 ? controls.canCheck : controls.canCall else {
                    return ActionAdvice(title:"WAIT",reason:"The call price and available actions disagree. Confirming fresh controls.",kind:nil)
                }
            }
        }
        if board.isEmpty, hole[0].rank == hole[1].rank, hole[0].rank >= 13 {
            let name = hole[0].rank == 13 ? "KK" : "AA"
            if let table, let target = premiumRaiseTo(table) {
                return ActionAdvice(title:"RAISE",reason:"\(name): raise to \(String(format:"$%.2f",Double(target)/100)) for preflop value (displayed size). Premium-hand rule; very tight re-raises need review.",kind:.raise,basis:"PREFLOP RULE")
            }
            if call == 0 { return ActionAdvice(title:"CHECK",reason:"\(name) normally wants a value raise preflop; no supported raise size is readable. Checking is free.",kind:.check,basis:"PREFLOP RULE") }
            if estimate.lower > 0 {
                return ActionAdvice(title:"CALL",reason:"\(name) is a premium preflop pair. No verified raise size; calling passes the random-hand price test. Tight re-raises need review.",kind:.call,basis:"PREFLOP RULE")
            }
            return ActionAdvice(title:"REVIEW",reason:"\(name) is a premium preflop pair. Check-down EV alone cannot justify FOLD. Confirm raise controls and consider opponents’ re-raising ranges.",kind:nil,basis:"PREFLOP RULE")
        }
        if let table, let advice = riverRaise(hole:hole,board:board,result:result,table:table) { return advice }
        if board.isEmpty, call > 0, estimate.lower <= 0 {
            return ActionAdvice(title:"REVIEW",reason:"Preflop check-down EV is not enough to choose a fold. Position, raising options and opponents’ betting ranges are not modeled here.",kind:nil,marginal:estimate.upper >= 0)
        }
        let advice = priced(equity:result.equity,estimate:estimate,call:call)
        if advice.kind == .fold, let controls = table?.controls, !controls.canFold {
            return ActionAdvice(title:"WAIT",reason:"No confirmed Fold control. Waiting for your available actions.",kind:nil)
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
        if isReview { return ActionAdvice(title:"REVIEW",reason:"Saved-card probabilities only. This is not a Fold suggestion; no live action is recommended while your current cards are not visible.",kind:nil,basis:"SAVED CARDS") }
        guard estimateIsCurrent, let estimate = callEstimate, let result, let hand = display.hand,
              let call = display.decisionCallDollars else { return ActionAdvice(title:"WAIT",reason:amountHelp,kind:nil) }
        return ActionAdvice.recommend(hole:hand.hole.map(\.card),board:hand.board.map(\.card),result:result,estimate:estimate,call:call,table:automatic && tableConfirmed ? table : nil)
    }
}
