import XCTest
@testable import TableRecognition

final class SeatActionTests: XCTestCase {
    func testOnlyExplicitLabelsAreParsed() {
        for (text,action) in [("Fold",SeatAction.fold),(" FOLDED ",.fold),("CHECKED",.check),("Calls $1.00",.call),("BET $0.25",.bet),("Raise to $0.30",.raise)] { XCTAssertEqual(SeatAction.parse(text),action) }
        for text in ["SITTING OUT","NEW PLAYER","ALL IN","SMALL BLIND","CHECK / FOLD","$3.00","Player 3 checks","RAISE TO POT","CALL $O.10","Fold next hand"] { XCTAssertNil(SeatAction.parse(text),text) }
    }
    func testSeatLabelIsRecognizedButAvailableControlsDoNotCountAsActions() throws {
        let fixture = TableReadingTests(), detector = TableStateDetector()
        let (image,cards) = fixture.practiceTable(seatCount:6,seatAction:"CHECK")
        let table = try XCTUnwrap(detector.scan(image,cards:cards))
        XCTAssertEqual(table.seats.filter { $0.action == .check }.count,1)
        XCTAssertNil(table.hero?.action,"The Call / Raise buttons are legal controls, not completed actions")
        XCTAssertEqual(table.controls?.canCall,true)
        XCTAssertEqual(table.controls?.canRaise,true)
        XCTAssertEqual(table.controls?.raiseToCents,150)
        XCTAssertEqual(table.seats.filter { $0.action == .raise || $0.action == .call }.count,0)
    }
}
