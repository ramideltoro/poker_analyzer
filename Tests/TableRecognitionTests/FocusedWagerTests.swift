import XCTest
import AppKit
import PokerCore
@testable import TableRecognition

final class FocusedWagerTests:XCTestCase {
    func testChipPrefixParserDoesNotGuessDigitsOrAcceptPartialMoney() {
        for value in ["$0.50","S $0.50","S$0.50","$ $0.50"] { XCTAssertEqual(TableStateDetector.chipAmount(value),50,value) }
        for value in ["S $O.50","$0.5","$0.50 $0.10","$2 $3","$9.00 CALL","pot $0.50","S 0.50","$-0.50"] { XCTAssertNil(TableStateDetector.chipAmount(value),value) }
    }
    func testFocusedCurrencyTokenRecoversHeroChipWithoutChangingStackOrCall() throws {
        let (base,cards)=TableReadingTests().practiceTable(seatCount:6)
        let scene=NSImage(size:NSSize(width:1200,height:1000));scene.lockFocus()
        NSImage(cgImage:base,size:scene.size).draw(in:NSRect(origin:.zero,size:scene.size))
        NSColor(calibratedRed:0.04,green:0.19,blue:0.19,alpha:1).setFill();NSRect(x:565,y:1000-725,width:140,height:50).fill()
        ("S $0.50" as NSString).draw(at:NSPoint(x:570,y:1000-690-25),withAttributes:[.font:NSFont.systemFont(ofSize:20,weight:.bold),.foregroundColor:NSColor.white])
        scene.unlockFocus()
        let image=try XCTUnwrap(scene.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let t=try XCTUnwrap(TableStateDetector().scan(image,cards:cards))
        XCTAssertEqual(t.hero?.betCents,50);XCTAssertEqual(t.hero?.stackCents,900);XCTAssertEqual(t.callCents,75)
        XCTAssertEqual(t.activeOpponents.first?.betCents,125);XCTAssertNil(t.incompleteReason)
        let excluded=UnitRect(x:0.46,y:0.67,width:0.14,height:0.055)
        let blocked=try XCTUnwrap(TableStateDetector().scan(image,cards:cards,excluding:[excluded]))
        XCTAssertNil(blocked.hero?.betCents);XCTAssertNotNil(blocked.incompleteReason)
    }
    func testBlankWagerRegionsRemainUnknownRatherThanZero() throws {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"table-flop",withExtension:"png",subdirectory:"Fixtures"))
        let image=try XCTUnwrap(NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let cards=try AutomaticCardDetector().scan(image).cards,t=try XCTUnwrap(TableStateDetector().scan(image,cards:cards))
        XCTAssertTrue(t.seats.allSatisfy { $0.betCents==nil })
    }
    func testTwoFocusedAmountsCannotBeChosenAsOneHeroWager() throws {
        let (base,cards)=TableReadingTests().practiceTable(seatCount:6)
        let scene=NSImage(size:NSSize(width:1200,height:1000));scene.lockFocus()
        NSImage(cgImage:base,size:scene.size).draw(in:NSRect(origin:.zero,size:scene.size))
        NSColor(calibratedRed:0.04,green:0.19,blue:0.19,alpha:1).setFill();NSRect(x:540,y:267,width:170,height:70).fill()
        for (text,top) in [("S $0.50",675),("$0.60",704)] {
            (text as NSString).draw(at:NSPoint(x:550,y:1000-top-25),withAttributes:[.font:NSFont.systemFont(ofSize:20,weight:.bold),.foregroundColor:NSColor.white])
        }
        scene.unlockFocus()
        let image=try XCTUnwrap(scene.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let t=try XCTUnwrap(TableStateDetector().scan(image,cards:cards))
        XCTAssertNil(t.hero?.betCents);XCTAssertNotNil(t.incompleteReason)
    }
}
