import XCTest
import AppKit
import PokerCore
@testable import TableRecognition

final class RevealedCardsTests: XCTestCase {
    func testOnlyTwoFacesAboveOneOpponentAreAssociated() {
        let seat = TableSeat(id:1,bounds:UnitRect(x:0.4,y:0.3,width:0.2,height:0.05),isHero:false,stackCents:1000,activity:.active)
        let cards = ["Qc","Qs"].enumerated().map { DetectedCard(card:Card($0.element)!,bounds:UnitRect(x:0.44+Double($0.offset)*0.06,y:0.22,width:0.05,height:0.08)) }
        XCTAssertEqual(RevealedCards.associate(cards:cards,seats:[seat],known:[])[0].map(\.code),["Qc","Qs"])
        XCTAssertTrue(RevealedCards.associate(cards:Array(cards.prefix(1)),seats:[seat],known:[])[0].isEmpty)
        XCTAssertTrue(RevealedCards.associate(cards:cards,seats:[seat],known:[Card("Qc")!])[0].isEmpty)
        var hero = seat; hero.isHero = true
        XCTAssertTrue(RevealedCards.associate(cards:cards,seats:[hero],known:[])[0].isEmpty)
        var new = seat; new.isNewPlayer = true
        XCTAssertTrue(RevealedCards.associate(cards:cards,seats:[new],known:[])[0].isEmpty)
        let duplicateAssignments = RevealedCards.associate(cards:cards,seats:[seat,seat],known:[])
        XCTAssertTrue(duplicateAssignments.allSatisfy(\.isEmpty))
        let thumbnails = cards.map { DetectedCard(card:$0.card,bounds:UnitRect(x:$0.bounds.x,y:0.25,width:0.01,height:0.02)) }
        XCTAssertTrue(RevealedCards.associate(cards:thumbnails,seats:[seat],known:[])[0].isEmpty)
        var uncertain = cards; uncertain[0].rankScore = 0.6
        XCTAssertTrue(RevealedCards.associate(cards:uncertain,seats:[seat],known:[])[0].isEmpty)
    }
}

extension RevealedCardsTests {
    func testSuppliedCardArtworkCanBeReadAtAnOpponentSeatWithoutHeroCards() throws {
        // Recompose only the user-supplied offline fixture, never a live capture.
        let url = try XCTUnwrap(Bundle.module.url(forResource:"table-diamonds",withExtension:"png",subdirectory:"Fixtures"))
        let source = try XCTUnwrap(NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let detector = AutomaticCardDetector(), tableDetector = TableStateDetector()
        let cards = try detector.scan(source).cards, selected = CardGrouping.select(cards)
        let before = try XCTUnwrap(tableDetector.scan(source,cards:cards))
        let target = try XCTUnwrap(before.activeOpponents.first)
        let context = try XCTUnwrap(CGContext(data:nil,width:source.width,height:source.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        func quartz(_ rect: CGRect) -> CGRect { CGRect(x:rect.minX,y:CGFloat(source.height)-rect.maxY,width:rect.width,height:rect.height) }
        context.draw(source,in:CGRect(x:0,y:0,width:source.width,height:source.height))
        let p = target.bounds
        for (i,card) in selected.hole.enumerated() {
            let crop = try XCTUnwrap(source.cropping(to:card.bounds.pixels(source)))
            let rect = CGRect(x:(p.x+p.width*(0.21+Double(i)*0.28))*Double(source.width),y:(p.y-p.height*1.8)*Double(source.height),width:p.width*0.27*Double(source.width),height:p.height*1.8*Double(source.height))
            context.draw(crop,in:quartz(rect))
        }
        context.setFillColor(CGColor(red:0.05,green:0.19,blue:0.19,alpha:1))
        for card in selected.hole { context.fill(quartz(card.bounds.pixels(source).insetBy(dx:-2,dy:-2))) }
        let image = try XCTUnwrap(context.makeImage())
        if let path = ProcessInfo.processInfo.environment["CARD_READER_REVEAL_PREVIEW"] {
            try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path))
        }
        let scan = try detector.scan(image,searchRegions:selected.hole.map(\.bounds))
        let after = try XCTUnwrap(tableDetector.scan(image,cards:scan.cards,heroRegions:selected.hole.map(\.bounds)))
        let shown = try XCTUnwrap(after.seats.first(where:{ abs($0.bounds.x-p.x) < 0.02 && abs($0.bounds.y-p.y) < 0.02 }))
        XCTAssertEqual(Set(shown.revealedCards),Set(selected.hole.map(\.card)))
        XCTAssertEqual(after.hero?.activity,.folded)
    }
}
