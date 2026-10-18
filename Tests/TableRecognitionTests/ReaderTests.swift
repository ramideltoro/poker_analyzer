import XCTest
import AppKit
import TableRecognition
import PokerCore

func cardFixture(_ cards: [(String,CGFloat,CGFloat)],width: CGFloat = 1200,height: CGFloat = 900,size: CGFloat = 100,font: String = "Arial") -> CGImage {
    let image = NSImage(size:NSSize(width:width,height:height))
    image.lockFocus()
    NSColor(calibratedRed:0.03,green:0.22,blue:0.15,alpha:1).setFill(); NSRect(x:0,y:0,width:width,height:height).fill()
    for (code,x,top) in cards {
        let card = Card(code)!, h = size*1.48, y = height-top-h
        let rect = NSRect(x:x,y:y,width:size,height:h)
        NSColor(calibratedWhite:0.97,alpha:1).setFill(); NSBezierPath(roundedRect:rect,xRadius:6,yRadius:6).fill()
        let color: NSColor = card.suit.red ? .systemRed : .black
        let attributes: [NSAttributedString.Key:Any] = [.font:NSFont(name:font,size:size*0.31) ?? NSFont.systemFont(ofSize:size*0.31),.foregroundColor:color]
        (String(card.code.dropLast()).replacingOccurrences(of:"T",with:"10") as NSString).draw(at:NSPoint(x:x+size*0.09,y:height-top-size*0.42),withAttributes:attributes)
        (card.suit.symbol as NSString).draw(at:NSPoint(x:x+size*0.08,y:height-top-size*0.77),withAttributes:[.font:NSFont(name:font,size:size*0.29) ?? NSFont.systemFont(ofSize:size*0.29),.foregroundColor:color])
        (card.suit.symbol as NSString).draw(at:NSPoint(x:x+size*0.37,y:height-top-size*1.2),withAttributes:[.font:NSFont(name:font,size:size*0.55) ?? NSFont.systemFont(ofSize:size*0.55),.foregroundColor:color])
    }
    image.unlockFocus()
    return image.cgImage(forProposedRect:nil,context:nil,hints:nil)!
}

