import Foundation
import Combine
import PokerCore
import TableRecognition

enum RaiseRangePreset: String, CaseIterable { case tight="Tight", balanced="Balanced", loose="Loose"
    func range(reraised: Bool) -> OpponentRange {
        switch self {
        case .tight: return reraised ? .tightReraise : .tightRaise
        case .balanced: return reraised ? .balancedReraise : .balancedRaise
        case .loose: return reraised ? .looseReraise : .looseRaise
        }
    }
}
struct PreflopEvidence: Equatable {
    var heroCalled=false
    var heroRaised=false
    var opponentRaises=0
}
struct RaiseResponseRequest {
    struct Key: Hashable, Sendable { var hole: [Card]; var ranges: [OpponentRange] }
    var key: Key
    var context: StackCallContext
    var quotedCall: Int
    var provenance: String
    var reraised: Bool
    var callClosesBetting: Bool
    static func detectsRaise(_ table: TableObservation,context: PreflopContext,evidence: PreflopEvidence) -> Bool {
        guard let call=table.callCents, call>0 else { return false }
        if context.situation == .raised || evidence.heroCalled || evidence.heroRaised || evidence.opponentRaises>0 || table.activeOpponents.contains(where:{ $0.action == .raise }) { return true }
        guard let own=table.hero?.betCents, let highest=table.activeOpponents.compactMap(\.betCents).max(), highest>own else { return false }
        return context.bigBlindCents.map { highest>$0 }==true || (own>0 && own<=100_000_000 && highest>own*2)
    }
    static func make(hole: [Card],table: TableObservation,context: PreflopContext,evidence: PreflopEvidence,preset: RaiseRangePreset) -> RaiseResponseRequest? {
        guard hole.count==2, Set(hole).count==2, detectsRaise(table,context:context,evidence:evidence),
              table.trackingUsable, table.incompleteReason==nil, table.hero?.activity == .active,
              let hero=table.hero, let own=hero.betCents, (0...100_000_000).contains(own), let stack=hero.stackCents,
              let pot=table.potCents, let call=table.callCents, call>0,
              table.activeOpponents.allSatisfy({ $0.betCents != nil && $0.stackCents != nil && $0.revealedCards.isEmpty }),
              let highest=table.activeOpponents.compactMap(\.betCents).max(), highest>own else { return nil }
        let gap=highest-own, bets=table.seats.compactMap(\.betCents)
        guard bets.allSatisfy({ (0...100_000_000).contains($0) }), bets.reduce(0,+)<=pot,
              call==gap || call==min(gap,stack),
              table.activeOpponents.count==1 || table.activeOpponents.allSatisfy({ ($0.betCents ?? 0)+($0.stackCents ?? 0)>=own+min(gap,stack) }),
              let priced=try? StackCallContext(potCents:pot,uncappedCallCents:gap,heroStackCents:stack,
                    opponentStackCents:table.activeOpponents.compactMap(\.stackCents),sidePots:table.sidePots) else { return nil }
        let reraised=evidence.heroRaised || evidence.opponentRaises>=2
        let range=preset.range(reraised:reraised)
        let ranges=[range]+Array(repeating:OpponentRange.caller,count:table.activeOpponents.count-1)
        let source=evidence.heroCalled ? "After your tracked call" : evidence.heroRaised ? "After your tracked raise" : context.situation == .raised ? "User-confirmed raise" : evidence.opponentRaises>0 ? "Tracked opponent raise" : table.activeOpponents.contains(where:{ $0.action == .raise }) ? "Visible opponent Raise label" : context.bigBlindCents.map { highest>$0 }==true ? "Wager exceeds the configured big blind" : "Wager exceeds twice your committed chips (standard-blind assumption)"
        return RaiseResponseRequest(key:Key(hole:hole.sorted { $0.code<$1.code },ranges:ranges),context:priced,quotedCall:call,provenance:source,reraised:reraised,callClosesBetting:stack<=priced.callCents || table.activeOpponents.allSatisfy { $0.stackCents==0 })
    }
    func advice(result: EquityResult,position: PokerPosition) -> ActionAdvice {
        // A disclosed scenario discount, not an empirical realization estimate or solved action EV.
        let noLaterHeroBetting=callClosesBetting
        let factor: Double
        if noLaterHeroBetting { factor=1 }
        else { switch position { case .cutoff,.button: factor=0.90; case .unknown: factor=0.80; default: factor=0.75 } }
        let pot=Double(context.potCents)/100, call=Double(context.callCents)/100, threshold=call/(pot+call)
        let adjusted=result.equity*factor, shouldCall=adjusted>=threshold
        let marginal=(result.lower*factor...result.upper*factor).contains(threshold)
        let q=String(format:"%.1f",result.equity*100), required=String(format:"%.1f",threshold*100)
        let discount=factor==1 ? "No future hero bets in this eligibility model." : "\(Int(factor*100))% realization scenario (\(position.rawValue.lowercased())): \(String(format:"%.1f",adjusted*100))% vs \(required)% needed."
        let ranges="Assume \(reraised ? "re-raiser" : "raiser") \(key.ranges[0].notation)\(key.ranges.count>1 ? "; \(key.ranges.count-1) others: caller range" : "")."
        return ActionAdvice(title:shouldCall ? "CALL" : "FOLD",reason:"\(provenance). \(String(format:"$%.2f",call)) more into \(String(format:"$%.2f",pot)); \(q)% range equity. \(discount) \(ranges) Earlier chips are sunk. Scenario estimate; no rake or solved future play.",kind:shouldCall ? .call : .fold,marginal:marginal,basis:"RAISE RESPONSE")
    }
}

