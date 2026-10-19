import Foundation
import Combine
import PokerCore
import TableRecognition

@MainActor final class HandAnalysisModel: ObservableObject {
    typealias Calculate = @Sendable ([Card],[Card],Int,@escaping @Sendable () -> Bool) throws -> EquityResult
    @Published private(set) var result: EquityResult?
    @Published private(set) var opponents = 1
    @Published private(set) var calculating = false
    @Published private(set) var error: String?
    @Published private(set) var automatic = true
    @Published private(set) var table: TableObservation?
    @Published private(set) var tableConfirmed = false
    @Published private(set) var display = AnalysisDisplay()
    @Published var potText = "" { didSet { refreshDisplay() } }
    @Published var callText = "" { didSet { refreshDisplay() } }
    private struct CardsKey: Equatable { var hole: [Card]; var board: [Card] }
    private struct Key: Hashable, Sendable { var hole: [Card]; var board: [Card]; var opponents: Int }
    private var cachedResults = [Key:EquityResult]()
    private var cacheOrder = [Key]()
    private var updating = false
    private var cardsKey: CardsKey?
    private var key: Key?
    private var current: LiveHand?
    private var tableStabilizer = TableReadingStabilizer()
    private var generation = UUID()
    private var worker: Task<EquityResult,Error>?
    private let calculate: Calculate

    init(calculate: @escaping Calculate = { hole,board,opponents,cancelled in
        try EquityEngine.calculate(hole:hole,board:board,opponents:opponents,cancelled:cancelled)
    }) { self.calculate = calculate }

