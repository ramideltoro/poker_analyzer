import XCTest
import PokerCore
@testable import TableRecognition

final class ActionControlTests: XCTestCase {
    func text(_ value: String,x: Double = 0.4,y: Double = 0.8,confidence: Float = 0.99) -> TableStateDetector.Text {
        TableStateDetector.Text(value:value,confidence:confidence,bounds:UnitRect(x:x,y:y,width:0.08,height:0.025))
    }
    func testMergedMultilineAndNoSpaceButtonsReadExactAmounts() {
        let detector = TableStateDetector()
        for label in ["CALL\n$0.10","CALL$0.10"," call \t $0.10 ","CALL\n\n$0.10"] {
            let result = detector.readActions([text(label)],width:0.07,height:0.12)
            XCTAssertEqual(result.1,10,label); XCTAssertTrue(result.0.canCall); XCTAssertFalse(result.0.canCheck)
        }
        let result = detector.readActions([text("CALL",x:0.3),text("$0.75",x:0.3,y:0.84),text("RAISE\nTO\n$1.50",x:0.6)],width:0.07,height:0.12)
        XCTAssertEqual(result.1,75); XCTAssertEqual(result.0.raiseToCents,150)
        XCTAssertTrue(result.0.canRaise)
        XCTAssertEqual(detector.readActions([text(" CHECK ")],width:0.07,height:0.12).1,0)
    }
    func testAmbiguousMalformedLowConfidenceAndHistoryTextCannotSetThePrice() {
        let detector = TableStateDetector()
        for labels in [
            [text("CALL $0.10"),text("CALL $0.20",x:0.6)],
            [text("CHECK"),text("CALL $0.10",x:0.6)],
            [text("CALL $O.10")], [text("CALL $0.10",confidence:0.94)],
            [text("CHECK$1.00")], [text("Player 1 calls $0.10")],
            [text("CALL"),text("$0.10",y:0.84),text("$0.20",y:0.85)]
        ] { XCTAssertNil(detector.readActions(labels,width:0.07,height:0.12).1) }
    }
    func testActionConfirmationIgnoresUnrelatedValuesButNotPriceButtonsOrHeroChanges() {
        let base = TableObservation(potCents:300,callCents:0,seats:[
            TableSeat(id:1,bounds:UnitRect(x:0.4,y:0.3,width:0.2,height:0.05),isHero:false,stackCents:1000,activity:.active),
            TableSeat(id:2,bounds:UnitRect(x:0.4,y:0.8,width:0.2,height:0.05),isHero:true,stackCents:2000,activity:.active)],controls:TableControls(canCheck:true,canRaise:true,raiseToCents:100))
        var changed = base; changed.potCents = nil; changed.seats[0].stackCents = nil; changed.controls?.raiseToCents = 999
        XCTAssertTrue(base.agreesForActions(with:changed))
        changed = base; changed.callCents = 100; XCTAssertFalse(base.agreesForActions(with:changed))
        changed = base; changed.controls?.canCheck = false; XCTAssertFalse(base.agreesForActions(with:changed))
        changed = base; changed.seats[1].activity = .folded; XCTAssertFalse(base.agreesForActions(with:changed))
        changed = base; changed.seats[1].bounds.y = 0.4; XCTAssertFalse(base.agreesForActions(with:changed))
        changed = base; changed.controls = nil; XCTAssertFalse(base.agreesForActions(with:changed))
    }
}
