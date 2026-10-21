import XCTest
import PokerCore
import TableRecognition
@testable import MacPokerCoach

final class ActionTransitionTests: XCTestCase {
    let round = UUID(), time = Date(timeIntervalSince1970:1_800_000_000)
    func table() -> TableObservation {
        TableObservation(potCents:100,callCents:0,seats:[
            TableSeat(id:1,bounds:UnitRect(x:0.4,y:0.2,width:0.15,height:0.05),isHero:false,stackCents:1000,betCents:0,activity:.active,seatNumber:1,isActing:true),
            TableSeat(id:2,bounds:UnitRect(x:0.7,y:0.4,width:0.15,height:0.05),isHero:false,stackCents:1000,betCents:0,activity:.active,seatNumber:2),
            TableSeat(id:3,bounds:UnitRect(x:0.4,y:0.8,width:0.15,height:0.05),isHero:true,stackCents:1000,betCents:0,activity:.active,seatNumber:3)
        ],boardCards:["2c","7s","Jd"].compactMap(Card.init))
    }
    func feed(_ tracker: inout ActionTransitions,_ table: TableObservation,at offset: Double) -> [ActionTransitions.Event] {
        var result = [ActionTransitions.Event]()
        for i in 0..<2 { result += tracker.accept(table,round:round,time:time.addingTimeInterval(offset+Double(i)*0.1)) }
        return result
    }
    func testChipTransitionsWithoutLabelsClassifyBetRaiseCallOnce() {
        var tracker = ActionTransitions(), scene = table()
        XCTAssertTrue(feed(&tracker,scene,at:0).isEmpty)
        scene.seats[0].stackCents = 950; scene.seats[0].betCents = 50; scene.potCents = 150
        let bet = feed(&tracker,scene,at:0.3)
        XCTAssertEqual(bet.map(\.action.kind),[.bet]); XCTAssertEqual(bet.first?.action.addedCents,50)
        XCTAssertEqual(bet.first?.action.evidence,.chips)
        XCTAssertTrue(feed(&tracker,scene,at:0.6).isEmpty)
        scene.seats[1].stackCents = 900; scene.seats[1].betCents = 100; scene.potCents = 250
        XCTAssertEqual(feed(&tracker,scene,at:0.9).map(\.action.kind),[.raise])
        scene.seats[0].stackCents = 900; scene.seats[0].betCents = 100; scene.potCents = 300
        XCTAssertEqual(feed(&tracker,scene,at:1.2).map(\.action.kind),[.call])
    }
    func testPotAnimationCanSettleButNotAcrossLongGaps() {
        var tracker = ActionTransitions(), scene = table()
        _ = feed(&tracker,scene,at:0)
        scene.seats[0].stackCents = 950; scene.seats[0].betCents = 50
        XCTAssertTrue(feed(&tracker,scene,at:0.3).isEmpty)
        scene.potCents = 150
        XCTAssertEqual(feed(&tracker,scene,at:0.6).map(\.action.kind),[.bet])
        scene.seats[1].stackCents = 900; scene.seats[1].betCents = 100; scene.potCents = 250
        XCTAssertTrue(feed(&tracker,scene,at:3).isEmpty)
    }
    func testChecksAndFoldsRequireTurnChangeAndUnchangedMoney() {
        var tracker = ActionTransitions(), scene = table()
        _ = feed(&tracker,scene,at:0)
        XCTAssertTrue(feed(&tracker,scene,at:0.3).isEmpty,"An unchanged frame is not a check")
        scene.seats[0].isActing = false; scene.seats[1].isActing = true
        let check = feed(&tracker,scene,at:0.6)
        XCTAssertEqual(check.map(\.action.kind),[.check]); XCTAssertEqual(check.first?.action.evidence,.turn)
        scene.seats[1].activity = .folded
        XCTAssertTrue(feed(&tracker,scene,at:0.9).isEmpty,"Card disappearance alone is not a fold")
        var other = ActionTransitions(); var before = table(); before.seats[0].isActing = false; before.seats[1].isActing = true
        _ = feed(&other,before,at:0)
        before.seats[1].activity = .folded; before.seats[1].isActing = false; before.seats[0].isActing = true
        let fold = feed(&other,before,at:0.3)
        XCTAssertEqual(fold.map(\.action.kind),[.fold]); XCTAssertEqual(fold.first?.action.evidence,.cards)
    }
    func testUncertainAndIncompatibleTransitionsCannotInventActions() {
        for mode in 0..<10 {
            var tracker = ActionTransitions(), scene = table()
            _ = feed(&tracker,scene,at:0)
            scene.seats[0].stackCents = 950; scene.seats[0].betCents = 50; scene.potCents = 150
            switch mode {
            case 0: scene.seats[1].stackCents = 950
            case 1: scene.seats[0].stackCents = nil
            case 2: scene.potCents = 175
            case 3: scene.sidePots = true
            case 4: scene.seats[0].isNewPlayer = true
            case 5: scene.seats[0].activity = .unknown
            case 6: scene.seats[0].stackCents = 1100
            case 7: scene.boardCards.append(Card("8h")!)
            case 8: scene.seats[0].bounds.x += 0.1
            default: scene.issue = "Unclear amount"
            }
            XCTAssertTrue(feed(&tracker,scene,at:0.3).isEmpty,"mode \(mode)")
        }
        var tracker = ActionTransitions(), scene = table(); scene.boardCards = []
        _ = feed(&tracker,scene,at:0)
        scene.seats[0].stackCents = 950; scene.seats[0].betCents = 50; scene.potCents = 150
        XCTAssertTrue(feed(&tracker,scene,at:0.3).isEmpty,"Initial preflop posting is not a raise")
    }
    func testAbsentOldWagersNeverBecomeAssumedZero() {
        var tracker = ActionTransitions(), scene = table()
        scene.callCents = nil; scene.seats = scene.seats.map { var s=$0; s.betCents=nil; return s }
        _ = feed(&tracker,scene,at:0)
        scene.seats[0].stackCents = 950; scene.seats[0].betCents = 50; scene.potCents = 150
        XCTAssertTrue(feed(&tracker,scene,at:0.3).isEmpty)
    }
}

