import Foundation
import PokerCore
import TableRecognition

/// Transparent value heuristics. Does not equate random-hand equity with betting EV.
enum PostflopPolicy {
    struct Features {
        var name: String
        var valueHand: Bool
        var danger: String?
    }
    static func features(hole: [Card],board: [Card]) -> Features? {
        guard hole.count==2, (3...5).contains(board.count), Set(hole+board).count==hole.count+board.count else { return nil }
        let rank=Evaluator.evaluate(hole+board), ranks=Dictionary(grouping:board,by:\.rank)
        let suits=Dictionary(grouping:board,by:\.suit), flushCount=suits.values.map(\.count).max() ?? 0
        var distinct=Set(board.map(\.rank)); if distinct.contains(14) { distinct.insert(1) }
        let connected=(5...14).map { high in (0..<5).filter { distinct.contains(high-$0) }.count }.max() ?? 0
        let paired=ranks.values.contains { $0.count>=2 }
        let personalTwoPair=rank.category==2 && hole[0].rank != hole[1].rank &&
            hole.allSatisfy { ranks[$0.rank]?.count==1 } && !paired
        let set=rank.category==3 && hole[0].rank==hole[1].rank && ranks[hole[0].rank]?.count==1
        let playsBoard=board.count==5 && Evaluator.evaluate(board)==rank
        let ownsFlushAce=hole.contains { c in c.rank==14 && (suits[c.suit]?.count ?? 0)>=3 }
        let strongFlush=rank.category==5 && (flushCount==3 || ownsFlushAce)
        let boatOrBetter=rank.category>=6 && !playsBoard
        let straight=rank.category==4 && !playsBoard && connected<=3
        let value=personalTwoPair || set || strongFlush || boatOrBetter || straight
        let danger: String?
        if playsBoard { danger="the best hand is on the board" }
        else if rank.category<5 && flushCount>=3 { danger="a flush is possible" }
        else if rank.category<4 && connected>=3 { danger="a straight is possible" }
        else if rank.category<6 && paired { danger="the paired board weakens this made hand" }
        else if rank.category==5 && !strongFlush { danger="a higher one-card flush can dominate" }
        else { danger=nil }
        return Features(name:personalTwoPair ? "Two pair made with both hole cards" : set ? "A set" : rank.name,valueHand:value,danger:danger)
    }
    static func aggressive(hole: [Card],board: [Card],table: TableObservation,confirmed: Bool,
                           situation: PreflopSituation = .unknown,position: PokerPosition = .unknown) -> ActionAdvice? {
        guard let f=features(hole:hole,board:board), f.valueHand, f.danger==nil,
              confirmed, table.incompleteReason==nil, !table.sidePots,
              let hero=table.hero, hero.activity == .active, let stack=hero.stackCents, stack>0,
              !table.activeOpponents.isEmpty,
              table.activeOpponents.allSatisfy({ $0.revealedCards.isEmpty && $0.stackCents != nil }),
              table.activeOpponents.contains(where:{ ($0.stackCents ?? 0)>0 }),
              let pot=table.potCents, pot>0, let call=table.callCents, let controls=table.controls,
              table.seats.compactMap(\.betCents).allSatisfy({ (0...100_000_000).contains($0) }),
              table.seats.compactMap(\.betCents).reduce(0,+)<=pot else { return nil }
        let players=table.activeOpponents.count+1
        if call==0, controls.canCheck, !controls.canCall, controls.canBet {
            if let own=hero.betCents, table.activeOpponents.contains(where:{ ($0.betCents ?? 0)>own }) { return nil }
            return ActionAdvice(title:"BET",reason:"\(f.name): bet for value from worse hands and deny a free card in this \(players)-way pot. Around half pot is a starting point; choose a legal size. Value heuristic; calling ranges and responses are unknown.",kind:.bet,basis:"VALUE BET")
        }
        // Narrow first-wager flop raise, not automatic stack commitment with any two pair.
        if board.count==3, situation == .limped, [.cutoff,.button].contains(position),
           call>0, call<=pot/3, controls.canCall, !controls.canCheck, controls.canRaise,
           hero.betCents==0, table.activeOpponents.allSatisfy({ $0.betCents != nil }),
           table.activeOpponents.compactMap(\.betCents).max()==call,
           stack>call*3, table.activeOpponents.contains(where:{ ($0.stackCents ?? 0)>call*2 }),
           table.activeOpponents.filter({ ($0.betCents ?? 0)>0 }).count==1 {
            return ActionAdvice(title:"RAISE",reason:"\(f.name) on a low-threat flop in a limped pot. A value raise can charge worse pairs and draws against this modest first bet. Choose a legal size; a re-raise or larger bet needs fresh assessment. Heuristic, not solved EV.",kind:.raise,basis:"VALUE RAISE")
        }
        return nil
    }
    static func checkReason(hole: [Card],board: [Card]) -> String {
        if let f=features(hole:hole,board:board), let danger=f.danger {
            return "Check cautiously: \(danger). The hand category alone does not justify building this pot. Free-check baseline, not proof that betting loses money."
        }
        return "Checking costs $0. No supported value-bet rule applies to this reading; preserve the hand and reassess new action. This baseline does not compare all betting strategies."
    }
}
