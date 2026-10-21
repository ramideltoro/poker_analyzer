import Foundation
import TableRecognition

enum ActionEvidence: String, Codable, Sendable { case label, chips, turn, cards }
struct TrackedAction: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var time: Date
    var round: UUID
    var street: Int
    var kind: SeatAction
    var addedCents: Int?
    var wagerToCents: Int?
    var evidence: ActionEvidence?
    var evidenceDescription: String {
        switch evidence {
        case .chips: return "Inferred: chips + pot"
        case .turn: return "Inferred: turn change"
        case .cards: return "Inferred: cards + turn change"
        default: return "Read action label"
        }
    }
    var inferred: Bool { evidence != nil && evidence != .label }
}

struct ActionStatistics {
    var events: [TrackedAction]
    var total: Int { events.count }
    var inferredCount: Int { events.filter(\.inferred).count }
    func count(_ kind: SeatAction) -> Int { events.filter { $0.kind == kind }.count }
    func rate(_ kind: SeatAction) -> Double? { total > 0 ? Double(count(kind))/Double(total) : nil }
    var preflopHands: Int { Set(events.filter { $0.street == 0 }.map(\.round)).count }
    var playedHands: Int { Set(events.filter { $0.street == 0 && $0.kind.entersPot }.map(\.round)).count }
    var raisedPreflopHands: Int { Set(events.filter { $0.street == 0 && $0.kind == .raise }.map(\.round)).count }
    var playRate: Double? { preflopHands > 0 ? Double(playedHands)/Double(preflopHands) : nil }
    var preflopRaiseRate: Double? { preflopHands > 0 ? Double(raisedPreflopHands)/Double(preflopHands) : nil }
    var aggression: Double? { total > 0 ? Double(count(.bet)+count(.raise))/Double(total) : nil }
    var knownAddedCents: Int { events.compactMap(\.addedCents).reduce(0,+) }
    var knownRaiseAddedCents: Int { events.filter { $0.kind == .raise }.compactMap(\.addedCents).reduce(0,+) }
    var pricedRaises: Int { events.filter { $0.kind == .raise && $0.addedCents != nil }.count }
}

/// Debounces explicit action labels. Chip changes and card disappearances never synthesize actions.
struct ActionScanner {
    private var round: UUID?
    private var street: Int?
    private var candidate: SeatAction?
    private var baseline: TableSeat?
    private var candidateTime: Date?
    private var candidateCount = 0
    private var latched: SeatAction?
    private var latchedStack: Int?
    private var latchedBet: Int?
    private var clearFrames = 0
    private var cleared = false
    private var folded = false
    private var checked = false
    private var awaitingFreshLabel = false
    mutating func interrupt() { candidate = nil; candidateCount = 0; baseline = nil; candidateTime = nil }
    mutating func accept(_ seat: TableSeat,previous: TableSeat?,round nextRound: UUID,street nextStreet: Int,time: Date) -> TrackedAction? {
        if round != nextRound {
            self = ActionScanner(); round = nextRound; street = nextStreet
        } else if street != nextStreet {
            let oldLabel = latched, oldFolded = folded
            self = ActionScanner(); round = nextRound; street = nextStreet
            folded = oldFolded; latched = oldLabel; awaitingFreshLabel = oldLabel != nil
        }
        guard !folded else { return nil }
        guard !seat.isNewPlayer, seat.activity != .waiting, seat.activity != .sittingOut, let action = seat.action else {
            interrupt(); clearFrames += 1
            if clearFrames >= 2 { cleared = true; if awaitingFreshLabel { awaitingFreshLabel = false; latched = nil } }
            return nil
        }
        if awaitingFreshLabel {
            guard action != latched else { return nil }
            awaitingFreshLabel = false; latched = nil
        }
        if candidate != action {
            candidate = action; baseline = previous; candidateTime = time; candidateCount = 1
        } else { candidateCount += 1 }
        clearFrames = 0
        let chipConfirmation: Bool
        if action.entersPot, let before = baseline?.stackCents, let now = seat.stackCents,
           let beforeBet = baseline?.betCents, let afterBet = seat.betCents {
            chipConfirmation = before > now && afterBet > beforeBet && before-now == afterBet-beforeBet
        } else { chipConfirmation = false }
        guard candidateCount >= 2 || chipConfirmation else { return nil }
        if action == .check && checked { return nil }
        if latched == action {
            let moneyChanged = (seat.stackCents != nil && latchedStack != nil && seat.stackCents != latchedStack) ||
                (seat.betCents != nil && latchedBet != nil && seat.betCents != latchedBet)
            guard cleared && moneyChanged else { return nil }
        }
        var added: Int?
        if action == .check || action == .fold { added = 0 }
        else if let before = baseline?.stackCents, let now = seat.stackCents, before > now {
            added = before-now
        }
        latched = action; latchedStack = seat.stackCents; latchedBet = seat.betCents; cleared = false
        if action == .fold { folded = true }
        if action == .check { checked = true }
        return TrackedAction(time:candidateTime ?? time,round:nextRound,street:nextStreet,kind:action,addedCents:added,wagerToCents:seat.betCents,evidence:.label)
    }
}
