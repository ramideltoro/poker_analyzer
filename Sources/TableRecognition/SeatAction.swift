import Foundation

public enum SeatAction: String, Codable, Sendable, CaseIterable, Hashable {
    case fold, check, call, bet, raise
    public var label: String { rawValue.capitalized }
    public var entersPot: Bool { self == .call || self == .bet || self == .raise }
    /// Only an explicit action label. Blinds, available controls, all-in and chip changes are not actions.
    public static func parse(_ text: String) -> SeatAction? {
        let normalized = text.uppercased().trimmingCharacters(in:.whitespacesAndNewlines)
            .replacingOccurrences(of:#"\s+"#,with:" ",options:.regularExpression)
        for (action,pattern) in [
            (SeatAction.fold,#"^(FOLD|FOLDED|FOLDS)$"#),
            (.check,#"^(CHECK|CHECKED|CHECKS)$"#),
            (.call,#"^(CALL|CALLED|CALLS)( \$[0-9]+(\.[0-9]{2})?)?$"#),
            (.bet,#"^(BET|BETS)( \$[0-9]+(\.[0-9]{2})?)?$"#),
            (.raise,#"^(RAISE|RAISED|RAISES)( TO)?( \$[0-9]+(\.[0-9]{2})?)?$"#)
        ] { if normalized.range(of:pattern,options:.regularExpression) != nil { return action } }
        return nil
    }
}

public struct TableControls: Sendable, Equatable {
    public var canFold: Bool
    public var canCheck: Bool
    public var canCall: Bool
    public var canBet: Bool
    public var canRaise: Bool
    public var raiseToCents: Int?
    public var betAmountCents: Int?
    public init(canFold: Bool = false,canCheck: Bool = false,canCall: Bool = false,canBet: Bool = false,canRaise: Bool = false,raiseToCents: Int? = nil,betAmountCents: Int? = nil) {
        self.canFold = canFold; self.canCheck = canCheck; self.canCall = canCall; self.canBet = canBet; self.canRaise = canRaise
        self.raiseToCents = raiseToCents; self.betAmountCents = betAmountCents
    }
}
