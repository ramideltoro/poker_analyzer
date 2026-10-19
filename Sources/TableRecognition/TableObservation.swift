import Foundation

public enum SeatActivity: String, Sendable, Equatable {
    case active, folded, sittingOut, waiting, unknown
    public var label: String {
        switch self {
        case .active: return "In hand"
        case .folded: return "No cards visible"
        case .sittingOut: return "Sitting out"
        case .waiting: return "Waiting"
        case .unknown: return "Unclear"
        }
    }
}
public struct TableSeat: Sendable, Equatable, Identifiable {
    public var id: Int
    public var bounds: UnitRect
    public var isHero: Bool
    public var stackCents: Int?
    public var betCents: Int?
    public var activity: SeatActivity
    public init(id: Int,bounds: UnitRect,isHero: Bool,stackCents: Int?,betCents: Int? = nil,activity: SeatActivity) {
        self.id = id; self.bounds = bounds; self.isHero = isHero; self.stackCents = stackCents; self.betCents = betCents; self.activity = activity
    }
}
public struct TableObservation: Sendable, Equatable {
    public var potCents: Int?
    public var callCents: Int?
    public var seats: [TableSeat]
    public var sidePots: Bool
    public var issue: String?
    public init(potCents: Int?,callCents: Int?,seats: [TableSeat],sidePots: Bool = false,issue: String? = nil) {
        self.potCents = potCents; self.callCents = callCents; self.seats = seats; self.sidePots = sidePots; self.issue = issue
    }
    public var hero: TableSeat? { seats.first(where: \.isHero) }
    public var activeOpponents: [TableSeat] { seats.filter { !$0.isHero && $0.activity == .active } }
    public var incompleteReason: String? {
        if let issue { return issue }
        guard (2...9).contains(seats.count), seats.filter(\.isHero).count == 1 else { return "Cannot identify all occupied seats and your stack." }
        guard seats.allSatisfy({ $0.activity != .unknown }) else { return "Confirming which players are still in the hand." }
        guard seats.filter({ $0.isHero || $0.activity == .active }).allSatisfy({ $0.stackCents != nil }) else { return "Reading the stacks of players still in the hand." }
        guard let potCents, potCents > 0 else { return "Waiting for a readable total pot." }
        guard let callCents, callCents >= 0 else { return "Waiting for a readable Call or Check button." }
        guard !activeOpponents.isEmpty else { return "Waiting for another player’s visible cards." }
        guard !sidePots else { return "Side-pot eligibility needs contribution history; automatic call EV is unavailable." }
        guard let stack = hero?.stackCents, stack > 0 else { return "You are all-in or your remaining stack is unreadable." }
        if callCents > stack && activeOpponents.count > 1 { return "A multiway short all-in needs contribution history." }
        if callCents > stack && potCents <= callCents-stack { return "The pot and unmatched bet are inconsistent." }
        return nil
    }
    /// Ignore minor rectangle jitter, but never confirm changed money/activity from a previous frame.
    public func agrees(with other: TableObservation) -> Bool {
        guard potCents == other.potCents, callCents == other.callCents, sidePots == other.sidePots,
              issue == other.issue, seats.count == other.seats.count else { return false }
        return zip(seats,other.seats).allSatisfy { a,b in
            a.id == b.id && a.isHero == b.isHero && a.stackCents == b.stackCents && a.betCents == b.betCents && a.activity == b.activity &&
            abs(a.bounds.rect.midX-b.bounds.rect.midX) < 0.015 && abs(a.bounds.rect.midY-b.bounds.rect.midY) < 0.015
        }
    }
    /// Inactive players' remaining chips do not change current-pot EV. Ignore their OCR jitter.
    public func agreesForAnalysis(with other: TableObservation) -> Bool {
        var a = self, b = other
        for i in a.seats.indices where !a.seats[i].isHero && a.seats[i].activity != .active { a.seats[i].stackCents = nil; a.seats[i].betCents = nil }
        for i in b.seats.indices where !b.seats[i].isHero && b.seats[i].activity != .active { b.seats[i].stackCents = nil; b.seats[i].betCents = nil }
        return a.agrees(with:b)
    }
}

public struct TableReadingStabilizer {
    private var previous: TableObservation?
    public init() {}
    public mutating func reset() { previous = nil }
    public mutating func accept(_ reading: TableObservation?) -> TableObservation? {
        defer { previous = reading }
        guard let reading, let previous, reading.agreesForAnalysis(with:previous) else { return nil }
        return reading
    }
}

/// Strict cents parser: no OCR substitutions, partial matches, locale guessing or floating-point rounding.
public enum TableMoney {
    public static func cents(_ text: String,requireCurrency: Bool = true) -> Int? {
        let value = text.trimmingCharacters(in:.whitespacesAndNewlines)
        let pattern = requireCurrency ? #"^\$([0-9]{1,6})(?:\.([0-9]{2}))?$"# : #"^\$?([0-9]{1,6})(?:\.([0-9]{2}))?$"#
        let regex = try! NSRegularExpression(pattern:pattern)
        let range = NSRange(value.startIndex...,in:value)
        guard let match = regex.firstMatch(in:value,range:range), let wholeRange = Range(match.range(at:1),in:value), let whole = Int(value[wholeRange]) else { return nil }
        let fraction = Range(match.range(at:2),in:value).flatMap { Int(value[$0]) } ?? 0
        return whole*100+fraction
    }
}
