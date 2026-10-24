import Foundation
import Combine
import PokerCore
import TableRecognition

@MainActor final class HandAnalysisModel: ObservableObject {
    typealias CalculateResponse = @Sendable ([Card],[OpponentRange],@escaping @Sendable () -> Bool) throws -> EquityResult
    typealias Calculate = @Sendable ([Card],[Card],Int,@escaping @Sendable () -> Bool) throws -> EquityResult
    @Published var position: PokerPosition = .unknown { didSet { if !updating { refreshForecast(); refreshRaiseResponse() }; refreshDisplay() } }
    @Published var preflopSituation: PreflopSituation = .unknown { didSet { if !updating { refreshRaiseResponse() }; refreshDisplay() } }
    @Published var bigBlindText = "" { didSet { if !updating { refreshRaiseResponse() }; refreshDisplay() } }
    @Published var raiseRange: RaiseRangePreset = .balanced { didSet { if !updating { refreshRaiseResponse(); refreshDisplay() } } }
    @Published private(set) var preflopEvidence=PreflopEvidence()
    @Published var raiseResponseResult: EquityResult?
    @Published var responseError: String?
    var responseKey: RaiseResponseRequest.Key?
    var responseWorker: Task<EquityResult,Error>?
    var responseGeneration=UUID()
    var responseCache=[RaiseResponseRequest.Key:EquityResult]()
    var responseCacheOrder=[RaiseResponseRequest.Key]()
    let calculateResponse: CalculateResponse
    private var contextHole: [Card]?
    private var positionStabilizer=PositionStabilizer()
    @Published private(set) var recognizedPosition: RecognizedPosition?
    @Published private(set) var recognizedBigBlind: Int?
    var preflopContext: PreflopContext {
        let prior=preflopSituation != .unknown ? "manual prior action" : effectiveSituation == .unknown ? "prior action unconfirmed" : "observed prior action"
        return PreflopContext(position:effectivePosition,situation:effectiveSituation,bigBlindCents:effectiveBigBlind,source:positionSource+"; "+prior,automaticSituation:preflopSituation == .unknown)
    }
    var showsLastAdvice: Bool {
        if current==nil, reading.confirmedHole.count==2,
           Set(reading.confirmedHole.map(\.card)) != Set(display.hand?.hole.map(\.card) ?? []) { return false }
        return (isReview || current == nil) && (display.lastAdvice ?? display.lastForecastAdvice) != nil
    }
    var showsLastForecast: Bool { showsLastAdvice && display.lastAdvice == nil }
    var isPlanning: Bool { automatic && current != nil && !isReview && !actionControlsConfirmed }
    var presentedAdvice: ActionAdvice {
        if showsLastAdvice { return (display.lastAdvice ?? display.lastForecastAdvice)! }
        if isPlanning {
            guard let table else { return ActionAdvice(title:"WAIT",reason:"Your cards are confirmed. Reading occupied seats and the current pot; hand recognition is not the missing input.",kind:nil,availability:.tableReading) }
            guard forecastConfirmed, let forecast else {
                let detail=table.incompleteReason ?? "Confirming consecutive player and wager readings."
                return ActionAdvice(title:"WAIT",reason:"Your cards are confirmed. "+detail+" Scanning continues; a forecast appears when those inputs agree.",kind:nil,availability:.tableReading)
            }
            if let hand=current, hand.board.isEmpty, var response=raiseResponseAdvice(for:forecast.table) { response.reason="Conditional plan. "+response.reason; return response }
            return forecast.advice(hole:current!.hole.map(\.card),board:current!.board.map(\.card),context:preflopContext)
        }
        return actionAdvice
    }
    @Published private(set) var reading=CardReadiness()
    var onDecisionUpdate: (() -> Void)?
    @Published private(set) var forecast: TurnForecast?
    @Published private(set) var forecastConfirmed=false
    @Published private(set) var equityTableConfirmed=false
    private var previousEquityTable: TableObservation?
    private var previousForecast: TurnForecast?
    private var forecastWorker: Task<EquityResult,Error>?
    private var forecastKey: Key?
    private var forecastGeneration=UUID()
    private var forecastRetryNotBefore=Date.distantPast
    @Published private(set) var result: EquityResult?
    @Published private(set) var opponents = 1
    @Published private(set) var calculating = false
    @Published private(set) var error: String?
    @Published private(set) var automatic = true
    @Published private(set) var planningTable: TableObservation?
    @Published private(set) var table: TableObservation?
    @Published private(set) var tableConfirmed = false
    @Published private(set) var actionControlsConfirmed = false
    @Published private(set) var display = AnalysisDisplay()
    @Published private(set) var details: RunoutDetails?
    private var detailsKey: CardsKey?
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
    var currentHand: LiveHand? { current }
    private var previousActionTable: TableObservation?
    private var tableStabilizer = TableReadingStabilizer()
    private var generation = UUID()
    private var worker: Task<EquityResult,Error>?
    private let calculate: Calculate
    private var failedKey: Key?
    private var failureCount = 0
    private var retryNotBefore = Date.distantPast

