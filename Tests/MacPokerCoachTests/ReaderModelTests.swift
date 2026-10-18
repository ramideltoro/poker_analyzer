import XCTest
import TableRecognition
import PokerCore
@testable import MacPokerCoach

final class ReaderModelTests: XCTestCase {
    @MainActor func testLiveReadingClearsOnStaleAndStopAndRequiresNewConfirmation() {
        let model = AppModel(log:.disabled), now = Date()
        let pair = [DetectedCard(card:Card("Ah")!,bounds:UnitRect(x:0.4,y:0.7,width:0.07,height:0.12)),DetectedCard(card:Card("Kd")!,bounds:UnitRect(x:0.48,y:0.7,width:0.07,height:0.12))]
        let scan = CardScan(cards:pair,timestamp:now)
        model.acceptScan(scan,now:now); XCTAssertNil(model.hand)
        model.acceptScan(scan,now:now); XCTAssertEqual(model.hand?.hole.count,2)
        model.expire(now:now.addingTimeInterval(3)); XCTAssertNil(model.hand)
        model.acceptScan(scan,now:now); XCTAssertNil(model.hand)
        model.acceptScan(scan,now:now); XCTAssertNotNil(model.hand)
        model.clear("Stopped"); XCTAssertNil(model.hand)
    }
    @MainActor func testNoDetectionsAndAmbiguityRemainExplicit() {
        let model = AppModel(log:.disabled)
        model.acceptScan(CardScan(cards:[]))
        XCTAssertEqual(model.faces,0); XCTAssertEqual(model.scanned,1)
        XCTAssertTrue(model.status.contains("Screen received")); XCTAssertNil(model.hand)
    }
    @MainActor func testOutdatedScanCannotRepopulateScreen() {
        let model = AppModel(log:.disabled), now = Date()
        model.acceptScan(CardScan(cards:[],timestamp:now.addingTimeInterval(-10)),now:now)
        XCTAssertNil(model.hand); XCTAssertEqual(model.scanned,0)
    }
    @MainActor func testKeepsReadingSuccessiveHandsAcrossFoldsAndEmptyFrames() {
        let model = AppModel(log:.disabled)
        let hands = [["Ah","Kd"],["Qc","5c"],["9h","Ts"],["7d","2c"]]
        for turn in 0..<20 {
            let codes = hands[turn%hands.count]
            let pair = codes.enumerated().map { index,code in
                DetectedCard(card:Card(code)!,bounds:UnitRect(x:0.4+Double(index)*0.08,y:0.7,width:0.07,height:0.12))
            }
            model.acceptScan(CardScan(cards:pair)); XCTAssertNil(model.hand)
            model.acceptScan(CardScan(cards:pair)); XCTAssertEqual(model.hand?.hole.map { $0.card.code },codes)
            // A fold/empty table is a new observation, not a stop command.
            for _ in 0..<4 { model.acceptScan(CardScan(cards:[])); XCTAssertNil(model.hand) }
            XCTAssertTrue(model.status.contains("Scanning continuously"))
        }
        XCTAssertEqual(model.scanned,120)
    }
    @MainActor func testStaleReadingClearsCardsButRetainsSeatForNextHand() {
        let model = AppModel(log:.disabled), now = Date()
        let pair = ["Ah","Kd"].enumerated().map { i,code in
            DetectedCard(card:Card(code)!,bounds:UnitRect(x:0.4+Double(i)*0.08,y:0.7,width:0.07,height:0.12))
        }
        model.acceptScan(CardScan(cards:pair,timestamp:now),now:now)
        model.acceptScan(CardScan(cards:pair,timestamp:now),now:now)
        model.expire(now:now.addingTimeInterval(3)); XCTAssertNil(model.hand)
        let next = now.addingTimeInterval(4)
        model.acceptScan(CardScan(cards:pair,timestamp:next),now:next); XCTAssertNil(model.hand)
        model.acceptScan(CardScan(cards:pair,timestamp:next),now:next); XCTAssertNotNil(model.hand)
    }
}
