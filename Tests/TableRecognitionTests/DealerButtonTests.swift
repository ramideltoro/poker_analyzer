import XCTest
import AppKit
import PokerCore
@testable import TableRecognition

final class DealerButtonTests: XCTestCase {
    func testSuppliedTableImageFindsTheActualDealerChipAtMultipleScales() throws {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"table-flop",withExtension:"png",subdirectory:"Fixtures"))
        let original=try XCTUnwrap(NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        for factor in [0.65,1.0,1.25] {
            let w=Int(Double(original.width)*factor),h=Int(Double(original.height)*factor)
            let c=try XCTUnwrap(CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            c.draw(original,in:CGRect(x:0,y:0,width:w,height:h))
            let image=try XCTUnwrap(c.makeImage()),cards=try AutomaticCardDetector().scan(image).cards
            let t=try XCTUnwrap(TableStateDetector().scan(image,cards:cards))
            let dealer=try XCTUnwrap(t.seats.first { $0.id==t.dealerSeatID },"\(factor): \(t)")
            XCTAssertGreaterThan(dealer.bounds.rect.midX,0.75); XCTAssertLessThan(dealer.bounds.rect.midY,0.4)
            XCTAssertFalse(dealer.isHero)
            XCTAssertEqual(dealer.activity,.folded,"Dealer does not have to remain active")
        }
    }
    func testMissingCoveredDuplicateAndNonDealerChipsAreRejected() throws {
        let (base,cards)=TableReadingTests().practiceTable(seatCount:6)
        let t=try XCTUnwrap(TableStateDetector().scan(base,cards:cards))
        XCTAssertNil(t.dealerSeatID)
        let seat=try XCTUnwrap(t.hero),p=seat.bounds
        let box=UnitRect(x:p.x-p.height*0.9,y:p.y+p.height*0.1,width:p.height*0.8*Double(base.height)/Double(base.width),height:p.height*0.8)
        func draw(glyph: String,color: NSColor,duplicate: Bool=false) throws -> CGImage {
            let scene=NSImage(size:NSSize(width:base.width,height:base.height)); scene.lockFocus()
            NSImage(cgImage:base,size:scene.size).draw(in:NSRect(origin:.zero,size:scene.size))
            func chip(_ b: UnitRect) {
                let rect=NSRect(x:b.x*scene.size.width,y:(1-b.y-b.height)*scene.size.height,width:b.width*scene.size.width,height:b.height*scene.size.height)
                NSColor.white.setFill(); NSBezierPath(ovalIn:rect).fill()
                let font=NSFont.systemFont(ofSize:rect.height*0.65,weight:.bold)
                (glyph as NSString).draw(at:NSPoint(x:rect.midX-rect.width*0.23,y:rect.midY-rect.height*0.40),withAttributes:[.font:font,.foregroundColor:color])
            }
            chip(box)
            if duplicate { var b=box; b.x=p.rect.maxX+0.01; chip(b) }
            scene.unlockFocus(); return try XCTUnwrap(scene.cgImage(forProposedRect:nil,context:nil,hints:nil))
        }
        let image=try draw(glyph:"B",color:.systemRed)
        XCTAssertEqual(DealerButtonDetector.seatID(image,seats:t.seats,excluding:[]),seat.id)
        XCTAssertNil(DealerButtonDetector.seatID(image,seats:t.seats,excluding:[box]))
        XCTAssertNil(DealerButtonDetector.seatID(try draw(glyph:"B",color:.systemRed,duplicate:true),seats:t.seats,excluding:[]))
        XCTAssertNil(DealerButtonDetector.seatID(try draw(glyph:"$",color:.black),seats:t.seats,excluding:[]))
    }
    func testStakesParserRequiresExactStandardCashHeader() {
        XCTAssertEqual(TableStateDetector.bigBlind("$0.05/$0.10 No Limit Hold'em"),10)
        XCTAssertEqual(TableStateDetector.bigBlind("$1/$2 No Limit Hold’em"),200)
        for text in ["$0.05/$O.10 No Limit Hold'em","$0.05/$0.20 No Limit Hold'em","Total pot: $0.10","$1/$2 Pot Limit Omaha","$1/$2 No Limit Hold'em Ante $1","$1/$2"] { XCTAssertNil(TableStateDetector.bigBlind(text),text) }
    }
    func testSuppliedFullScreenshotReadsDealerAndBlindTogether() throws {
        guard let path=ProcessInfo.processInfo.environment["CARD_READER_FLOP_FIXTURE"] else { throw XCTSkip("Provide the user-supplied full screenshot for header replay.") }
        let image=try XCTUnwrap(NSImage(contentsOfFile:path)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let cards=try AutomaticCardDetector().scan(image).cards
        let t=try XCTUnwrap(TableStateDetector().scan(image,cards:cards))
        XCTAssertNotNil(t.dealerSeatID); XCTAssertEqual(t.bigBlindCents,10)
    }
}