    init(calculate: @escaping Calculate = { hole,board,opponents,cancelled in
        try EquityEngine.calculate(hole:hole,board:board,opponents:opponents,cancelled:cancelled)
    },calculateResponse: @escaping CalculateResponse = { hole,ranges,cancelled in try RangeEquityEngine.calculate(hole:hole,ranges:ranges,cancelled:cancelled) }) { self.calculate = calculate; self.calculateResponse=calculateResponse }

    func setAutomatic(_ enabled: Bool) {
        guard enabled != automatic else { return }
        updating = true
        defer { updating = false; refreshDisplay() }
        automatic = enabled; potText = ""; callText = ""
        display.estimate = nil; display.context = nil; display.eligiblePotDollars = nil; display.estimateTime = nil
        display.decisionEquity = nil; display.decisionCallDollars = nil
        invalidate(); refreshAnalysis(); refreshForecast(); refreshRaiseResponse()
    }
    func setOpponents(_ count: Int) {
        guard !automatic, (1...8).contains(count), count != opponents else { return }
        updating = true
        defer { updating = false; refreshDisplay() }
        opponents = count; potText = ""; callText = ""; refreshAnalysis()
    }
    func update(_ hand: LiveHand?,table reading: TableObservation? = nil,recognition: CardReadiness? = nil,preflop: PreflopEvidence? = nil) {
        updating = true
        defer { updating = false; refreshDisplay() }
        current = hand; planningTable=reading
        if let recognition { self.reading=recognition }
        if let hand {
            let detailKey = CardsKey(hole:hand.hole.map(\.card),board:hand.board.map(\.card))
            if detailsKey != detailKey { detailsKey = detailKey; details = RunoutDetails(hole:detailKey.hole,board:detailKey.board) }
        }
        let next = hand.map { CardsKey(hole:$0.hole.map(\.card).sorted { $0.code < $1.code },board:$0.board.map(\.card).sorted { $0.code < $1.code }) }
        if let next, let previous = display.hand,
           !((hand?.isReview == true) && next.hole == previous.hole.map(\.card).sorted { $0.code < $1.code }),
           next != CardsKey(hole:previous.hole.map(\.card).sorted { $0.code < $1.code },board:previous.board.map(\.card).sorted { $0.code < $1.code }) {
            let retained = next.hole == previous.hole.map(\.card).sorted { $0.code < $1.code } && Set(previous.board.map(\.card)).isSubset(of:Set(next.board)) ? display.lastAdvice : nil
            let retainedForecast = retained != nil || (next.hole == previous.hole.map(\.card).sorted { $0.code < $1.code } && Set(previous.board.map(\.card)).isSubset(of:Set(next.board))) ? display.lastForecastAdvice : nil
            let shown=next.hole == previous.hole.map(\.card).sorted { $0.code < $1.code } && Set(previous.board.map(\.card)).isSubset(of:Set(next.board)) ? display.lastShownAdvice : nil
            let shownHole=shown == nil ? [] : display.lastShownHole
            display = AnalysisDisplay(); display.lastShownAdvice=shown; display.lastShownHole=shownHole; display.lastAdvice = retained; display.lastForecastAdvice = retainedForecast
        }
        if let next, hand?.isReview != true, next.hole != contextHole {
            contextHole = next.hole; position = .unknown; preflopSituation = .unknown; preflopEvidence=PreflopEvidence()
            positionStabilizer.reset()
        }
        if hand==nil || hand?.board.isEmpty != true { preflopEvidence=PreflopEvidence() }
        else if let preflop { preflopEvidence=PreflopEvidence(heroCalled:preflopEvidence.heroCalled || preflop.heroCalled,heroRaised:preflopEvidence.heroRaised || preflop.heroRaised,opponentRaises:max(preflopEvidence.opponentRaises,preflop.opponentRaises)) }
        if next != cardsKey {
            cardsKey = next; potText = ""; callText = ""; tableStabilizer.reset()
            previousActionTable = nil; previousForecast=nil; forecastConfirmed=false
        }
        equityTableConfirmed = hand != nil && reading.map { previousEquityTable?.agreesForEquity(with:$0)==true }==true
        previousEquityTable = hand == nil ? nil : reading
        actionControlsConfirmed = hand != nil && reading.map { next in previousActionTable?.agreesForActions(with:next) == true } == true
        previousActionTable = hand == nil ? nil : reading
        if hand == nil { table = nil; tableConfirmed = false; tableStabilizer.reset() }
        else {
            table = reading
            tableConfirmed = tableStabilizer.accept(reading) != nil
            if automatic, equityTableConfirmed, let reading, validOpponentCount(reading) {
                opponents = reading.activeOpponents.count
            }
        }
        if hand?.isReview != true, hand != nil || self.reading.confirmedHole.count==2 {
            positionStabilizer.update(reading)
            recognizedPosition=positionStabilizer.recognized; recognizedBigBlind=positionStabilizer.bigBlind
        } else if hand==nil {
            positionStabilizer.reset(); recognizedPosition=nil; recognizedBigBlind=nil
        }
        refreshAnalysis(); refreshForecast(isObservation:true); refreshRaiseResponse()
    }
    /// Stop, stale capture or permission loss must remove even presentation-only history.
    func reset() { reading=CardReadiness(); update(nil); display = AnalysisDisplay(); details = nil; detailsKey = nil; contextHole = nil; positionStabilizer.reset(); recognizedPosition=nil; recognizedBigBlind=nil; position = .unknown; preflopSituation = .unknown; bigBlindText = "" }
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
            if !automatic || (table.map { validOpponentCount($0) && $0.activeOpponents.count == opponents } == true && (equityTableConfirmed || key != nil)) {
                next = Key(hole:cardsKey.hole,board:cardsKey.board,opponents:opponents)
            }
        }
        guard next != key else { return }
        if next != failedKey { failedKey = nil; failureCount = 0; retryNotBefore = .distantPast }
        if next != nil, failedKey == next, Date() < retryNotBefore { return }
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
                self.failedKey = nil; self.failureCount = 0
                self.result = result; self.cachedResults[next] = result
                self.cacheOrder.removeAll { $0 == next }; self.cacheOrder.append(next)
                if self.cacheOrder.count > 16 { self.cachedResults.removeValue(forKey:self.cacheOrder.removeFirst()) }
            case .failure:
                self.key = nil; self.failedKey = next; self.failureCount += 1
                self.retryNotBefore = Date().addingTimeInterval(min(2,Double(self.failureCount)*0.25))
                self.error = "The calculation was interrupted. Retrying automatically while the current hand remains readable."
            }
            self.refreshForecast(); self.refreshDisplay()
        }
    }
    private func stopForecast() {
        forecastGeneration=UUID(); forecastWorker?.cancel(); forecastWorker=nil; forecastKey=nil
    }
    private func refreshForecast(isObservation: Bool = false) {
        guard isPlanning, let hand=current, let table,
              let next=TurnForecast.make(table,position:effectivePosition,board:hand.board.map(\.card),bigBlindCents:preflopContext.bigBlindCents) else {
            stopForecast(); forecast=nil; previousForecast=nil; forecastConfirmed=false; return
        }
        let stable=previousForecast.map { $0.assumedFoldIDs==next.assumedFoldIDs && $0.orderKnown==next.orderKnown && $0.table.agreesForAnalysis(with:next.table) }==true
        if isObservation { previousForecast=next; forecastConfirmed=stable && equityTableConfirmed }
        else { forecastConfirmed = forecastConfirmed && stable }
        var value=next
        guard forecastConfirmed, (1...8).contains(value.opponents) else { stopForecast(); forecast=value; return }
        let nextKey=Key(hole:hand.hole.map(\.card).sorted { $0.code<$1.code },board:hand.board.map(\.card).sorted { $0.code<$1.code },opponents:value.opponents)
        if let cached=cachedResults[nextKey] { stopForecast(); value.result=cached; forecast=value; return }
        if value.opponents==opponents {
            stopForecast(); value.result=result; value.calculating=calculating; forecast=value; return
        }
        if forecastKey==nextKey { value.result=forecast?.result; value.calculating=forecastWorker != nil; forecast=value; return }
        stopForecast(); forecast=value
        guard Date()>=forecastRetryNotBefore else { return }
        forecastKey=nextKey; let token=forecastGeneration, calculate=calculate
        value.calculating=true; forecast=value
        let task=Task.detached(priority:.utility) { try calculate(nextKey.hole,nextKey.board,nextKey.opponents,{ Task.isCancelled }) }
        forecastWorker=task
        Task { [weak self] in
            let outcome=await task.result
            guard let self, self.forecastGeneration==token, var latest=self.forecast else { return }
            self.forecastWorker=nil; latest.calculating=false
            switch outcome {
            case .success(let result):
                latest.result=result; self.cachedResults[nextKey]=result
                self.cacheOrder.removeAll { $0==nextKey }; self.cacheOrder.append(nextKey)
                if self.cacheOrder.count>16 { self.cachedResults.removeValue(forKey:self.cacheOrder.removeFirst()) }
            case .failure:
                self.forecastKey=nil; self.forecastRetryNotBefore=Date().addingTimeInterval(0.5)
            }
            self.forecast=latest; self.refreshDisplay()
        }
    }
    var automaticContext: StackCallContext? {
        guard current?.isReview != true, automatic, actionControlsConfirmed, tableConfirmed, let table, table.incompleteReason == nil,
              let pot = table.potCents, let quoted = table.callCents, let stack = table.hero?.stackCents else { return nil }
        var uncapped = quoted
        if quoted >= stack {
            // Some clients cap the Call label at hero's stack. Both visible street bets must resolve the true gap.
            guard table.activeOpponents.count == 1, let ownBet = table.hero?.betCents,
                  let opponentBet = table.activeOpponents.first?.betCents else { return nil }
            uncapped = max(0,opponentBet-ownBet)
            guard quoted == min(uncapped,stack) || quoted == uncapped else { return nil }
        }
        // A readable street wager is independent evidence for the Call label.
        // Do not price a raise-to OCR error as an additional call, or combine
        // money captured on opposite sides of a betting animation.
        let bets = table.seats.compactMap(\.betCents)
        guard bets.allSatisfy({ (0...100_000_000).contains($0) }), bets.reduce(0,+) <= pot else { return nil }
        if let own = table.hero?.betCents {
            let foeBets = table.activeOpponents.compactMap(\.betCents)
            let gap = max(0,(foeBets.max() ?? 0)-own)
            guard gap <= uncapped else { return nil }
            if foeBets.count == table.activeOpponents.count, gap != uncapped { return nil }
        }
        return try? StackCallContext(potCents:pot,uncappedCallCents:uncapped,heroStackCents:stack,
                                    opponentStackCents:table.activeOpponents.compactMap(\.stackCents),sidePots:table.sidePots)
    }
    var callEstimate: CallEstimate? {
        guard current?.isReview != true, let result else { return nil }
        if automatic { return try? automaticContext?.estimate(result) }
        guard let pot = Self.amount(potText), let call = Self.amount(callText) else { return nil }
        return try? CallEstimate(equity:result,potBeforeCall:pot,call:call)
    }
    var isReview: Bool { current?.isReview == true || display.hand?.isReview == true }
    var hasCards: Bool { current != nil }
    var amountHelp: String {
        if isReview { return "Saved hole cards: probabilities are what-if results against the visible remaining players. Call EV is frozen at the last decision; you have no claim to the pot after folding." }
        guard current != nil else { return reading.received ? reading.reason : "Waiting for confirmed cards." }
        if automatic {
            if isPlanning { return forecast?.estimate != nil ? "Conditional EV uses the stated fold assumption; live action awaits your turn." : "Equity runs before your turn; conditional dollar EV needs readable wagers, pot and stacks." }
            guard let table else { return "Reading the table · last confirmed values stay muted while updating." }
            guard tableConfirmed else { return "Confirming table amounts and player activity across consecutive frames…" }
            if let issue = table.incompleteReason { return issue }
            guard automaticContext != nil else { return "Checking pot / call consistency and all-in eligibility; waiting for current amounts and bets." }
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
        if current == nil { if reading.received { return reading.availability.label }; return display.hand == nil ? "Waiting for cards" : isReview ? "Review held · waiting for next confirmed hand / board" : "Updating · previous confirmed hand" }
        if isReview { return calculating ? "Review · updating what-if probabilities" : "Review · saved hole cards, last-decision EV" }
        if calculating { return "Calculating probabilities" }
        if callEstimate != nil { return "Live estimate" }
        if !automatic { return "Waiting for manual pot / call inputs" }
        if automatic, table == nil { return "Reading table · keeping previous values muted" }
        if isPlanning { return "Planning before your turn · \(forecast?.assumption ?? "confirming player activity")" }
        if automatic, table?.sidePots == true { return "Side pot · EV needs contribution history" }
        return "Updating table readings"
    }
    var simulationSummary: String {
        if current==nil, reading.received { return reading.confirmedHole.count==2 ? "Hole cards confirmed · reading the community cards before calculating." : reading.availability.label+" · scanning continues; prior values are muted." }
        if current != nil, display.result==nil { return "Cards confirmed · reading active opponents and calculating probabilities." }
        guard let value = display.result else { return "Waiting for a confirmed hand and opponent count." }
        let model = "vs \(display.opponents) random \(display.opponents == 1 ? "opponent" : "opponents")"
        return value.exact ? "Exact · \(value.samples.formatted()) deals · \(model)" : "\(value.samples.formatted()) deals · \(model) · 95% equity/outcome bound ±\(String(format:"%.2f",value.samplingBound*100)) pp\(value.categoriesExact ? " · exact categories" : "")"
    }
    func refreshDisplay() {
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
            next.decisionEquity = result?.equity
            next.decisionCallDollars = automatic ? automaticContext.map { Double($0.callCents)/100 } : Self.amount(callText)
            next.eligiblePotDollars = automatic ? automaticContext.map { Double($0.potCents)/100 } : Self.amount(potText)
        }
        if current?.isReview == false {
            if isPlanning, forecastConfirmed { let plan=presentedAdvice; if plan.kind != nil { next.lastForecastAdvice=plan } }
            let live = actionAdvice
            if live.kind != nil { next.lastAdvice = live; if live.basis=="RAISE RESPONSE", let value=raiseResponseResult { next.decisionEquity=value.equity } }
        }
        let shown=decisionAdvice
        if shown.kind != nil {
            next.lastShownAdvice=shown
            let holes=current?.hole.map(\.card) ?? reading.confirmedHole.map(\.card)
            if !holes.isEmpty { next.lastShownHole=holes }
        }
        display = next; onDecisionUpdate?()
    }
    private static func amount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20, trimmed.allSatisfy({ "0123456789.".contains($0) }),
              let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }
    deinit { worker?.cancel(); forecastWorker?.cancel(); responseWorker?.cancel() }
}
