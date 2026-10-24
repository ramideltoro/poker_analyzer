import Foundation
import PokerCore
import TableRecognition

/// Presentation-only history. These values never feed the live calculation.
struct AnalysisDisplay {
    struct VerifiedTurn {
        var advice: ActionAdvice
        var hole: Set<Card>
        var board: Set<Card>
        var call: Int
    }
    var lastVerifiedTurn: VerifiedTurn?
    var lastShownAdvice: ActionAdvice?
    var lastShownHole=[Card]()
    var lastAdvice: ActionAdvice?
    var lastForecastAdvice: ActionAdvice?
    var hand: LiveHand?
    var table: TableObservation?
    var result: EquityResult?
    var estimate: CallEstimate?
    var context: StackCallContext?
    var eligiblePotDollars: Double?
    var decisionEquity: Double?
    var decisionCallDollars: Double?
    var opponents = 1
    var equityTime: Date?
    var estimateTime: Date?
    var tableTime: Date?
}
