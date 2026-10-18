import XCTest
import AppKit
import PokerCore
@testable import TableRecognition

final class TableReadingTests: XCTestCase {
    func testStrictMoneyParserRejectsGuessedAndPartialOCR() {
        for (text,cents) in [("$0.10",10),(" $10 ",1000),("$2.75",275),("$0",0),("$999999.99",99_999_999)] { XCTAssertEqual(TableMoney.cents(text),cents) }
        for text in ["$O.10","$3.58R","$1,000.00","$2.7","$2.750","2.75","-$2.75","$-2.75","$2 $3","NaN","$1000000.00"] { XCTAssertNil(TableMoney.cents(text),text) }
    }
    func snapshot() -> TableObservation {
        TableObservation(potCents:300,callCents:100,seats:[
            TableSeat(id:1,bounds:UnitRect(x:0.4,y:0.3,width:0.2,height:0.05),isHero:false,stackCents:1000,activity:.active),
            TableSeat(id:2,bounds:UnitRect(x:0.4,y:0.8,width:0.2,height:0.05),isHero:true,stackCents:2000,activity:.active)])
    }
    func testChangedMoneyActivityOrMissingFrameInvalidatesConfirmation() {
        var reader = TableReadingStabilizer(), t = snapshot()
        XCTAssertNil(reader.accept(t)); XCTAssertNotNil(reader.accept(t))
        t.potCents = 400; XCTAssertNil(reader.accept(t)); XCTAssertNotNil(reader.accept(t))
        t.seats[0].stackCents = 900; XCTAssertNil(reader.accept(t)); XCTAssertNotNil(reader.accept(t))
        t.seats[0].activity = .folded; XCTAssertNil(reader.accept(t)); XCTAssertNotNil(reader.accept(t))
        XCTAssertNil(reader.accept(nil)); XCTAssertNil(reader.accept(t)); XCTAssertNotNil(reader.accept(t))
        reader.reset(); XCTAssertNil(reader.accept(t))
    }
    func testMissingStacksUnknownActivityAndSidePotsAreIncomplete() {
        let good = snapshot(); XCTAssertNil(good.incompleteReason)
        var t = good; t.sidePots = true; XCTAssertNotNil(t.incompleteReason)
        t = good; t.seats[0].stackCents = nil; XCTAssertNotNil(t.incompleteReason)
        t = good; t.seats[0].activity = .unknown; XCTAssertNotNil(t.incompleteReason)
        t = good; t.callCents = nil; XCTAssertNotNil(t.incompleteReason)
        t = good; t.seats[1].stackCents = 0; XCTAssertNotNil(t.incompleteReason)
    }
    func testSuppliedTableCropsReadMoneyAndAllOccupiedStacks() throws {
        for (name,pot,stacks,hero) in [("table-diamonds",53,[275,1000,1072,1076],275),("table-flop",19,[290,358,394,542,1000,1086],290)] {
            let url = try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"png",subdirectory:"Fixtures"))
            let image = try XCTUnwrap(NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
            let cards = try AutomaticCardDetector().scan(image).cards
            let table = try XCTUnwrap(TableStateDetector().scan(image,cards:cards))
            XCTAssertEqual(table.potCents,pot,"\(name) \(table)"); XCTAssertEqual(table.callCents,0)
            XCTAssertEqual(table.seats.compactMap(\.stackCents).sorted(),stacks,"\(name) \(table)")
            XCTAssertEqual(table.hero?.stackCents,hero); XCTAssertEqual(table.activeOpponents.count,1,"\(name) \(table)")
            XCTAssertNil(table.incompleteReason,"\(name): \(table.incompleteReason ?? "")")
            XCTAssertTrue(table.seats.allSatisfy { $0.betCents == nil },"Stack labels must not become current bets")
            if name == "table-diamonds" {
                XCTAssertEqual(table.seats.filter { $0.activity == .sittingOut }.count,1)
                XCTAssertEqual(table.seats.filter { $0.activity == .waiting }.count,1)
            }
            let opponent = try XCTUnwrap(table.activeOpponents.first)
            let blocked = try XCTUnwrap(TableStateDetector().scan(image,cards:cards,excluding:[opponent.bounds]))
            XCTAssertNotNil(blocked.incompleteReason)
        }
    }
    func testPrivateFullScreenshotsAtCaptureSizesWhenProvided() throws {
        guard let diamond = ProcessInfo.processInfo.environment["CARD_READER_DIAMOND_FIXTURE"], let flop = ProcessInfo.processInfo.environment["CARD_READER_FLOP_FIXTURE"] else { throw XCTSkip("Provide private full images for capture-size replay.") }
        for (path,pot,stacks,hero) in [(diamond,53,[275,1000,1072,1076],275),(flop,19,[290,358,394,542,1000,1086],290)] {
            let image = try XCTUnwrap(NSImage(contentsOfFile:path)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
            for (width,height) in [(3840,2160),(2560,1440),(1920,1080)] {
                let c = try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
                c.interpolationQuality = .high; c.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
                let resized = try XCTUnwrap(c.makeImage()), cards = try AutomaticCardDetector().scan(resized).cards
                let table = try XCTUnwrap(TableStateDetector().scan(resized,cards:cards))
                XCTAssertEqual(table.potCents,pot,"\(width) \(table)"); XCTAssertEqual(table.callCents,0)
                XCTAssertEqual(table.seats.compactMap(\.stackCents).sorted(),stacks,"\(width) \(table)")
                XCTAssertEqual(table.hero?.stackCents,hero); XCTAssertEqual(table.activeOpponents.count,1)
                XCTAssertNil(table.incompleteReason,"\(width) \(table)")
            }
        }
    }
}

