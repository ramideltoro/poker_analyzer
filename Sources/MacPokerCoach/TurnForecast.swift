import Foundation
import PokerCore
import TableRecognition

struct TurnForecast {
    var table: TableObservation
    var assumedFoldIDs: [Int]
    var orderKnown: Bool
    var callCents: Int?
    var result: EquityResult?
    var calculating=false
    var issue: String?
    var opponents: Int { table.activeOpponents.count }
    var assumption: String {
        if !orderKnown { return "Turn order unknown: all visible players retained." }
        return "Assume \(assumedFoldIDs.count) player\(assumedFoldIDs.count==1 ? "" : "s") before you fold; committed chips stay in the pot."
    }
    var context: StackCallContext? {
        guard issue==nil, let call=callCents, table.incompleteReason==nil,
              let pot=table.potCents, let hero=table.hero?.stackCents,
              let context=try? StackCallContext(potCents:pot,uncappedCallCents:call,heroStackCents:hero,
                  opponentStackCents:table.activeOpponents.compactMap(\.stackCents),sidePots:table.sidePots) else { return nil }
        return context
    }
    var estimate: CallEstimate? { guard let result, let context else { return nil }; return try? context.estimate(result) }
    static func make(_ observed: TableObservation,position: PokerPosition,board: [Card],bigBlindCents: Int? = nil) -> TurnForecast? {
        guard observed.trackingUsable, observed.hero?.activity == .active,
              observed.seats.allSatisfy({ $0.activity != .unknown }), (2...9).contains(observed.seats.count) else { return nil }
        // Detector IDs are clockwise screen positions, beginning just after hero.
        let ring=observed.seats.sorted { $0.id<$1.id }
        guard let heroIndex=ring.firstIndex(where: \.isHero) else { return nil }
        let actors=ring.indices.filter { ring[$0].isActing && ring[$0].activity == .active && (ring[$0].stackCents ?? 0)>0 }
        var pending=[Int](), known=false
        if actors.count==1, let actor=actors.first {
            known=true; var i=actor
            while i != heroIndex { pending.append(ring[i].id); i=(i+1)%ring.count }
        } else if board.isEmpty {
            // Fallback only for precise positions and a complete active/folded roster.
            let dealt=ring.filter { [.active,.folded].contains($0.activity) }
            if let h=dealt.firstIndex(where: \.isHero), dealt.count>=4, dealt.count==ring.count {
                let offset: Int?
                switch position {
                case .cutoff: offset=1
                case .hijack: offset=dealt.count>=5 ? 2 : nil
                case .button: offset=0
                case .smallBlind: offset=dealt.count-1
                case .bigBlind: offset=dealt.count-2
                default: offset=nil
                }
                if let offset {
                    let start=(h+offset+3)%dealt.count
                    var i=start; known=true
                    while i != h {
                        let seat=dealt[i]
                        // An already observed voluntary action is not an assumed fold.
                        if seat.action?.entersPot != true && (seat.betCents ?? 0)==0 { pending.append(seat.id) }
                        i=(i+1)%dealt.count
                    }
                }
            }
        }
        var copy=observed
        let folds=copy.seats.filter { pending.contains($0.id) && !$0.isHero && $0.activity == .active && ($0.stackCents ?? 0)>0 }.map(\.id)
        for i in copy.seats.indices where folds.contains(copy.seats[i].id) { copy.seats[i].activity = .folded }
        let active=observed.seats.filter { $0.activity == .active || $0.isHero }
        let call: Int?
        if let own=observed.hero?.betCents, active.allSatisfy({ $0.betCents != nil }) {
            call=max(0,(active.compactMap(\.betCents).max() ?? 0)-own)
        } else { call=nil }
        copy.callCents=call
        copy.controls=call.map { TableControls(canFold:true,canCheck:$0==0,canCall:$0>0,canBet:$0==0,canRaise:$0>0) }
        var issue: String?
        if let call, call>0, let own=observed.hero?.betCents,
           !copy.activeOpponents.contains(where:{ $0.betCents==own+call }) {
            issue="The highest wager would leave the hand under this fold assumption; call pricing is unsupported."
        }
        return TurnForecast(table:copy,assumedFoldIDs:folds,orderKnown:known,callCents:call,issue:issue)
    }
    func advice(hole: [Card],board: [Card],context: PreflopContext) -> ActionAdvice {
        guard opponents>0 else { return ActionAdvice(title:"WAIT",reason:"If every remaining opponent folds, the hand ends before another betting decision. \(assumption)",kind:nil,availability:.forecast) }
        guard table.activeOpponents.allSatisfy({ $0.revealedCards.isEmpty }) else {
            return ActionAdvice(title:"WAIT",reason:"Opponent cards are visible; the random-hand forecast does not model those known cards. Confirm the next hand before using a priced plan.",kind:nil,availability:.forecast)
        }
        if let issue { return ActionAdvice(title:"WAIT",reason:issue+" "+assumption,kind:nil,availability:.forecast) }
        if board.isEmpty {
            if let premium=ActionAdvice.immediate(hole:hole,board:board,table:table,confirmedSize:true) {
                var plan=premium; plan.reason="Conditional plan. "+plan.reason; return plan
            }
            var projectedContext=context
            if projectedContext.situation == .unknown, orderKnown, let bb=context.bigBlindCents,
               let pot=table.potCents, pot>=bb, pot<=bb*2,
               table.seats.allSatisfy({ ($0.betCents ?? Int.max)<=bb && $0.action?.entersPot != true }) {
                projectedContext.situation = .firstIn
            }
            if let opening=projectedContext.suggestion(hole:hole,table:table) {
                var plan=opening; plan.reason="Conditional assuming-folds plan. "+plan.reason.replacingOccurrences(of:"User-confirmed first-in context",with:"Projected first-in context"); return plan
            }
            return ActionAdvice(title:"WAIT",reason:"Preflop plan needs position, prior action, readable wagers and supported stack depth. \(assumption)",kind:nil,availability:.forecast)
        }
        if callCents==nil {
            if table.activeOpponents.contains(where:{ ($0.betCents ?? 0)>0 }) { return ActionAdvice(title:"WAIT",reason:"A wager is visible but the additional call cannot be resolved. Equity keeps updating; confirming the current wagers before a price-based plan.",kind:nil,availability:.forecast) }
            // Explicit counterfactual, never a claim that the current call is free.
            var checked=table; checked.callCents=0; checked.controls=TableControls(canCheck:true,canBet:true)
            if let value=PostflopPolicy.aggressive(hole:hole,board:board,table:checked,confirmed:true,situation:context.situation,position:context.position) {
                var plan=value; plan.reason="If checked to you: "+plan.reason; return plan
            }
            if let f=PostflopPolicy.features(hole:hole,board:board), f.valueHand, f.danger==nil {
                return ActionAdvice(title:"WAIT",reason:"Strong made hand: a value-bet plan needs readable pot and stacks. The current call is also unreadable; equity continues updating.",kind:nil,availability:.forecast)
            }
            return ActionAdvice(title:"CHECK",reason:"If checked to you: "+PostflopPolicy.checkReason(hole:hole,board:board)+" Current call price is unreadable.",kind:.check,basis:"CONDITIONAL PLAN")
        }
        if let value=PostflopPolicy.aggressive(hole:hole,board:board,table:table,confirmed:true,situation:context.situation,position:context.position) { return value }
        if callCents==0 {
            if let f=PostflopPolicy.features(hole:hole,board:board), f.valueHand, f.danger==nil {
                return ActionAdvice(title:"WAIT",reason:"Strong made hand: confirming the pot, stacks and eligible opponents before a value-bet plan. Missing readings do not make Check the best action.",kind:nil,availability:.forecast)
            }
            return ActionAdvice(title:"CHECK",reason:PostflopPolicy.checkReason(hole:hole,board:board),kind:.check,basis:"CONDITIONAL PLAN")
        }
        if let result, let estimate, let callCents {
            return ActionAdvice.priced(equity:result.equity,estimate:estimate,call:Double(callCents)/100)
        }
        return ActionAdvice(title:"WAIT",reason:"Updating the conditional price and equity. "+assumption,kind:nil,availability:.forecast)
    }
}