@MainActor final class InferredTrackingTests: XCTestCase {
    func testAfterFoldChipActionsTrackUpgradeToLabelAndSurvivePotReadingFailure() throws {
        let f = PlayTrackingTests(), t = PlayTracking(persist:false)
        var scene = ActionTransitionTests().table()
        scene.seats[2].activity = .folded
        f.feed(t,scene,f.hand(board:["2c","7s","Jd"],review:false),frames:4)
        scene.seats[0].stackCents = 950; scene.seats[0].betCents = 50; scene.potCents = 150
        f.feed(t,scene,nil,at:0.5,frames:4)
        XCTAssertEqual(t.opponents.first?.statistics.count(.bet),1)
        XCTAssertEqual(t.opponents.first?.statistics.inferredCount,1)
        scene.seats[0].action = .bet
        f.feed(t,scene,nil,at:1,frames:4)
        XCTAssertEqual(t.opponents.first?.statistics.count(.bet),1)
        XCTAssertEqual(t.opponents.first?.statistics.inferredCount,0)
        XCTAssertEqual(t.opponents.first?.flopRounds.count,1)
        scene.potCents = nil; scene.issue = "Unreadable pot"; scene.trackingUsable = true; scene.seats[1].action = .fold
        f.feed(t,scene,nil,at:1.5,frames:4)
        XCTAssertEqual(t.opponents.count,2); XCTAssertEqual(t.opponents.last?.statistics.count(.fold),1)
        let id = t.opponents.first!.id
        scene.seats[0].isNewPlayer = true; scene.seats[0].activity = .waiting
        f.feed(t,scene,nil,at:2,frames:4)
        XCTAssertFalse(t.opponents.contains { $0.id == id })
        t.endTable(); XCTAssertTrue(t.opponents.isEmpty)
    }
    func testInferredOwnActionsPersistWithProvenanceAndOldActionsDecode() throws {
        let f = PlayTrackingTests(), t = PlayTracking(persist:false)
        var scene = ActionTransitionTests().table()
        f.feed(t,scene,f.hand(board:["2c","7s","Jd"]),frames:4)
        scene.seats[2].stackCents = 950; scene.seats[2].betCents = 50; scene.potCents = 150
        f.feed(t,scene,f.hand(board:["2c","7s","Jd"]),at:0.5,frames:4)
        XCTAssertEqual(t.ownStatistics.count(.bet),1); XCTAssertEqual(t.ownStatistics.inferredCount,1)
        let decoded = try JSONDecoder().decode(OwnPlayArchive.self,from:JSONEncoder().encode(t.archive))
        XCTAssertEqual(decoded.hands.first?.actions?.first?.evidence,.chips)
        var event = TrackedAction(time:Date(),round:UUID(),street:0,kind:.call)
        event.evidence = nil
        let old = try JSONDecoder().decode(TrackedAction.self,from:JSONEncoder().encode(event))
        XCTAssertFalse(old.inferred); XCTAssertEqual(old.evidenceDescription,"Read action label")
    }
}

extension ActionTransitionTests {
    func testContradictoryFreeControlsAndImpossiblePotDoNotInferPaidActions() {
        for contradiction in [true,false] {
            var tracker=ActionTransitions(), scene=table()
            scene.seats[1].betCents=50; scene.controls=TableControls(canCheck:true)
            _ = feed(&tracker,scene,at:0)
            scene.seats[0].stackCents=960; scene.seats[0].betCents=40
            scene.potCents=contradiction ? 140 : 20
            XCTAssertTrue(feed(&tracker,scene,at:0.3).isEmpty)
        }
    }
}
