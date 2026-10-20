import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

@MainActor final class PlayTrackingTests: XCTestCase {
    let time = Date(timeIntervalSince1970:1_800_000_000)
    func table(stack: Int = 1000,bet: Int? = 10,board: [String] = [],folded: Bool = false,reveal: [String] = []) -> TableObservation {
        TableObservation(potCents:30,callCents:10,seats:[
            TableSeat(id:1,bounds:UnitRect(x:0.4,y:0.2,width:0.15,height:0.05),isHero:false,stackCents:2000,activity:.active,seatNumber:1,revealedCards:reveal.compactMap(Card.init)),
            TableSeat(id:2,bounds:UnitRect(x:0.75,y:0.4,width:0.15,height:0.05),isHero:false,stackCents:2000,activity:.folded,seatNumber:2),
            TableSeat(id:3,bounds:UnitRect(x:0.4,y:0.8,width:0.15,height:0.05),isHero:true,stackCents:stack,betCents:bet,activity:folded ? .folded : .active,seatNumber:3)
        ],boardCards:board.compactMap(Card.init))
    }
    func hand(_ hole: [String] = ["Ah","Kd"],board: [String] = [],review: Bool = false) -> LiveHand {
        var hand = HandAnalysisTests().hand(hole,board:board); hand.isReview = review; return hand
    }
    func feed(_ tracker: PlayTracking,_ table: TableObservation,_ hand: LiveHand?,at offset: Double = 0,frames: Int = 3) {
        for i in 0..<frames { tracker.observe(table:table,hand:hand,time:time.addingTimeInterval(offset+Double(i)*0.1)) }
    }
    func testRevealsContinueAfterFoldAndDoNotDuplicateAcrossFramesOrStreets() {
        let t = PlayTracking(persist:false)
        feed(t,table(),hand())
        let flop = ["2c","7s","Jd"]
        feed(t,table(board:flop,folded:true,reveal:["Qc","Qs"]),hand(board:flop,review:true),at:0.5,frames:10)
        XCTAssertTrue(t.active); XCTAssertEqual(t.opponents.count,2)
        XCTAssertEqual(t.opponents.first?.shown.count,1)
        XCTAssertEqual(t.opponents.first?.shown.first?.cards.map(\.code),["Qc","Qs"])
        XCTAssertTrue(t.archive.hands[0].cardsDisappeared)
        let river = flop+["8h","9d"]
        feed(t,table(board:river,folded:true,reveal:["Qc","Qs"]),hand(board:river,review:true),at:1.6)
        XCTAssertEqual(t.opponents.first?.shown.count,1)
        XCTAssertEqual(t.opponents.first?.shown.first?.board.map(\.code),river)
        XCTAssertEqual(t.archive.hands[0].board,river)
        XCTAssertNil(t.archive.hands[0].netCents)
    }
    func testLeavingSeatWipesOnlyThatProfileEvenWhenSortedIDsChange() {
        let t = PlayTracking(persist:false)
        feed(t,table(reveal:["Qc","Qs"]),hand(),frames:4)
        let remainingID = t.opponents[1].id, leavingID = t.opponents[0].id
        var fewer = table(); fewer.seats.remove(at:0); fewer.seats[0].id = 1; fewer.seats[1].id = 2
        feed(t,fewer,hand(),at:0.5)
        XCTAssertEqual(t.opponents.count,1); XCTAssertEqual(t.opponents.first?.id,remainingID)
        XCTAssertFalse(t.opponents.contains { $0.id == leavingID })
        feed(t,table(),hand(),at:1)
        XCTAssertEqual(t.opponents.count,2)
        XCTAssertTrue(t.opponents.contains { $0.id == remainingID })
        XCTAssertFalse(t.opponents.contains { $0.id == leavingID })
    }
    func testNewPlayerMarkerReplacesOnceAndClearsShownHands() {
        let t = PlayTracking(persist:false)
        feed(t,table(reveal:["Qc","Qs"]),hand(),frames:4)
        let oldID = t.opponents[0].id, otherID = t.opponents[1].id
        var replacement = table(); replacement.seats[0].isNewPlayer = true; replacement.seats[0].activity = .waiting
        feed(t,replacement,hand(),at:0.5,frames:10)
        XCTAssertNotEqual(t.opponents.first(where:{ $0.seatNumber == 1 })?.id,oldID)
        XCTAssertTrue(t.opponents.contains { $0.id == otherID })
        XCTAssertTrue(t.opponents.first(where:{ $0.seatNumber == 1 })?.shown.isEmpty == true)
        let newID = t.opponents.first(where:{ $0.seatNumber == 1 })?.id
        feed(t,replacement,hand(),at:1.6)
        XCTAssertEqual(t.opponents.first(where:{ $0.seatNumber == 1 })?.id,newID)
    }
    func testGapExitAndHeroSeatChangeDoNotCarryAnonymousIdentity() {
        let t = PlayTracking(persist:false)
        feed(t,table(reveal:["Qc","Qs"]),hand(),frames:4)
        let id = t.opponents[0].id
        t.observe(table:nil,hand:nil,time:time.addingTimeInterval(4))
        XCTAssertTrue(t.opponents.isEmpty); XCTAssertFalse(t.active)
        feed(t,table(),hand(),at:5)
        XCTAssertFalse(t.opponents.contains { $0.id == id })
        var changed = table(); changed.seats[2].seatNumber = 6
        feed(t,changed,hand(),at:5.5)
        XCTAssertEqual(t.archive.tables.count,3)
        t.endTable(time:time.addingTimeInterval(6)); XCTAssertTrue(t.opponents.isEmpty)
        XCTAssertFalse(t.archive.hands.isEmpty)
    }
    func testCashCheckpointsMeasureNetAndAdjustTopUpsWithoutInventingFinalResult() {
        let t = PlayTracking(persist:false)
        feed(t,table(stack:990),hand()) // 1000 total including blind
        XCTAssertEqual(t.tableRecord?.baselineCents,1000)
        feed(t,table(stack:1190),hand(["Qc","Qs"]),at:0.5)
        XCTAssertEqual(t.archive.hands[0].netCents,200)
        XCTAssertEqual(t.totalNetCents,200)
        XCTAssertTrue(t.addCashAdjustment(cents:500,time:time.addingTimeInterval(1)))
        XCTAssertEqual(t.totalNetCents,200); XCTAssertEqual(t.tableRecord?.pendingCashCents,500)
        feed(t,table(stack:1590),hand(["8c","9c"]),at:1.2)
        XCTAssertEqual(t.archive.hands[1].netCents,-100)
        XCTAssertEqual(t.totalNetCents,100)
        t.endTable(time:time.addingTimeInterval(2))
        XCTAssertNil(t.archive.hands.last?.netCents)
        XCTAssertEqual(t.totalNetCents,100)
        XCTAssertEqual(t.measuredHands.count,2)
    }
    func testPartialFirstHandHasNoOpeningBankrollAndDecisionsAreDeduplicated() {
        let t = PlayTracking(persist:false), board = ["2c","7s","Jd"]
        feed(t,table(board:board),hand(board:board))
        XCTAssertNil(t.tableRecord?.baselineCents); XCTAssertNil(t.currentHand?.openingChips)
        var display = AnalysisDisplay(); display.hand = hand(board:board)
        display.decisionEquity = 0.5; display.decisionCallDollars = 1; display.eligiblePotDollars = 3
        display.estimate = try! CallEstimate(equity:EquityResult(equity:0.5,samplingBound:0,samples:990,exact:true),potBeforeCall:3,call:1)
        for _ in 0..<10 { t.recordDecision(display,current:true); feed(t,table(board:board),hand(board:board)) }
        XCTAssertEqual(t.archive.hands[0].observations.filter { $0.note == "Decision estimate" }.count,1)
        feed(t,table(stack:1190),hand(["Qc","Qs"]),at:1)
        XCTAssertNil(t.archive.hands[0].netCents)
        XCTAssertEqual(t.tableRecord?.baselineCents,1200)
    }
    func testArchivePersistsOnlyHeroAndDoesNotResumeOpponentOrUnfinishedMoneyInterval() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("own-play.json"), t = PlayTracking(url:url)
        feed(t,table(reveal:["Qc","Qs"]),hand(),frames:4)
        t.saveIfNeeded(time:time.addingTimeInterval(1),force:true); t.store.flush()
        let text = try String(contentsOf:url,encoding:.utf8)
        XCTAssertTrue(text.contains("Ah")); XCTAssertFalse(text.contains("Qc")); XCTAssertFalse(text.contains("opponents")); XCTAssertFalse(text.contains("seatNumber"))
        let restored = PlayTracking(url:url)
        XCTAssertEqual(restored.archive.hands.count,1); XCTAssertNotNil(restored.archive.hands[0].ended)
        XCTAssertNil(restored.archive.hands[0].netCents); XCTAssertTrue(restored.opponents.isEmpty); XCTAssertFalse(restored.active)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as? NSNumber)?.intValue,0o600)
    }
    func testUnreadableArchiveIsPreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url = folder.appendingPathComponent("own-play.json"), original = Data("broken-history".utf8)
        try original.write(to:url)
        let t = PlayTracking(url:url)
        XCTAssertNotNil(t.storageError)
        feed(t,table(),hand()); t.endTable(); t.store.flush()
        XCTAssertEqual(try Data(contentsOf:url),original)
    }
}

