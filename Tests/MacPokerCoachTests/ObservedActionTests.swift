import XCTest
import TableRecognition
@testable import MacPokerCoach

final class ObservedActionTests: XCTestCase {
    func seat(_ action: SeatAction?,stack: Int? = 1000,bet: Int? = 0) -> TableSeat {
        TableSeat(id:1,bounds:UnitRect(x:0.4,y:0.3,width:0.2,height:0.05),isHero:false,stackCents:stack,betCents:bet,activity:.active,action:action)
    }
    func testPersistentLabelsAndMoneyChangesDoNotDuplicateButAnotherRaiseCanCount() {
        var scanner = ActionScanner(); let round = UUID(), time = Date()
        var events = [TrackedAction]()
        let before = seat(nil), raised = seat(.raise,stack:900,bet:100)
        for i in 0..<20 { if let e = scanner.accept(raised,previous:i == 0 ? before : raised,round:round,street:3,time:time) { events.append(e) } }
        XCTAssertEqual(events.count,1); XCTAssertEqual(events[0].addedCents,100)
        let changed = seat(.raise,stack:800,bet:200)
        for _ in 0..<5 { XCTAssertNil(scanner.accept(changed,previous:raised,round:round,street:3,time:time)) }
        for _ in 0..<2 { XCTAssertNil(scanner.accept(seat(nil,stack:800,bet:200),previous:changed,round:round,street:3,time:time)) }
        let reraised = seat(.raise,stack:600,bet:400)
        XCTAssertNil(scanner.accept(reraised,previous:seat(nil,stack:800,bet:200),round:round,street:3,time:time))
        let event = scanner.accept(reraised,previous:reraised,round:round,street:3,time:time)
        XCTAssertEqual(event?.kind,.raise); XCTAssertEqual(event?.addedCents,200)
    }
    func testFoldDoesNotCountAgainWhenBoardAdvancesAndSameLabelPersists() {
        var scanner = ActionScanner(); let round = UUID(), time = Date(), folded = seat(.fold)
        XCTAssertNil(scanner.accept(folded,previous:nil,round:round,street:0,time:time))
        XCTAssertEqual(scanner.accept(folded,previous:folded,round:round,street:0,time:time)?.kind,.fold)
        for street in [3,4,5] { for _ in 0..<5 { XCTAssertNil(scanner.accept(folded,previous:folded,round:round,street:street,time:time)) } }
        let next = UUID()
        XCTAssertNil(scanner.accept(folded,previous:folded,round:next,street:0,time:time))
        XCTAssertEqual(scanner.accept(folded,previous:folded,round:next,street:0,time:time)?.kind,.fold)
    }
    func testFreshCheckCanCountOnAnotherStreetButNoLabelOrChipOnlyReadingCreatesAnAction() {
        var scanner = ActionScanner(); let round = UUID(), time = Date(), check = seat(.check)
        for _ in 0..<5 { XCTAssertNil(scanner.accept(seat(nil,stack:800),previous:seat(nil),round:round,street:3,time:time)) }
        XCTAssertNil(scanner.accept(check,previous:seat(nil),round:round,street:3,time:time))
        XCTAssertEqual(scanner.accept(check,previous:check,round:round,street:3,time:time)?.kind,.check)
        XCTAssertNil(scanner.accept(check,previous:check,round:round,street:4,time:time))
        for _ in 0..<2 { XCTAssertNil(scanner.accept(seat(nil),previous:nil,round:round,street:4,time:time)) }
        XCTAssertNil(scanner.accept(check,previous:seat(nil),round:round,street:4,time:time))
        XCTAssertEqual(scanner.accept(check,previous:check,round:round,street:4,time:time)?.kind,.check)
    }
    func testRatesDistinguishPreflopHandSamplesFromActionMix() {
        let a = UUID(), b = UUID(), c = UUID(), time = Date()
        let events = [TrackedAction(time:time,round:a,street:0,kind:.raise),TrackedAction(time:time,round:a,street:0,kind:.raise),TrackedAction(time:time,round:a,street:3,kind:.check),TrackedAction(time:time,round:b,street:0,kind:.call),TrackedAction(time:time,round:b,street:3,kind:.fold),TrackedAction(time:time,round:c,street:0,kind:.fold)]
        let stats = ActionStatistics(events:events)
        XCTAssertEqual(stats.preflopHands,3); XCTAssertEqual(stats.playedHands,2); XCTAssertEqual(stats.raisedPreflopHands,1)
        XCTAssertEqual(stats.playRate!,2.0/3,accuracy:1e-12)
        XCTAssertEqual(stats.rate(.raise)!,2.0/6,accuracy:1e-12)
        XCTAssertEqual(stats.preflopRaiseRate!,1.0/3,accuracy:1e-12)
        XCTAssertNil(ActionStatistics(events:[]).playRate); XCTAssertNil(ActionStatistics(events:[]).rate(.check))
    }
    func testInterruptedOrSingleLabelsDoNotCountAndUnknownAmountsStayUnknown() {
        var scanner = ActionScanner(); let round = UUID(), time = Date(), call = seat(.call,stack:nil,bet:nil)
        XCTAssertNil(scanner.accept(call,previous:nil,round:round,street:0,time:time))
        scanner.interrupt()
        XCTAssertNil(scanner.accept(call,previous:nil,round:round,street:0,time:time))
        let event = scanner.accept(call,previous:nil,round:round,street:0,time:time)
        XCTAssertEqual(event?.kind,.call); XCTAssertNil(event?.addedCents)
    }
}

