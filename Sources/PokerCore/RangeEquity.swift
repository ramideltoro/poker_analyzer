import Foundation

/// Transparent, uncalibrated cash-game assumptions. Every legal combo in a range has equal weight.
public enum OpponentRange: String, CaseIterable, Hashable, Sendable {
    case random, caller, tightRaise, balancedRaise, looseRaise, tightReraise, balancedReraise, looseReraise
    case shortEarlyOpen,shortHijackOpen,shortCutoffOpen,shortButtonOpen,shortSmallBlindOpen
    private var shortOpening: ShortCashRange? {
        switch self {
        case .shortEarlyOpen:return .early
        case .shortHijackOpen:return .hijack
        case .shortCutoffOpen:return .cutoff
        case .shortButtonOpen:return .button
        case .shortSmallBlindOpen:return .smallBlind
        default:return nil
        }
    }
    public var notation: String {
        if let shortOpening { return shortOpening.notation }
        switch self {
        case .random: return "any legal hand"
        case .caller: return "22+,A2s+,K9s+,Q9s+,J9s+,T9s,98s,87s,76s,65s,ATo+,KJo+,QJo"
        case .tightRaise: return "TT+,AQs+,AKo"
        case .balancedRaise: return "77+,ATs+,KJs+,QJs,JTs,AJo+,KQo"
        case .looseRaise: return "22+,A2s+,K8s+,Q9s+,J9s+,T9s,98s,87s,76s,65s,A9o+,KTo+,QTo+,JTo"
        case .tightReraise: return "KK+,AKs"
        case .balancedReraise: return "QQ+,AK"
        case .looseReraise: return "TT+,AQs+,AKo"
        case .shortEarlyOpen,.shortHijackOpen,.shortCutoffOpen,.shortButtonOpen,.shortSmallBlindOpen:return ""
        }
    }
    public func contains(_ cards: [Card]) -> Bool {
        guard cards.count==2, cards[0] != cards[1] else { return false }
        if let shortOpening { return shortOpening.contains(cards) }
        let h=max(cards[0].rank,cards[1].rank), l=min(cards[0].rank,cards[1].rank), s=cards[0].suit==cards[1].suit
        if self == .random { return true }
        if h==l {
            switch self {
            case .caller,.looseRaise: return true
            case .balancedRaise: return h>=7
            case .tightRaise,.looseReraise: return h>=10
            case .balancedReraise: return h>=12
            case .tightReraise: return h>=13
            default: return true
            }
        }
        switch self {
        case .tightReraise: return h==14 && l==13 && s
        case .balancedReraise: return h==14 && l==13
        case .tightRaise,.looseReraise: return h==14 && (s ? l>=12 : l==13)
        case .balancedRaise: return s ? (h==14 && l>=10) || (h==13 && l>=11) || (h==12 && l==11) || (h==11 && l==10) : (h==14 && l>=11) || (h==13 && l==12)
        case .caller,.looseRaise:
            if s { return h==14 || (h==13 && l >= (self == .caller ? 9 : 8)) || (h==12 && l>=9) || (h==11 && l>=9) || (h-l==1 && l>=5) }
            return (h==14 && l >= (self == .caller ? 10 : 9)) || (h==13 && l >= (self == .caller ? 11 : 10)) || (h==12 && l >= (self == .caller ? 11 : 10)) || (self == .looseRaise && h==11 && l==10)
        case .random: return true
        case .shortEarlyOpen,.shortHijackOpen,.shortCutoffOpen,.shortButtonOpen,.shortSmallBlindOpen:return false
        }
    }
}

public enum RangeEquityError: Error { case emptyOrIncompatibleRanges }
private struct RangeRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var n=state; n=(n ^ (n>>30)) &* 0xbf58476d1ce4e5b9; n=(n ^ (n>>27)) &* 0x94d049bb133111eb
        return n ^ (n>>31)
    }
}
public enum RangeEquityEngine {
    private static let deck=Suit.allCases.flatMap { suit in (2...14).map { Card(rank:$0,suit:suit) } }
    private static func bit(_ c: Card) -> UInt64 { 1 << ((c.rank-2)*4+Suit.allCases.firstIndex(of:c.suit)!) }
    private struct Combo { var cards: [Card]; var mask: UInt64 }
    public static func calculate(hole: [Card],board: [Card] = [],ranges: [OpponentRange],samples: Int = 100_000,
                                 seed: UInt64 = UInt64.random(in:1...UInt64.max),cancelled: @Sendable () -> Bool = { false }) throws -> EquityResult {
        let known=hole+board
        guard hole.count==2, [0,3,4,5].contains(board.count), Set(known).count==known.count else { throw EquityError.invalidCards }
        guard (1...8).contains(ranges.count) else { throw EquityError.invalidOpponents }
        guard (1...1_000_000).contains(samples) else { throw EquityError.invalidSamples }
        if cancelled() { throw EquityError.cancelled }
        let available=deck.filter { !known.contains($0) }
        let pools=ranges.map { range in
            var combos=[Combo]()
            for a in 0..<available.count-1 { for b in a+1..<available.count {
                let cards=[available[a],available[b]]
                if range.contains(cards) { combos.append(Combo(cards:cards,mask:bit(cards[0]) | bit(cards[1]))) }
            } }
            return combos
        }
        guard pools.allSatisfy({ !$0.isEmpty }), pools.flatMap({ $0 }).reduce(UInt64(0),{ $0 | $1.mask }).nonzeroBitCount >= ranges.count*2 else { throw RangeEquityError.emptyOrIncompatibleRanges }
        var rng=RangeRandom(state:seed), sum=0.0, wins=0, ties=0, categories=[Int](repeating:0,count:9)
        var count=0, attempts=0
        let exact=board.count==5 && ranges.count==1
        while count < (exact ? pools[0].count : samples) {
            attempts+=1
            if attempts%64==0 && cancelled() { throw EquityError.cancelled }
            guard exact || attempts<=max(10_000,samples*200) else { throw RangeEquityError.emptyOrIncompatibleRanges }
            var occupied:UInt64=0, villains=[[Card]](), compatible=true
            // Draw independent combos, then reject the WHOLE tuple on collisions.
            // Sequentially filtering later ranges would bias earlier players' combo weights.
            for pool in pools {
                let combo=exact ? pool[count] : pool[Int.random(in:0..<pool.count,using:&rng)]
                if occupied & combo.mask != 0 { compatible=false; break }
                occupied |= combo.mask; villains.append(combo.cards)
            }
            if !compatible { continue }
            var remaining=available.filter { occupied & bit($0)==0 }
            let missing=5-board.count
            for i in 0..<missing { remaining.swapAt(i,Int.random(in:i..<remaining.count,using:&rng)) }
            let runout=board+remaining.prefix(missing), hero=Evaluator.evaluate(hole+runout)
            var shareCount=1, lost=false
            for villain in villains {
                let rank=Evaluator.evaluate(villain+runout)
                if rank>hero { lost=true; break }; if rank==hero { shareCount+=1 }
            }
            categories[hero.category]+=1
            if !lost { sum+=1/Double(shareCount); if shareCount==1 { wins+=1 } else { ties+=1 } }
            count+=1
        }
        return EquityResult(equity:sum/Double(count),samplingBound:exact ? 0 : sqrt(log(40)/(2*Double(count))),samples:count,exact:exact,
            outcomes:ShowdownProbabilities(win:Double(wins)/Double(count),tie:Double(ties)/Double(count),lose:Double(count-wins-ties)/Double(count)),
            categoryProbabilities:categories.map { Double($0)/Double(count) })
    }
}
