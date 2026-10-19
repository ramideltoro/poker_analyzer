import Foundation
import PokerCore
import TableRecognition

/// Presentation-only history. These values never feed the live calculation.
struct AnalysisDisplay {
    var hand: LiveHand?
    var table: TableObservation?
    var result: EquityResult?
    var estimate: CallEstimate?
    var context: StackCallContext?
    var eligiblePotDollars: Double?
    var opponents = 1
    var equityTime: Date?
    var estimateTime: Date?
    var tableTime: Date?
}
