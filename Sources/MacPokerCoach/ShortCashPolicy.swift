import Foundation
import PokerCore
import TableRecognition

enum ShortCashPolicy {
    static func range(_ position: PokerPosition) -> ShortCashRange? {
        switch position {
        case .early,.middle:return .early
        case .hijack:return .hijack
        case .cutoff:return .cutoff
        case .button:return .button
        case .smallBlind:return .smallBlind
        default:return nil
        }
    }
    static func depth(_ table: TableObservation,bigBlind: Int) -> Double? {
        guard bigBlind>0,let hero=table.hero,let own=hero.stackCents,own>0,!table.activeOpponents.isEmpty,
              table.activeOpponents.allSatisfy({ ($0.stackCents ?? 0)>0 }) else { return nil }
        let effective=min(own,table.activeOpponents.compactMap(\.stackCents).min()!)
        return Double(effective)/Double(bigBlind)
    }
    static func suggestion(hole: [Card],table: TableObservation,context: PreflopContext) -> ActionAdvice? {
        guard context.situation == .firstIn,let r=range(context.position),let bb=context.bigBlindCents,bb>0,
              let depth=depth(table,bigBlind:bb),depth>=20,depth<50,
              table.issue==nil,!table.sidePots,table.hero?.activity == .active,
              table.activeOpponents.allSatisfy({ $0.revealedCards.isEmpty }),
              let call=table.callCents,call>0,table.controls?.canCall==true,table.controls?.canRaise==true,
              table.potCents==bb+bb/2,bb%2==0,
              call == (context.position == .smallBlind ? bb/2 : bb),
              table.hero?.betCents==nil || table.hero?.betCents == (context.position == .smallBlind ? bb/2 : 0),
              table.seats.compactMap(\.betCents).allSatisfy({ $0<=bb }),
              !table.seats.contains(where:{ !$0.isHero && $0.action?.entersPot == true }) else { return nil }
        let opens=r.contains(hole)
        guard opens || table.controls?.canFold==true else { return nil }
        return ActionAdvice(title:opens ? "RAISE" : "FOLD",
            reason:"\(HandDetails.startingClass(hole) ?? "Hand"), \(context.position.rawValue.lowercased()), folded to you at \(String(format:"%.1f",depth)) BB effective: \(opens ? "open-raise using a legal client size" : "outside this short-stack opening range"). \(context.source). Explicit 20–49 BB cash raise/fold heuristic; no solver EV, actual opponent response or rake model.",kind:opens ? .raise : .fold,basis:"SHORT CASH OPEN")
    }
}
