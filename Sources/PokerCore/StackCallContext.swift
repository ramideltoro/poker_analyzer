import Foundation

/// A single-pot call, with an uncapped amount-to-call and remaining stacks in integer cents.
/// Future wagers are excluded: stacks constrain eligibility/exposure, not showdown hand strength.
public struct StackCallContext: Sendable, Equatable {
    public let potCents: Int
    public let callCents: Int
    public let unmatchedCents: Int
    public let effectiveStacks: [Int]
    public init(potCents: Int,uncappedCallCents: Int,heroStackCents: Int,opponentStackCents: [Int],sidePots: Bool = false) throws {
        guard potCents > 0, potCents <= 100_000_000, uncappedCallCents >= 0, uncappedCallCents <= 100_000_000,
              heroStackCents > 0, heroStackCents <= 100_000_000, (1...8).contains(opponentStackCents.count),
              opponentStackCents.allSatisfy({ (0...100_000_000).contains($0) }), !sidePots else { throw EquityError.invalidAmounts }
        let cost = min(uncappedCallCents,heroStackCents)
        let unmatched = uncappedCallCents-cost
        // Contribution history is required to assign multiway side pots when hero cannot cover a wager.
        guard unmatched == 0 || opponentStackCents.count == 1, potCents > unmatched else { throw EquityError.invalidAmounts }
        self.potCents = potCents-unmatched; callCents = cost; unmatchedCents = unmatched
        effectiveStacks = opponentStackCents.map { min(heroStackCents,$0) }
    }
    public func estimate(_ equity: EquityResult) throws -> CallEstimate {
        try CallEstimate(equity:equity,potBeforeCall:Double(potCents)/100,call:Double(callCents)/100)
    }
}
