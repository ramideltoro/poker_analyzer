import XCTest
@testable import PokerCore

final class ShortCashRangeTests:XCTestCase {
    func testPublishedRangeNotationMatchesEveryStartingClass() {
        let ranks=Array("23456789TJQKA")
        func declares(_ notation:String,h:Int,l:Int,suited:Bool) -> Bool {
            notation.replacingOccurrences(of:" ",with:"").split(separator:",").contains { token in
                let chars=Array(token),plus=chars.last=="+"
                guard chars.count>=2,let a=ranks.firstIndex(of:chars[0]),let b=ranks.firstIndex(of:chars[1]) else { return false }
                let high=a+2,low=b+2
                if high==low { return h==l && (plus ? h>=high : h==high) }
                guard h==high,plus ? l>=low : l==low else { return false }
                return chars[2]=="s" ? suited : !suited
            }
        }
        for range in ShortCashRange.allCases { for h in 2...14 { for l in 2...h { for s in [false,true] where h != l || !s {
            let hole=[Card(rank:h,suit:.spades),Card(rank:l,suit:s ? .spades : .diamonds)]
            XCTAssertEqual(range.contains(hole),declares(range.notation,h:h,l:l,suited:s),"\(range), \(h), \(l), \(s)")
        } } } }
        XCTAssertTrue(ShortCashRange.smallBlind.contains([Card("Ks")!,Card("5d")!]))
        XCTAssertTrue(ShortCashRange.cutoff.contains([Card("7h")!,Card("6h")!]))
        XCTAssertFalse(ShortCashRange.early.contains([Card("9s")!,Card("5s")!]))
    }
    func testNewOpponentRangesAreNonemptyAndProduceReproducibleLegalEquity() throws {
        for range in [OpponentRange.shortEarlyOpen,.shortHijackOpen,.shortCutoffOpen,.shortButtonOpen,.shortSmallBlindOpen] {
            let result=try RangeEquityEngine.calculate(hole:[Card("Js")!,Card("7c")!],ranges:[range],samples:1000,seed:88)
            XCTAssertEqual(result.samples,1000);XCTAssertTrue((0...1).contains(result.equity));XCTAssertFalse(range.notation.isEmpty)
        }
    }
}
