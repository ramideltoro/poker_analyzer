import Foundation

/// Prices relative to folding. One eligible pot, no future betting or rake.
public struct DecisionPrice: Equatable, Sendable {
    public let equity: Double
    public let call: Double
    public let pot: Double
    public init(equity: Double, pot: Double, call: Double) throws {
        guard equity.isFinite, (0...1).contains(equity), pot.isFinite, pot > 0,
              call.isFinite, call >= 0, (pot+call).isFinite else { throw EquityError.invalidAmounts }
        self.equity = equity; self.pot = pot; self.call = call
    }
    /// nil means no finite pot makes a positive-cost call break even at zero equity.
    public var minimumPot: Double? {
        if call == 0 { return 0 }
        guard equity > 0 else { return nil }
        let value = call*(1-equity)/equity
        return value.isFinite ? max(0,value) : nil
    }
    public var maximumCall: Double? {
        guard equity < 1 else { return nil } // unbounded at certain full pot ownership
        let value = equity*pot/(1-equity)
        return value.isFinite ? value : nil
    }
    public var callEV: Double { equity*(pot+call)-call }
}

/// A transparent heads-up raise scenario, NOT a recommended size or a solver policy.
/// Risk is the additional chips put in now (including the call), not a raise-to amount.
public struct RaiseScenario: Equatable, Sendable {
    public let ev: Double
    public let calledEV: Double
    public let minimumPot: Double?
    public let requiredFoldFrequency: Double?
    public init(pot: Double,risk: Double,opponentAdds: Double,equityWhenCalled: Double,foldFrequency: Double) throws {
        guard [pot,risk,opponentAdds,equityWhenCalled,foldFrequency].allSatisfy(\.isFinite),
              pot > 0, risk > 0, opponentAdds >= 0, (0...1).contains(equityWhenCalled),
              (0...1).contains(foldFrequency), (pot+risk+opponentAdds).isFinite else { throw EquityError.invalidAmounts }
        calledEV = equityWhenCalled*(pot+risk+opponentAdds)-risk
        ev = foldFrequency*pot+(1-foldFrequency)*calledEV
        let coefficient = foldFrequency+(1-foldFrequency)*equityWhenCalled
        let needed = coefficient > 0 ? max(0,(1-foldFrequency)*(risk-equityWhenCalled*(risk+opponentAdds))/coefficient) : .infinity
        minimumPot = needed.isFinite ? needed : nil
        requiredFoldFrequency = calledEV >= 0 ? 0 : min(1,-calledEV/(pot-calledEV))
    }
}
