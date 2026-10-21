import XCTest
import PokerCore
final class PreflopReferenceTests: XCTestCase {
    func hole(_ name: String) -> [Card] { [Card(String(name.prefix(1))+"s")!,Card(String(name.dropFirst().prefix(1))+(name.hasSuffix("s") ? "s" : "d"))!] }
    func testAll169CategoryReferencesAgreeWithIndependentLocalSampling() throws {
        let reference=try XCTUnwrap(PreflopReference.shared)
        XCTAssertEqual(reference.classes.count,169)
        // Family-wise 95% Hoeffding bound over 169 × 9 comparisons, not 1,521 independent 95% claims.
        let bound=sqrt(log(2*Double(169*9)/0.05)/(2*100000))
        for (i,name) in reference.classes.keys.sorted().enumerated() {
            let entry=reference.classes[name]!, cards=hole(name)
            let sample=try EquityEngine.calculate(hole:cards,board:[],opponents:1,samples:100000,seed:UInt64(20481+i),useCategoryReference:false)
            XCTAssertEqual(sample.method,.monteCarlo); XCTAssertFalse(sample.categoriesExact)
            for j in 0..<9 { XCTAssertLessThanOrEqual(abs(sample.categoryProbabilities[j]-Double(entry.categories[j])/Double(reference.boards)),bound,"\(name) category \(j)") }
        }
    }
    func testNinetyEightSuitedCategoryReferenceAppliesToEverySuitAndAnyRandomOpponentCount() throws {
        for suit in Suit.allCases {
            let result=try EquityEngine.calculate(hole:[Card(rank:9,suit:suit),Card(rank:8,suit:suit)],board:[],opponents:1,samples:100000,seed:81)
            XCTAssertEqual(result.method,.monteCarlo); XCTAssertFalse(result.exact)
            XCTAssertEqual(result.equity,0.508,accuracy:result.samplingBound)
            XCTAssertTrue(result.categoriesExact)
            XCTAssertEqual(result.outcomes!.win+result.outcomes!.tie/2,result.equity,accuracy:1e-12)
            XCTAssertEqual(result.categoryProbabilities,PreflopReference.shared!.classes["98s"]!.categories.map { Double($0)/2_118_760 })
        }
        let multi=try EquityEngine.calculate(hole:hole("98s"),board:[],opponents:3,samples:1000,seed:31)
        XCTAssertEqual(multi.method,.monteCarlo); XCTAssertFalse(multi.exact); XCTAssertTrue(multi.categoriesExact)
    }
    func testExactPostflopEnumerationMatchesSimulationAndDealCounts() throws {
        for (board,count) in [(["2c","7s","Jd"],1_070_190),(["2c","7s","Jd","Th"],45_540)] {
            let exact=try EquityEngine.calculate(hole:hole("98s"),board:board.compactMap(Card.init),opponents:1)
            let sampled=try EquityEngine.calculate(hole:hole("98s"),board:board.compactMap(Card.init),opponents:1,samples:100000,seed:751,exactPostflop:false)
            XCTAssertTrue(exact.exact); XCTAssertEqual(exact.samples,count)
            XCTAssertLessThanOrEqual(abs(sampled.equity-exact.equity),sampled.samplingBound)
            XCTAssertEqual(exact.outcomes!.win+exact.outcomes!.tie+exact.outcomes!.lose,1,accuracy:1e-12)
            XCTAssertEqual(exact.categoryProbabilities.reduce(0,+),1,accuracy:1e-12)
            XCTAssertThrowsError(try EquityEngine.calculate(hole:hole("98s"),board:board.compactMap(Card.init),opponents:1,cancelled:{true}))
        }
    }
    func testEntireNinetyEightSuitedCategoryReferenceAgainstLocalExhaustiveEnumeration() throws {
        let cards=hole("98s"), deck=Suit.allCases.flatMap { suit in (2...14).map { Card(rank:$0,suit:suit) } }.filter { !cards.contains($0) }
        var counts=[Int](repeating:0,count:9)
        for a in 0..<46 { for b in a+1..<47 { for c in b+1..<48 { for d in c+1..<49 { for e in d+1..<50 {
            counts[Evaluator.evaluate(cards+[deck[a],deck[b],deck[c],deck[d],deck[e]]).category]+=1
        } } } } }
        XCTAssertEqual(counts,PreflopReference.shared?.classes["98s"]?.categories)
        XCTAssertEqual(counts.reduce(0,+),2_118_760)
    }
    func testPremiumPairsUseLocalSamplingAndDoNotTrustRejectedExternalMatchups() throws {
        for (name,expected) in [("AA",0.852),("KK",0.824)] {
            let result=try EquityEngine.calculate(hole:hole(name),board:[],opponents:1,seed:7551991)
            XCTAssertFalse(result.exact); XCTAssertEqual(result.method,.monteCarlo)
            XCTAssertEqual(result.samples,1_000_000); XCTAssertEqual(result.equity,expected,accuracy:result.samplingBound)
            XCTAssertEqual(result.samplingBound,sqrt(log(40)/2_000_000),accuracy:1e-12)
        }
    }
}