extension PlayTrackingTests {
    func testSamePreflopCardsReturningAfterAReadingGapDoNotInventAnotherDeal() {
        let t = PlayTracking(persist:false)
        feed(t,table(),hand())
        feed(t,table(folded:true),nil,at:0.5,frames:4)
        feed(t,table(),hand(),at:1,frames:4)
        XCTAssertEqual(t.archive.hands.count,1)
        XCTAssertEqual(t.opponents.first?.observedRounds.count,1)
        XCTAssertNil(t.archive.hands.first?.netCents)
    }
    func testStopClearsOpponentsButKeepsOwnHistoryAndReviewCannotCreateNewDecision() {
        let tracking = PlayTracking(persist:false), app = AppModel(log:.disabled,tracking:tracking)
        feed(tracking,table(reveal:["Qc","Qs"]),hand(),frames:4)
        XCTAssertFalse(tracking.opponents.isEmpty)
        app.clear("Stopped")
        XCTAssertTrue(tracking.opponents.isEmpty); XCTAssertFalse(tracking.active)
        XCTAssertEqual(tracking.archive.hands.count,1)
        XCTAssertNotNil(tracking.archive.hands[0].ended)
    }
    func testPreflopFoldStillTracksOtherPlayersAndNewRoundsWithoutLiveHeroHand() {
        let t = PlayTracking(persist:false)
        feed(t,table(),hand())
        feed(t,table(folded:true),nil,at:0.5,frames:4)
        let board = ["2c","7s","Jd","8h","9d"]
        feed(t,table(board:board,folded:true,reveal:["Qc","Qs"]),nil,at:1,frames:4)
        XCTAssertEqual(t.opponents.first?.shown.count,1)
        XCTAssertEqual(t.archive.hands.first?.board,board)
        XCTAssertFalse(t.archive.hands.first?.sawFlop ?? true)
        feed(t,table(folded:true),nil,at:1.5,frames:4)
        feed(t,table(board:["3c","6s","Td"],folded:true,reveal:["Ac","Ad"]),nil,at:2,frames:4)
        XCTAssertEqual(t.opponents.first?.shown.count,2)
        XCTAssertEqual(t.archive.hands.first?.board,board,"A later anonymous round cannot overwrite the saved own hand")
    }
    func testConflictingRevealsAreQuarantinedAndFoldedHeroCardsCannotBeShownElsewhere() {
        let t = PlayTracking(persist:false)
        feed(t,table(reveal:["Qc","Qs"]),hand(),frames:4)
        feed(t,table(reveal:["8c","9c"]),hand(),at:0.5,frames:4)
        XCTAssertTrue(t.opponents.first?.shown.isEmpty == true)
        feed(t,table(reveal:["Qc","Qs"]),hand(),at:1,frames:4)
        XCTAssertTrue(t.opponents.first?.shown.isEmpty == true)
        let t2 = PlayTracking(persist:false)
        feed(t2,table(),hand())
        feed(t2,table(folded:true,reveal:["Ah","Qs"]),nil,at:0.5,frames:4)
        XCTAssertTrue(t2.opponents.first?.shown.isEmpty == true)
    }
}