final class ReaderTests: XCTestCase {
    func face(_ code: String,x: Double,y: Double) -> DetectedCard { DetectedCard(card:Card(code)!,bounds:UnitRect(x:x,y:y,width:0.07,height:0.12)) }
    func testSuitGlyphShapesAcrossFonts() throws {
        for font in ["Arial","Georgia","Times New Roman"] {
            for suit in Suit.allCases {
                let match = try XCTUnwrap(SuitRecognizer.match(SuitRecognizer.render(suit,fontName:font)))
                XCTAssertEqual(match.suit,suit,"\(font)")
                XCTAssertGreaterThanOrEqual(match.score,0.82)
                XCTAssertGreaterThanOrEqual(match.margin,0.035)
            }
        }
    }
    func testAutomaticPixelDetectionWithNoCoordinatesOrCardCodes() throws {
        let expected = ["Ah","Kd","Qh","Js","2c"]
        let image = cardFixture([("Ah",500,640),("Kd",610,640),("Qh",430,330),("Js",540,330),("2c",650,330)])
        let scan = try AutomaticCardDetector().scan(image)
        XCTAssertEqual(Set(scan.cards.map { $0.card.code }),Set(expected),"\(scan.cards), rectangles=\(scan.rectangles)")
        let grouped = CardGrouping.select(scan.cards)
        XCTAssertEqual(grouped.hole.map { $0.card.code },["Ah","Kd"])
        XCTAssertEqual(grouped.board.map { $0.card.code },["Qh","Js","2c"])
    }
    func testDetectorRejectsScreenWithoutCardsAndExcludesOwnWindow() throws {
        let detector = AutomaticCardDetector()
        XCTAssertTrue(try detector.scan(cardFixture([])).cards.isEmpty)
        let image = cardFixture([("Ah",500,640),("Kd",610,640)])
        let scan = try detector.scan(image,excluding:[UnitRect(x:0.3,y:0.6,width:0.4,height:0.4)])
        XCTAssertTrue(scan.cards.isEmpty)
    }
    func testAutomaticDetectionOfAllRanksAndSuits() throws {
        let detector = AutomaticCardDetector()
        for rank in "23456789TJQKA" {
            let codes = Suit.allCases.map { String(rank)+$0.rawValue }
            let image = cardFixture(codes.enumerated().map { ($0.element,CGFloat(250+$0.offset*120),CGFloat(350)) })
            let scan = try detector.scan(image)
            XCTAssertEqual(Set(scan.cards.map { $0.card.code }),Set(codes),"Rank \(rank): \(scan.cards)")
        }
    }
    func testCardsMoveAndChangeSizeWithoutCalibration() throws {
        let detector = AutomaticCardDetector()
        for (size,x,top) in [(CGFloat(72),CGFloat(100),CGFloat(600)),(CGFloat(125),CGFloat(780),CGFloat(420))] {
            let image = cardFixture([("9c",x,top),("Td",x+size+12,top)],size:size)
            let scan = try detector.scan(image)
            XCTAssertEqual(Set(scan.cards.map { $0.card.code }),Set(["9c","Td"]),"size=\(size), rectangles=\(scan.rectangles), faces=\(scan.cards)")
        }
    }
    func testStableTwoFramePairAndImmediateClearingWhenCardsDisappear() {
        let pair = [face("Ah",x:0.4,y:0.7),face("Kd",x:0.48,y:0.7)]
        var stabilizer = ReadingStabilizer()
        XCTAssertNil(stabilizer.accept(CardScan(cards:pair)).0)
        XCTAssertEqual(stabilizer.accept(CardScan(cards:pair)).0?.hole.map { $0.card.code },["Ah","Kd"])
        XCTAssertNil(stabilizer.accept(CardScan(cards:[])).0)
        XCTAssertNil(stabilizer.accept(CardScan(cards:pair)).0)
        stabilizer.reset(); XCTAssertNil(stabilizer.accept(CardScan(cards:pair)).0)
    }
    func testMultiplePairsAndDuplicateFacesDoNotGuessHero() {
        let pair = [face("Ah",x:0.4,y:0.7),face("Kd",x:0.48,y:0.7)]
        XCTAssertNotNil(CardGrouping.select(pair+[face("Qs",x:0.3,y:0.3),face("Jh",x:0.38,y:0.3)]).issue)
        XCTAssertNotNil(CardGrouping.select(pair+[face("Ah",x:0.3,y:0.3)]).issue)
    }
    func testBoardMustBeAboveAssumedHeroPair() {
        let cards = [face("Ah",x:0.4,y:0.2),face("Kd",x:0.48,y:0.2),face("Qs",x:0.3,y:0.6),face("Jh",x:0.38,y:0.6),face("2c",x:0.46,y:0.6)]
        XCTAssertNotNil(CardGrouping.select(cards).issue)
    }
    func testMiniaturePreviewDuplicatesAndHistoryBoardDoNotBecomeTheLiveHand() {
        let pair = [face("Qc",x:0.4,y:0.7),face("5c",x:0.48,y:0.7)]
        let miniatureCodes = ["Qc","5c","Ac","Ks","Th","8h","6s"]
        let miniatures = miniatureCodes.enumerated().map { index,code in
            DetectedCard(card:Card(code)!,bounds:UnitRect(x:0.68+Double(index)*0.025,y:0.1,width:0.02,height:0.04))
        }
        let selected = CardGrouping.select(pair+miniatures)
        XCTAssertNil(selected.issue)
        XCTAssertEqual(selected.hole.map { $0.card.code },["Qc","5c"])
        XCTAssertTrue(selected.board.isEmpty)
    }
    func testConfirmedSeatSurvivesFoldBoardAnimationsAndDistractingPairs() {
        var reader = ReadingStabilizer()
        let pair = [face("Ah",x:0.4,y:0.7),face("Kd",x:0.48,y:0.7)]
        let board = [face("Qs",x:0.35,y:0.35),face("Jh",x:0.43,y:0.35),face("2c",x:0.51,y:0.35)]
        XCTAssertNil(reader.accept(CardScan(cards:pair+board)).0)
        XCTAssertNotNil(reader.accept(CardScan(cards:pair+board)).0)
        XCTAssertEqual(reader.searchRegions.count,5)
        XCTAssertNil(reader.accept(CardScan(cards:board)).0)
        XCTAssertNil(reader.accept(CardScan(cards:[])).0)
        XCTAssertEqual(reader.searchRegions.count,5)
        let next = [face("9c",x:0.4,y:0.7),face("Td",x:0.48,y:0.7)]
        // A sidebar image duplicates the new hole cards at the same scale.
        let sidebar = [face("9c",x:0.83,y:0.4),face("Td",x:0.91,y:0.4)]
        XCTAssertNil(reader.accept(CardScan(cards:next+sidebar)).0)
        let hand = reader.accept(CardScan(cards:next+sidebar)).0
        XCTAssertEqual(hand?.hole.map { $0.card.code },["9c","Td"])
        XCTAssertEqual(hand?.board.count,0)
        XCTAssertEqual(reader.searchRegions.count,2)
        reader.reset(keepLayout:true); XCTAssertEqual(reader.searchRegions.count,2)
        reader.reset(); XCTAssertTrue(reader.searchRegions.isEmpty)
    }
    func testHintsReadNewValuesAndBlankFramesNeverReuseOldCards() throws {
        let detector = AutomaticCardDetector()
        let first = try detector.scan(cardFixture([("Ah",500,640),("Kd",610,640)]))
        let regions = first.cards.map(\.bounds)
        XCTAssertEqual(regions.count,2)
        let changed = try detector.scan(cardFixture([("9c",500,640),("Td",610,640)]),searchRegions:regions)
        XCTAssertEqual(Set(changed.cards.map { $0.card.code }),Set(["9c","Td"]))
        XCTAssertEqual(changed.diagnostics.hintCandidates,2)
        XCTAssertTrue(try detector.scan(cardFixture([]),searchRegions:regions).cards.isEmpty)
        XCTAssertTrue(try detector.scan(cardFixture([("9c",500,640),("Td",610,640)]),excluding:[UnitRect(x:0.3,y:0.6,width:0.4,height:0.4)],searchRegions:regions).cards.isEmpty)
    }
    func testExcludedWindowGeometryOnSecondaryDisplay() {
        let rect = CaptureGeometry.excludedRegion(window:CGRect(x:2000,y:100,width:500,height:400),display:CGRect(x:1920,y:0,width:1920,height:1080),mainScreenHeight:1080)
        XCTAssertEqual(rect?.x,80.0/1920)
        XCTAssertEqual(rect?.y,580.0/1080)
        XCTAssertNil(CaptureGeometry.excludedRegion(window:CGRect(x:100,y:100,width:500,height:400),display:CGRect(x:1920,y:0,width:1920,height:1080),mainScreenHeight:1080))
    }
}
