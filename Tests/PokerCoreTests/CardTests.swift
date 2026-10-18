import XCTest
import PokerCore

final class CardTests: XCTestCase {
    func testCardParsingAndInvalidRanks() throws {
        XCTAssertEqual(Card("10h")?.code,"Th")
        XCTAssertEqual(Card("AS")?.display,"A♠")
        XCTAssertNil(Card("1s")); XCTAssertNil(Card("AhKh"))
        XCTAssertThrowsError(try JSONDecoder().decode(Card.self,from:Data(#"{"rank":99,"suit":"h"}"#.utf8)))
    }
    func testAllHandCategoriesAndWheel() {
        let cases: [(String,String)] = [
            ("Ah Kd 9c 7s 3h","High card"),("Ah Ad 9c 7s 3h","One pair"),
            ("Ah Ad 9c 9s 3h","Two pair"),("Ah Ad Ac 7s 3h","Three of a kind"),
            ("Ah 2d 3c 4s 5h","Straight"),("Ah Jh 9h 7h 3h","Flush"),
            ("Ah Ad Ac 7s 7h","Full house"),("Ah Ad Ac As 3h","Four of a kind"),
            ("Ah Kh Qh Jh Th","Straight flush")]
        for (text,name) in cases { XCTAssertEqual(Evaluator.evaluate(text.split(separator:" ").map { Card(String($0))! }).name,name) }
    }
    func testSevenCardsUseBestFive() {
        let cards = "Ah Ad Ac Ks Kh Kd 2h".split(separator:" ").map { Card(String($0))! }
        XCTAssertEqual(Evaluator.evaluate(cards).name,"Full house")
        XCTAssertGreaterThan(Evaluator.evaluate(cards),Evaluator.evaluate([Card("Kh")!,Card("Kd")!,Card("Kc")!,Card("As")!,Card("Ad")!]))
    }
}