extension TableReadingTests {
    func practiceTable(seatCount: Int,sidePot: Bool = false) -> (CGImage,[DetectedCard]) {
        let scene = NSImage(size:NSSize(width:1200,height:1000))
        scene.lockFocus()
        NSColor(calibratedRed:0.04,green:0.19,blue:0.19,alpha:1).setFill(); NSRect(x:0,y:0,width:1200,height:1000).fill()
        func box(_ x: CGFloat,_ top: CGFloat,_ width: CGFloat,_ height: CGFloat,_ color: NSColor) {
            color.setFill(); NSBezierPath(roundedRect:NSRect(x:x,y:1000-top-height,width:width,height:height),xRadius:12,yRadius:12).fill()
        }
        func text(_ value: String,_ x: CGFloat,_ top: CGFloat,_ size: CGFloat,_ color: NSColor = .white) {
            (value as NSString).draw(at:NSPoint(x:x,y:1000-top-size*1.25),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:.bold),.foregroundColor:color])
        }
        let ring: [(CGFloat,CGFloat)] = seatCount == 9 ? [(400,190),(800,190),(1050,360),(1050,620),(850,790),(350,790),(150,620),(150,360)] : [(600,190),(1050,360),(1050,620),(150,620),(150,360)]
        for (i,point) in (ring+[(600,860)]).enumerated() {
            let (x,y) = point, hero = i == ring.count, left = x-108, top = y-26
            if hero {
                box(526,735,70,104,.white); box(603,735,70,104,.white)
                text("A",532,740,23,.black); text("K",610,740,23,.black)
            } else if i == 0 {
                for dx: CGFloat in [0.21,0.49] {
                    let bx = left+216*dx, by = top-72
                    box(bx,by,57,80,.white); box(bx+2,by+2,53,76,NSColor(calibratedWhite:0.17,alpha:1))
                    text("B",bx+17,by+25,27,NSColor(calibratedRed:0.75,green:0.06,blue:0.1,alpha:1))
                }
            }
            box(left,top,216,52,NSColor(calibratedRed:0.4,green:0.54,blue:0.55,alpha:1))
            text(hero ? "$9.00" : String(format:"$%d.00",i+10),left+78,top+9,23,.black)
        }
        text("Total pot: $3.00",510,350,22)
        if sidePot { text("Main pot: $2.00",510,383,22); text("Side pot: $1.00",510,416,22) }
        box(520,920,190,78,NSColor(calibratedWhite:0.04,alpha:1)); text("CALL",584,929,21); text("$0.75",584,958,21)
        box(740,920,190,78,NSColor(calibratedWhite:0.04,alpha:1)); text("RAISE TO",775,929,21); text("$1.50",801,958,21)
        text("$1.25",ring[0].0,ring[0].1+85,20); text("$0.50",586,690,20)
        scene.unlockFocus()
        let image = scene.cgImage(forProposedRect:nil,context:nil,hints:nil)!
        let cards = ["Ah","Kd"].enumerated().map { DetectedCard(card:Card($0.element)!,bounds:UnitRect(x:Double(526+$0.offset*77)/1200,y:0.735,width:70.0/1200,height:0.104)) }
        return (image,cards)
    }
    func testPracticeSixAndNineSeatLayoutsReadCallAndCurrentBets() throws {
        for count in [6,9] {
            let (image,cards) = practiceTable(seatCount:count)
            let table = try XCTUnwrap(TableStateDetector().scan(image,cards:cards))
            XCTAssertEqual(table.seats.count,count,"\(table)")
            XCTAssertEqual(table.potCents,300); XCTAssertEqual(table.callCents,75,"\(table)")
            XCTAssertEqual(table.hero?.stackCents,900); XCTAssertEqual(table.hero?.betCents,50,"\(table)")
            XCTAssertEqual(table.activeOpponents.count,1,"\(table)")
            XCTAssertEqual(table.activeOpponents.first?.betCents,125)
            XCTAssertNil(table.incompleteReason,"\(table)")
        }
    }
    func testPracticeSidePotIsReadButMarkedIncomplete() throws {
        let (image,cards) = practiceTable(seatCount:6,sidePot:true)
        let table = try XCTUnwrap(TableStateDetector().scan(image,cards:cards))
        XCTAssertTrue(table.sidePots); XCTAssertNotNil(table.incompleteReason)
    }
}
