import Foundation
import PokerCore
import TableRecognition

/// A disclosed low-confidence plan when a fully priced strategy cannot be supported.
/// Does not supply missing money, change equity, or count an assumed action as observed play.
enum DefaultDecision {
    static func available(_ table: TableObservation?,confirmed: Bool) -> Set<SeatAction>? {
        guard confirmed, let table, table.hero?.activity == .active, table.hero?.stackCents != 0,
              let c=table.controls, let price=table.callCents, price>=0,
              price==0 ? (c.canCheck && !c.canCall) : (c.canCall && !c.canCheck) else { return nil }
        var result=Set<SeatAction>()
        if c.canCheck && price==0 { result.insert(.check) }
        if c.canCall && price>0 { result.insert(.call); result.insert(.fold) } // Standard Hold'em permits folding to a paid wager.
        if c.canFold { result.insert(.fold) }
        if c.canBet && price==0 { result.insert(.bet) }
        if c.canRaise { result.insert(.raise) }
        return result.isEmpty ? nil : result
    }
    static func make(hole:[Card],board:[Card]?,table:TableObservation?,confirmedControls:Bool,
                     context:PreflopContext,evidence:PreflopEvidence) -> ActionAdvice? {
        guard hole.count==2, Set(hole).count==2, table?.hero?.stackCents != 0 else { return nil }
        let legal=available(table,confirmed:true)
        let price=table?.callCents.flatMap { (0...100_000_000).contains($0) ? $0 : nil }
        let free=price==0 || legal?.contains(.check)==true
        let high=max(hole[0].rank,hole[1].rank), low=min(hole[0].rank,hole[1].rank)
        let pair=high==low, suited=hole[0].suit==hole[1].suit
        let premium=pair && high>=13
        let strong=pair && high>=10 || high==14 && low>=12 || suited && high>=12 && low>=11
        var preferred:SeatAction
        var why:String
        if let board, board.isEmpty {
            let raised=table.map { RaiseResponseRequest.detectsRaise($0,context:context,evidence:evidence) }==true || context.situation == .raised || evidence.heroCalled || evidence.heroRaised
            let alreadyInvested=(table?.hero?.betCents ?? 0)>0
            let assumeOpening = !raised && context.situation != .limped && !alreadyInvested
            let position=context.position == .unknown ? PokerPosition.hijack : context.position
            let opening=PreflopContext.opens(hole:hole,position:position) ?? strong
            if premium { preferred = .raise; why="Premium starting pair: prefer a value raise using a legal client size." }
            else if free { preferred = .check; why="Checking keeps the hand for no additional chips." }
            else if assumeOpening && opening {
                preferred = .raise
                why="Fits the default opening range. Assume an unopened pot\(context.position == .unknown ? " and a neutral hijack position" : " from \(context.position.rawValue.lowercased())"); choose a legal raise size."
            } else if strong { preferred = .call; why="Strong starting hand: default to continuing against a paid wager while the range/price analysis updates." }
            else {
                let speculative=pair || suited && (high==14 || high-low<=2 && low>=5)
                if speculative && affordable(table) { preferred = .call; why="Playable speculative hand at a small observed additional price; reassess further raises." }
                else { preferred = .fold; why="Outside the default continuation range at this reading. Earlier chips are sunk; the missing information does not justify committing more." }
            }
        } else if let board, let f=PostflopPolicy.features(hole:hole,board:board) {
            let assumeCheckedTo=free || (price==nil && table?.activeOpponents.contains(where:{ ($0.betCents ?? 0)>(table?.hero?.betCents ?? 0) }) != true)
            if assumeCheckedTo {
                if f.valueHand && f.danger==nil { preferred = .bet; why="\(f.name): default to an unsized value bet when Bet is available. Use the client's legal sizing." }
                else { preferred = .check; why="Checking is free\(f.danger.map { "; \($0)" } ?? ""). Keep the hand without adding chips." }
            } else {
                let rank=Evaluator.evaluate(hole+board)
                let personalPair=rank.category==1 && hole.contains { h in board.contains { $0.rank==h.rank } }
                let flushDraw=Suit.allCases.contains { suit in (hole+board).filter { $0.suit==suit }.count==4 && hole.contains { $0.suit==suit } } && board.count<5
                let playsBoard=board.count==5 && Evaluator.evaluate(board)==rank
                if f.valueHand && (f.danger==nil || affordable(table)) || rank.category>=3 && !playsBoard || (personalPair || flushDraw) && affordable(table) {
                    preferred = .call; why="Made hand\(flushDraw ? " or flush draw" : ""): default to continuing; exact pot eligibility and opponent ranges are not fully verified."
                } else { preferred = .fold; why="No supported strong made hand or cheaply priced draw. Default to protecting remaining chips against a wager." }
            }
        } else {
            preferred = free || price==nil ? .check : .fold
            why=preferred == .check ? "Free-check plan while the board is being read. This assumes no wager to face; it is not a verified current action." : "Board incomplete: conservative fold plan against a wager; no current hand-strength or EV claim."
        }
        let selected:SeatAction
        if let legal {
            if legal.contains(preferred) { selected=preferred }
            else if legal.contains(.check) { selected = .check }
            else if (strong || premium || preferred == .call) && legal.contains(.call) { selected = .call }
            else if legal.contains(.fold) { selected = .fold }
            else if legal.contains(.call) { selected = .call }
            else if legal.contains(.bet) { selected = .bet }
            else if legal.contains(.raise) { selected = .raise }
            else { return nil }
        } else { selected=preferred }
        if selected != preferred {
            why="\(selected.label) fits the currently readable actions. "+(selected == .check ? "It costs no additional chips. " : "")+"The preferred \(preferred.label.lowercased()) action is unavailable."
        }
        let scope=legal==nil || !confirmedControls ? " Conditional on the client offering this action on your turn." : " Uses readable client actions."
        return ActionAdvice(title:selected.label.uppercased(),reason:why+scope+" Lower-confidence default; no verified sizing or full strategic EV.",kind:selected,marginal:true,basis:"DEFAULT PLAN",provisional:true)
    }
    private static func affordable(_ table:TableObservation?) -> Bool {
        guard let table, let call=table.callCents, call>0, let pot=table.potCents, pot>0,
              let stack=table.hero?.stackCents, stack>0,
              call<=100_000_000, pot<=100_000_000, stack<=100_000_000 else { return false }
        return Double(call)/Double(pot+call)<=0.20 && Double(call)/Double(stack)<=0.08
    }
}