extension HandAnalysisModel {
    var responseTable: TableObservation? { isPlanning ? (forecastConfirmed ? forecast?.table : nil) : (tableConfirmed && actionControlsConfirmed ? table : nil) }
    func raiseResponseAdvice(for table: TableObservation) -> ActionAdvice? {
        guard let hand=currentHand, hand.board.isEmpty, !hand.isReview,
              RaiseResponseRequest.detectsRaise(table,context:preflopContext,evidence:preflopEvidence) else { return nil }
        guard let request=RaiseResponseRequest.make(hole:hand.hole.map(\.card),table:table,context:preflopContext,evidence:preflopEvidence,preset:raiseRange) else {
            return ActionAdvice(title:"WAIT",reason:"A preflop raise is present. "+(table.incompleteReason ?? "Confirming the additional call against current committed bets and eligible stacks.")+" Earlier context is not the blocker.",kind:nil,availability:.amounts)
        }
        guard responseKey==request.key, let value=raiseResponseResult else {
            return ActionAdvice(title:"WAIT",reason:responseError ?? "Calculating your raise response against the displayed range assumptions. Your earlier call is sunk; no preflop-context entry is required.",kind:nil,availability:.calculating)
        }
        let advice=request.advice(result:value,position:position)
        guard advice.kind == .call ? table.controls?.canCall==true : table.controls?.canFold==true else {
            return ActionAdvice(title:"WAIT",reason:"Confirming a legal Call / Fold control for this raised price.",kind:nil,availability:.controls)
        }
        return advice
    }
    func refreshRaiseResponse() {
        guard automatic, let hand=currentHand, !hand.isReview, hand.board.isEmpty, let table=responseTable,
              let request=RaiseResponseRequest.make(hole:hand.hole.map(\.card),table:table,context:preflopContext,evidence:preflopEvidence,preset:raiseRange) else {
            cancelRaiseResponse(); return
        }
        if responseKey==request.key, raiseResponseResult != nil || responseWorker != nil { return }
        cancelRaiseResponse(); responseKey=request.key
        if let cached=responseCache[request.key] { raiseResponseResult=cached; return }
        let key=request.key, token=responseGeneration, calculate=calculateResponse
        let task=Task.detached(priority:.utility) { try calculate(key.hole,key.ranges,{ Task.isCancelled }) }
        responseWorker=task
        Task { [weak self] in
            let result=await task.result
            guard let self, self.responseGeneration==token else { return }
            self.responseWorker=nil
            switch result {
                        case .success(let result):
                self.raiseResponseResult=result; self.responseError=nil; self.responseCache[key]=result
                self.responseCacheOrder.removeAll { $0==key }; self.responseCacheOrder.append(key)
                if self.responseCacheOrder.count>16 { self.responseCache.removeValue(forKey:self.responseCacheOrder.removeFirst()) }
            case .failure: self.responseError="Raise-response calculation interrupted; retrying on the next confirmed reading."
            }
            self.refreshDisplay()
        }
    }
    func cancelRaiseResponse() {
        responseGeneration=UUID(); responseWorker?.cancel(); responseWorker=nil; responseKey=nil; raiseResponseResult=nil; responseError=nil
    }
}
