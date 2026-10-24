import Foundation
import TableRecognition

struct RecognizedPosition {
    var position: PokerPosition
    var dealerID: Int
    /// Clockwise dealt seats, including folded players. Empty/sitting-out/new seats are excluded.
    var ring: [TableSeat]
    var heroIndex: Int
    var dealerIndex: Int
    static func read(_ table: TableObservation) -> RecognizedPosition? {
        guard table.trackingUsable, let dealer=table.dealerSeatID,
              table.seats.filter(\.isHero).count==1,
              Set(table.seats.map(\.id)).count==table.seats.count,
              table.seats.allSatisfy({ $0.activity != .unknown && $0.bounds.valid }) else { return nil }
        let ring=table.seats.filter { [.active,.folded].contains($0.activity) }.sorted { $0.id<$1.id }
        guard (2...9).contains(ring.count),let d=ring.firstIndex(where:{ $0.id==dealer }),let h=ring.firstIndex(where: \.isHero) else { return nil }
        let distance=(h-d+ring.count)%ring.count, n=ring.count, p: PokerPosition
        if distance==0 { p = .button }
        else if n==2 { p = .bigBlind } // Button is also the small blind heads-up.
        else if distance==1 { p = .smallBlind }
        else if distance==2 { p = .bigBlind }
        else if distance==n-1 { p = .cutoff }
        else if distance==n-2 { p = .hijack }
        else { p = n>=7 && distance>n-4 ? .middle : .early }
        return RecognizedPosition(position:p,dealerID:dealer,ring:ring,heroIndex:h,dealerIndex:d)
    }
    func agrees(with other: RecognizedPosition) -> Bool {
        guard position==other.position,dealerID==other.dealerID,ring.count==other.ring.count else { return false }
        return zip(ring,other.ring).allSatisfy { a,b in
            a.id==b.id && a.isHero==b.isHero &&
            (a.seatNumber==nil || b.seatNumber==nil || a.seatNumber==b.seatNumber) &&
            abs(a.bounds.rect.midX-b.bounds.rect.midX)<0.015 && abs(a.bounds.rect.midY-b.bounds.rect.midY)<0.015
        }
    }
    var blindIDs: Set<Int> {
        if ring.count==2 { return Set(ring.map(\.id)) }
        return [ring[(dealerIndex+1)%ring.count].id,ring[(dealerIndex+2)%ring.count].id]
    }
    var beforeHero: [TableSeat] {
        let start=(dealerIndex+(ring.count==2 ? 0 : 3))%ring.count
        var i=start,result=[TableSeat]()
        while i != heroIndex { result.append(ring[i]); i=(i+1)%ring.count }
        return result
    }
    func situation(table: TableObservation,bigBlind: Int?,evidence: PreflopEvidence) -> PreflopSituation {
        if evidence.heroCalled || evidence.heroRaised || evidence.opponentRaises>0 || ring.contains(where:{ $0.action == .raise }) { return .raised }
        guard let bb=bigBlind,bb>0 else { return .unknown }
        if ring.contains(where:{ ($0.betCents ?? 0)>bb }) { return .raised }
        if ring.contains(where:{ !$0.isHero && ($0.action == .call || !blindIDs.contains($0.id) && ($0.betCents ?? 0)>0) }) { return .limped }
        guard position != .bigBlind,ring.count>=3,table.sidePots==false,
              table.potCents==bb+bb/2,bb%2==0,
              (table.hero?.betCents ?? (position == .smallBlind ? bb/2 : 0)) == (position == .smallBlind ? bb/2 : 0),
              beforeHero.allSatisfy({ $0.activity == .folded && $0.action?.entersPot != true && ($0.betCents ?? 0)==0 }),
              ring.allSatisfy({ ($0.betCents ?? 0)<=bb && $0.action?.entersPot != true }) else { return .unknown }
        return .firstIn
    }
}

struct PositionStabilizer {
    private var previous: RecognizedPosition?
    private var dealtRoster: [TableSeat]?
    private var previousBlind: Int?
    private(set) var recognized: RecognizedPosition?
    private(set) var bigBlind: Int?
    mutating func reset() { self=PositionStabilizer() }
    mutating func update(_ table: TableObservation?) {
        var next=table.flatMap(RecognizedPosition.read)
        if let locked=dealtRoster, let candidate=next,
           locked.map(\.id) != candidate.ring.map(\.id) || !zip(locked,candidate.ring).allSatisfy({ a,b in a.seatNumber==nil || b.seatNumber==nil || a.seatNumber==b.seatNumber }) {
            // A player joining/leaving during a hand must not renumber that hand's positions.
            // Re-establish a dealt roster on the next hand or capture reset.
            next=nil
        }
        recognized = next.flatMap { candidate in previous.map { candidate.agrees(with:$0) }==true ? candidate : nil }
        if let recognized, dealtRoster==nil { dealtRoster=recognized.ring }
        let blind=table?.trackingUsable==true ? table?.bigBlindCents : nil
        bigBlind = blind != nil && blind==previousBlind ? blind : nil
        previous=next; previousBlind=blind
    }
}

extension HandAnalysisModel {
    var effectivePosition: PokerPosition { position != .unknown ? position : recognizedPosition?.position ?? .unknown }
    var positionSource: String { position != .unknown ? "manual override" : recognizedPosition != nil ? "recognized dealer + seats" : "unconfirmed; hijack fallback" }
    var positionSummary: String { "\(effectivePosition == .unknown ? "Position unknown" : effectivePosition.rawValue) · \(positionSource)" }
    var effectiveSituation: PreflopSituation {
        if preflopSituation != .unknown { return preflopSituation }
        guard currentHand?.board.isEmpty==true,let table,let recognizedPosition else { return .unknown }
        return recognizedPosition.situation(table:table,bigBlind:effectiveBigBlind,evidence:preflopEvidence)
    }
    var effectiveBigBlind: Int? { TableMoney.cents(bigBlindText,requireCurrency:false).flatMap { $0>0 ? $0 : nil } ?? recognizedBigBlind }
}