extension HandAnalysisModel {
    var decisionIsHistory:Bool {
        guard display.lastShownAdvice != nil else { return showsLastAdvice }
        if let hand=currentHand { return hand.isReview || table?.hero?.stackCents==0 || [.folded,.sittingOut,.waiting].contains(table?.hero?.activity ?? .unknown) }
        if reading.confirmedHole.count==2 { return Set(reading.confirmedHole.map(\.card))==Set(display.lastShownHole) }
        return true
    }
    var decisionAdvice:ActionAdvice {
        let raw=presentedAdvice
        let holes=currentHand?.hole.map(\.card) ?? reading.confirmedHole.map(\.card)
        let matches=holes.isEmpty || Set(holes)==Set(display.lastShownHole)
        if decisionIsHistory && matches, let prior=display.lastShownAdvice { return prior }
        if let hand=currentHand, hand.isReview || table?.hero?.stackCents==0 || [.folded,.sittingOut,.waiting].contains(table?.hero?.activity ?? .unknown) { return showsLastAdvice && raw.kind != nil ? raw : ActionAdvice(title:"—",reason:"There is no current betting decision. Previous moves remain available when one was recorded.",kind:nil) }
        if let kind=raw.kind {
            let legal=DefaultDecision.available(table,confirmed:true)
            if legal==nil || legal!.contains(kind) {
                var value=raw; if isPlanning || legal==nil { value.provisional=true }; return value
            }
        }
        if holes.count==2, let plan=DefaultDecision.make(hole:holes,board:currentHand?.board.map(\.card),table:table ?? planningTable,
            confirmedControls:actionControlsConfirmed,context:preflopContext,evidence:preflopEvidence) { return plan }
        return ActionAdvice(title:"—",reason:raw.reason,kind:nil,availability:raw.availability)
    }
}