    func setAutomatic(_ enabled: Bool) {
        guard enabled != automatic else { return }
        updating = true
        defer { updating = false; refreshDisplay() }
        automatic = enabled; potText = ""; callText = ""
        display.estimate = nil; display.context = nil; display.eligiblePotDollars = nil; display.estimateTime = nil
        invalidate(); refreshAnalysis()
    }
    func setOpponents(_ count: Int) {
        guard !automatic, (1...8).contains(count), count != opponents else { return }
        updating = true
        defer { updating = false; refreshDisplay() }
        opponents = count; potText = ""; callText = ""; refreshAnalysis()
    }
    func update(_ hand: LiveHand?,table reading: TableObservation? = nil) {
        updating = true
        defer { updating = false; refreshDisplay() }
        current = hand
        let next = hand.map { CardsKey(hole:$0.hole.map(\.card).sorted { $0.code < $1.code },board:$0.board.map(\.card).sorted { $0.code < $1.code }) }
        if let next, let previous = display.hand,
           next != CardsKey(hole:previous.hole.map(\.card).sorted { $0.code < $1.code },board:previous.board.map(\.card).sorted { $0.code < $1.code }) {
            display = AnalysisDisplay()
        }
        if next != cardsKey {
            cardsKey = next; potText = ""; callText = ""; tableStabilizer.reset()
        }
        if hand == nil { table = nil; tableConfirmed = false; tableStabilizer.reset() }
        else {
            table = reading
            tableConfirmed = tableStabilizer.accept(reading) != nil
            if automatic, tableConfirmed, let reading, validOpponentCount(reading) {
                opponents = reading.activeOpponents.count
            }
        }
        refreshAnalysis()
    }
    /// Stop, stale capture or permission loss must remove even presentation-only history.
    func reset() { update(nil); display = AnalysisDisplay() }
    private func validOpponentCount(_ table: TableObservation) -> Bool {
        table.seats.filter(\.isHero).count == 1 && (2...9).contains(table.seats.count) &&
        table.seats.allSatisfy { $0.activity != .unknown } && (1...8).contains(table.activeOpponents.count)
    }
    private func invalidate() {
        generation = UUID(); worker?.cancel(); worker = nil; key = nil
        result = nil; calculating = false; error = nil
    }
    private func refreshAnalysis() {
        var next: Key?
        if let cardsKey {
            if !automatic || (table.map { validOpponentCount($0) && $0.activeOpponents.count == opponents } == true && (tableConfirmed || key != nil)) {
                next = Key(hole:cardsKey.hole,board:cardsKey.board,opponents:opponents)
            }
        }
        guard next != key else { return }
        invalidate(); key = next
        guard let next else { return }
        if let cached = cachedResults[next] { result = cached; return }
        let token = generation, calculate = calculate
        calculating = true
        let task = Task.detached(priority:.utility) { try calculate(next.hole,next.board,next.opponents,{ Task.isCancelled }) }
        worker = task
        Task { [weak self] in
            let outcome = await task.result
            guard let self, self.generation == token else { return }
            self.worker = nil; self.calculating = false
            switch outcome {
            case .success(let result):
                self.result = result; self.cachedResults[next] = result
                self.cacheOrder.removeAll { $0 == next }; self.cacheOrder.append(next)
                if self.cacheOrder.count > 16 { self.cachedResults.removeValue(forKey:self.cacheOrder.removeFirst()) }
            case .failure: self.error = "Analysis unavailable for this reading. Waiting for new cards."
            }
            self.refreshDisplay()
        }
    }
    var automaticContext: StackCallContext? {
        guard automatic, tableConfirmed, let table, table.incompleteReason == nil,
              let pot = table.potCents, let quoted = table.callCents, let stack = table.hero?.stackCents else { return nil }
        var uncapped = quoted
        if quoted >= stack {
            // Some clients cap the Call label at hero's stack. Both visible street bets must resolve the true gap.
            guard table.activeOpponents.count == 1, let ownBet = table.hero?.betCents,
                  let opponentBet = table.activeOpponents.first?.betCents else { return nil }
            uncapped = max(0,opponentBet-ownBet)
            guard quoted == min(uncapped,stack) || quoted == uncapped else { return nil }
        }
        return try? StackCallContext(potCents:pot,uncappedCallCents:uncapped,heroStackCents:stack,
                                    opponentStackCents:table.activeOpponents.compactMap(\.stackCents),sidePots:table.sidePots)
    }
    var callEstimate: CallEstimate? {
        guard let result else { return nil }
        if automatic { return try? automaticContext?.estimate(result) }
        guard let pot = Self.amount(potText), let call = Self.amount(callText) else { return nil }
        return try? CallEstimate(equity:result,potBeforeCall:pot,call:call)
    }
    var hasCards: Bool { current != nil }
    var amountHelp: String {
        guard current != nil else { return "Waiting for confirmed cards." }
        if automatic {
            guard let table else { return "Reading the table · last confirmed values stay muted while updating." }
            guard tableConfirmed else { return "Confirming table amounts and player activity across consecutive frames…" }
            if let issue = table.incompleteReason { return issue }
            guard automaticContext != nil else { return "Checking all-in eligibility · waiting for both current bets." }
            return "Pot, remaining stacks, active opponents and call amount read from the table."
        }
        if potText.isEmpty || callText.isEmpty { return "Enter the current pot and your call amount for dollar EV." }
        guard let pot = Self.amount(potText), pot > 0, let call = Self.amount(callText), call >= 0,
              (pot+call).isFinite else { return "Use a positive pot and a nonnegative call in dollars, e.g. 1.50. No commas." }
        return "Pot includes the opponent's current bet and all earlier contributions; exclude your new call."
    }
    var equityIsCurrent: Bool { current != nil && result != nil }
    var estimateIsCurrent: Bool { callEstimate != nil }
    var displayStatus: String {
        if current == nil { return display.hand == nil ? "Waiting for cards" : "Updating · previous confirmed hand" }
        if calculating { return "Calculating probabilities" }
        if callEstimate != nil { return "Live estimate" }
        if !automatic { return "Waiting for manual pot / call inputs" }
        if automatic, table == nil { return "Reading table · keeping previous values muted" }
        if automatic, table?.callCents == nil { return "Waiting for Call / Check controls" }
        if automatic, table?.sidePots == true { return "Side pot · EV needs contribution history" }
        return "Updating table readings"
    }
    var simulationSummary: String {
        guard let value = display.result else { return "Waiting for a confirmed hand and opponent count." }
        let model = "vs \(display.opponents) random \(display.opponents == 1 ? "opponent" : "opponents")"
        return value.exact ? "Exact · \(value.samples) deals · \(model)" : "\(value.samples) deals · \(model) · 95% bound per metric ±\(String(format:"%.1f",value.samplingBound*100)) pp"
    }
    private func refreshDisplay() {
        guard !updating else { return }
        var next = display
        if let current { next.hand = current }
        if tableConfirmed, let table {
            var merged = table
            // Keep missing cells as muted historical readings, without using them for analysis.
            if let old = display.table {
                if merged.callCents == nil { merged.callCents = old.callCents }
                for i in merged.seats.indices where merged.seats[i].stackCents == nil {
                    if let seat = old.seats.first(where:{ $0.id == merged.seats[i].id && $0.isHero == merged.seats[i].isHero && abs($0.bounds.rect.midX-merged.seats[i].bounds.rect.midX) < 0.015 && abs($0.bounds.rect.midY-merged.seats[i].bounds.rect.midY) < 0.015 }) { merged.seats[i].stackCents = seat.stackCents }
                }
            }
            next.table = merged; next.tableTime = Date()
        }
        if let result { next.result = result; next.opponents = opponents; next.equityTime = Date() }
        if let ev = callEstimate {
            next.estimate = ev; next.context = automaticContext; next.estimateTime = Date()
            next.eligiblePotDollars = automatic ? automaticContext.map { Double($0.potCents)/100 } : Self.amount(potText)
        }
        display = next
    }
    private static func amount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20, trimmed.allSatisfy({ "0123456789.".contains($0) }),
              let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }
    deinit { worker?.cancel() }
}