@MainActor final class ActionTrackingIntegrationTests: XCTestCase {
    func testOwnAndOpponentActionsPersistSeparatelyAndReplacementWipesOnlyItsActions() throws {
        let fixture = PlayTrackingTests(), tracker = PlayTracking(persist:false)
        fixture.feed(tracker,fixture.table(),fixture.hand())
        var table = fixture.table(); table.seats[0].action = .raise; table.seats[2].action = .call
        fixture.feed(tracker,table,fixture.hand(),at:0.5,frames:4)
        XCTAssertEqual(tracker.ownStatistics.count(.call),1)
        XCTAssertEqual(tracker.opponents.first?.statistics.count(.raise),1)
        let other = tracker.opponents.first(where:{ $0.seatNumber == 2 })!.id
        table.seats[0].isNewPlayer = true; table.seats[0].activity = .waiting
        fixture.feed(tracker,table,fixture.hand(),at:1,frames:4)
        XCTAssertTrue(tracker.opponents.first(where:{ $0.seatNumber == 1 })?.actions.isEmpty == true)
        XCTAssertTrue(tracker.opponents.contains { $0.id == other })
        let decoded = try JSONDecoder().decode(OwnPlayArchive.self,from:JSONEncoder().encode(tracker.archive))
        XCTAssertEqual(decoded.hands.flatMap { $0.actions ?? [] }.map(\.kind),[.call])
        tracker.endTable(); XCTAssertEqual(tracker.ownStatistics.count(.call),1); XCTAssertTrue(tracker.opponents.isEmpty)
    }
    func testActionsContinueAfterHeroFoldAndNoActionIsInferredFromDisappearingCards() {
        let f = PlayTrackingTests(), t = PlayTracking(persist:false)
        f.feed(t,f.table(),f.hand())
        f.feed(t,f.table(folded:true),nil,at:0.5,frames:4)
        XCTAssertEqual(t.ownStatistics.count(.fold),0)
        var table = f.table(folded:true); table.seats[2].action = .fold; table.seats[0].action = .check
        f.feed(t,table,nil,at:1,frames:4)
        XCTAssertEqual(t.ownStatistics.count(.fold),1); XCTAssertEqual(t.opponents.first?.statistics.count(.check),1)
    }
    func testVersionElevenArchiveWithoutActionsStillLoads() throws {
        var archive = OwnPlayArchive()
        archive.hands = [OwnHandRecord(started:Date(),hole:["Ah","Kd"],board:[],startedPreflop:true)]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(archive)) as? [String:Any])
        var hands = try XCTUnwrap(object["hands"] as? [[String:Any]])
        hands[0].removeValue(forKey:"actions"); object["hands"] = hands
        let result = try JSONDecoder().decode(OwnPlayArchive.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(result.hands.count,1); XCTAssertNil(result.hands[0].actions)
    }
    func testResultTotalsAndDrawdownExcludeUnknownFinalPayout() {
        var archive = OwnPlayArchive()
        archive.hands = [100,-200,50,400,-75].enumerated().map { i,value in
            OwnHandRecord(started:Date(timeIntervalSince1970:Double(i)),hole:["Ah","Kd"],board:[],startedPreflop:true,netCents:value)
        }
        archive.hands.append(OwnHandRecord(started:Date(),hole:["Qc","Qs"],board:[],startedPreflop:true))
        let stats = PersonalStatistics(archive:archive)
        XCTAssertEqual(stats.grossWon,550); XCTAssertEqual(stats.grossLost,275)
        XCTAssertEqual(stats.wins,3); XCTAssertEqual(stats.losses,2)
        XCTAssertEqual(stats.trend,[0,100,-100,-50,350,275]); XCTAssertEqual(stats.drawdown,200)
        XCTAssertEqual(stats.averageCents,55); XCTAssertEqual(stats.largestWin,400); XCTAssertEqual(stats.largestLoss,-200)
    }
}

extension ActionTrackingIntegrationTests {
    func testHundredsOfHandsKeepActionCountsStableAndArchiveRoundTrips() throws {
        let f = PlayTrackingTests(), t = PlayTracking(persist:false)
        for hand in 0..<250 {
            let cards = hand%2 == 0 ? ["Ah","Kd"] : ["Qc","Qs"]
            let offset = Double(hand)*1.5
            f.feed(t,f.table(stack:1000),f.hand(cards),at:offset)
            var table = f.table(stack:990,bet:20); table.seats[2].action = .call; table.seats[0].action = .raise
            f.feed(t,table,f.hand(cards),at:offset+0.4,frames:3)
            table.seats[2].action = .fold; table.seats[2].activity = .folded
            f.feed(t,table,nil,at:offset+0.8,frames:3)
            if hand%50 == 0 { _ = try JSONDecoder().decode(OwnPlayArchive.self,from:JSONEncoder().encode(t.archive)) }
        }
        XCTAssertEqual(t.archive.hands.count,250)
        XCTAssertEqual(t.ownStatistics.count(.call),250)
        XCTAssertEqual(t.ownStatistics.count(.fold),250)
        XCTAssertEqual(t.opponents.first?.statistics.count(.raise),250)
        XCTAssertEqual(t.measuredHands.count,249)
        t.endTable(); XCTAssertEqual(t.ownStatistics.total,500); XCTAssertTrue(t.opponents.isEmpty)
    }
}
