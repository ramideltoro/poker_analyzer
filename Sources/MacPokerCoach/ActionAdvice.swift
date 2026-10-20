import Foundation
import PokerCore
import TableRecognition

struct ActionAdvice: Equatable {
    var title: String
    var reason: String
    var kind: SeatAction?
    var marginal = false
    static func priced(equity: Double,estimate: CallEstimate,call: Double) -> ActionAdvice {
        if call == 0 { return ActionAdvice(title:"CHECK",reason:"Checking costs nothing. Keep your hand without adding chips.",kind:.check) }
        let positive = estimate.value >= 0
        let marginal = estimate.lower < estimate.upper && estimate.lower <= 0 && estimate.upper >= 0
        let comparison = String(format:"%.1f%% equity vs %.1f%% needed",equity*100,estimate.requiredEquity*100)
        let value = String(format:"%+.2f USD",estimate.value)
        return ActionAdvice(title:positive ? "CALL" : "FOLD",
            reason:marginal ? "Very close: \(comparison). Call EV \(value); simulation uncertainty crosses zero." :
                positive ? "\(comparison). Calling adds an estimated \(value) on average in this model." :
                "\(comparison). Calling averages \(value); folding avoids that extra cost.",kind:positive ? .call : .fold,marginal:marginal)
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
        if isReview { return ActionAdvice(title:"FOLDED / REVIEW",reason:"These are saved-card probabilities. You have no live decision in this pot.",kind:nil) }
        guard estimateIsCurrent, let estimate = callEstimate, let equity = result?.equity,
              let call = display.decisionCallDollars else { return ActionAdvice(title:"WAIT",reason:amountHelp,kind:nil) }
        if automatic, tableConfirmed, let table, let hand = display.hand, let result,
           let advice = ActionAdvice.riverRaise(hole:hand.hole.map(\.card),board:hand.board.map(\.card),result:result,table:table) { return advice }
        return ActionAdvice.priced(equity:equity,estimate:estimate,call:call)
    }
}
