import SwiftUI
import PokerCore
import TableRecognition

struct HandAnalysisView: View {
    @ObservedObject var analysis: HandAnalysisModel
    @State private var showingDetails = false
    private func percent(_ value: Double) -> String { String(format:"%.1f%%",value*100) }
    private func dollars(_ value: Double) -> String { String(format:value < 0 ? "−$%.2f" : "+$%.2f",abs(value)) }
    private func money(_ cents: Int?) -> String { cents.map { String(format:"$%.2f",Double($0)/100) } ?? "—" }
    var body: some View {
        VStack(spacing:10) {
            HStack(spacing:10) {
                summary.frame(maxWidth:.infinity)
                handDetails.frame(width:344)
            }.frame(height:184)
            HStack(spacing:10) {
                ProbabilityCharts(result:analysis.display.result,requiredEquity:analysis.display.estimate?.requiredEquity,equityCurrent:analysis.equityIsCurrent,estimateCurrent:analysis.estimateIsCurrent)
                seatTable.frame(width:262)
            }.frame(height:DashboardStyle.chartHeight)
            statusLine.frame(height:24)
        }.frame(height:DashboardStyle.analysisHeight).transaction { $0.animation = nil }
    }
    private var summary: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                Text("HAND PROBABILITIES & EV").sectionLabel()
                Spacer()
                Image(systemName:analysis.isReview ? "clock.arrow.circlepath" : "waveform.path")
                    .foregroundStyle(analysis.isReview ? .orange : analysis.equityIsCurrent ? DashboardStyle.accent : .secondary)
                Text(analysis.isReview ? "WHAT-IF REVIEW" : analysis.equityIsCurrent ? "CURRENT READING" : "AWAITING READING").font(.system(size:9,weight:.semibold)).foregroundStyle(.secondary)
            }.frame(height:14)
            HStack(alignment:.top,spacing:18) {
                headline("Showdown equity",value:analysis.display.result.map { percent($0.equity) },note:"Expected share of the pot",current:analysis.equityIsCurrent,color:DashboardStyle.accent)
                    .help("Equity is your average share of the pot, including your fraction of tied pots.")
                headline(analysis.isReview ? "Last decision EV" : "Call / check EV",value:analysis.display.estimate.map { dollars($0.value) },note:analysis.display.estimate.map { "95%: \(dollars($0.lower)) to \(dollars($0.upper))" } ?? "95% sampling range: —",current:analysis.estimateIsCurrent,color:.primary)
                    .help("Incremental call EV = equity × (eligible pot + call) − call. Saved EV stays frozen in review.")
                headline("Call threshold",value:analysis.display.estimate.map { percent($0.requiredEquity) },note:"Equity needed to break even",current:analysis.estimateIsCurrent,color:.orange)
                    .help("Required calling equity = additional call ÷ (eligible pot + call). This is a cost threshold.")
            }.frame(height:58)
            HStack(spacing:8) {
                amount("Total pot",money(analysis.display.table?.potCents),current:analysis.tableConfirmed && analysis.table?.potCents != nil,input:!analysis.automatic,text:$analysis.potText,help:"Chips already in the pot before your new call.")
                amount("Additional call",money(analysis.display.table?.callCents),current:analysis.tableConfirmed && analysis.table?.callCents != nil,input:!analysis.automatic,text:$analysis.callText,help:"New chips needed to call; checking costs zero.")
                amount("Your stack",money(analysis.display.table?.hero?.stackCents),current:analysis.tableConfirmed && analysis.table?.hero?.stackCents != nil,help:"Your remaining chips, excluding chips already bet.")
                amount("Eligible pot",analysis.display.eligiblePotDollars.map { String(format:"$%.2f",$0) } ?? "—",current:analysis.estimateIsCurrent,help:"Pot used for the displayed EV, adjusted for supported unmatched wagers. Unwagered stacks are excluded.")
            }.frame(height:44)
            Text(analysis.simulationSummary).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85).frame(height:14,alignment:.leading).help(analysis.simulationSummary)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).frame(height:184).dashboardPanel()
    }
    private func headline(_ title: String,value: String?,note: String,current: Bool,color: Color) -> some View {
        VStack(alignment:.leading,spacing:3) {
            Text(title).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
            Text(value ?? "—").font(.system(size:27,weight:.semibold,design:.rounded)).monospacedDigit()
                .foregroundStyle(current ? color : .secondary).lineLimit(1).minimumScaleFactor(0.8).contentTransition(.identity)
            Text(note).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func amount(_ title: String,_ value: String,current: Bool,input: Bool = false,text: Binding<String> = .constant(""),help: String) -> some View {
        VStack(alignment:.leading,spacing:3) {
            Text(title).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1)
            ZStack(alignment:.leading) {
                Text(value).opacity(input ? 0 : 1).foregroundStyle(current ? .primary : .secondary)
                TextField("Dollars",text:text).textFieldStyle(.plain).opacity(input ? 1 : 0)
                    .disabled(!input || !analysis.hasCards).accessibilityHidden(!input)
            }.font(.system(size:15,weight:.medium,design:.rounded)).monospacedDigit().frame(height:18).contentTransition(.identity)
        }.padding(.horizontal,8).frame(maxWidth:.infinity,alignment:.leading).frame(height:44)
            .background(Color.white.opacity(0.035),in:RoundedRectangle(cornerRadius:7)).help(help)
    }
    private var handDetails: some View {
        let hand = analysis.display.hand
        let starting = HandDetails.startingClass(hand?.hole.map(\.card) ?? [])
        return VStack(alignment:.leading,spacing:8) {
            HStack {
                Text("HAND DETAILS").sectionLabel()
                Spacer()
                Text(starting ?? "—").font(.system(size:11,weight:.semibold,design:.monospaced))
                    .foregroundStyle(DashboardStyle.cyan).padding(.horizontal,8).padding(.vertical,3)
                    .background(DashboardStyle.cyan.opacity(0.1),in:Capsule())
                Button { showingDetails.toggle() } label: { Image(systemName:"ellipsis.circle").font(.system(size:15)) }
                    .buttonStyle(.plain).help("Improving cards, historical samples and details").accessibilityLabel("More hand details")
                    .popover(isPresented:$showingDetails,arrowEdge:.trailing) { extendedDetails.padding(20).frame(width:420) }
            }.frame(height:20)
            Text(analysis.details?.madeHand ?? (hand == nil ? "Waiting for cards" : "Preflop hand"))
                .font(.system(size:20,weight:.semibold,design:.rounded)).lineLimit(1).frame(height:25,alignment:.leading)
            Text(HandDetails.texture(hand?.board.map(\.card) ?? []))
                .font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2).frame(height:26,alignment:.topLeading)
            HStack(spacing:12) {
                detailMetric("Next card",analysis.details?.nextCardImprovement.map(percent) ?? "—")
                detailMetric("By river",analysis.details?.riverImprovement.map(percent) ?? "—")
                detailMetric("Improving cards",analysis.details.map { String($0.improvingCards.count) } ?? "—")
            }.frame(height:38)
            Text("Higher hand category · not guaranteed winning outs")
                .font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).frame(height:184).dashboardPanel()
            .help("Improvement means a higher hand category, including board-only improvements. It does not include merely improving a kicker or guarantee winning. Next card and by-river probabilities are exact on flop/turn.")
    }
    private func detailMetric(_ title: String,_ value: String) -> some View {
        VStack(alignment:.leading,spacing:3) {
            Text(title).font(.system(size:9)).foregroundStyle(.secondary)
            Text(value).font(.system(size:17,weight:.medium,design:.rounded)).monospacedDigit().contentTransition(.identity)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var extendedDetails: some View {
        let starting = HandDetails.startingClass(analysis.display.hand?.hole.map(\.card) ?? [])
        let reference = starting.flatMap { ReferenceData.shared?.classes[$0] }
        return VStack(alignment:.leading,spacing:14) {
            Text("Hand details · \(starting ?? "—")").font(.title3).fontWeight(.semibold)
            Text("Next-card category improvements").font(.headline)
            Text(analysis.details?.improvingCards.map(\.display).joined(separator:"  ") ?? "Available after a confirmed flop.")
            Text(analysis.details.map { "\($0.runouts.formatted()) exact remaining board runouts. These cards can improve the board alone; they are not clean winning outs." } ?? "A preflop hand has no made five-card category yet.")
            Divider()
            Text("Historical starting-hand context").font(.headline)
            Text(reference.map { "\($0.known.formatted()) revealed \(starting ?? "") samples; \($0.river.formatted()) with a complete board. Most common recorded finish: \($0.mostCommonFinish)." } ?? "Waiting for a recognized starting hand.")
            Text(ReferenceData.shared.map { "Curated archive: \($0.hands.formatted()) supported Hold’em histories. These historical revealed-hand samples are selected toward showdown and do not determine live equity." } ?? "Reference data unavailable.")
            Text("s = suited; o = offsuit. Live equity still assumes random legal opponent hands.").foregroundStyle(.secondary)
        }.font(.callout).fixedSize(horizontal:false,vertical:true)
    }
    private var seatTable: some View {
        VStack(spacing:5) {
            HStack {
                Text("PLAYER STACKS").sectionLabel()
                Spacer()
                Text(analysis.display.table.map { "\($0.activeOpponents.count) active" } ?? "— active")
                    .font(.system(size:9,weight:.medium)).foregroundStyle(DashboardStyle.accent)
            }.frame(height:16)
            HStack {
                Text("Seat").frame(width:28,alignment:.leading)
                Text("Stack").frame(maxWidth:.infinity,alignment:.trailing)
                Text("Effective").frame(width:58,alignment:.trailing)
                Text("Status").frame(width:56,alignment:.trailing)
            }.font(.system(size:9)).foregroundStyle(.tertiary).frame(height:12)
            VStack(spacing:0) {
                ForEach(0..<9,id:\.self) { i in
                    let seat = i == 0 ? analysis.display.table?.hero : analysis.display.table?.seats.filter { !$0.isHero }[safe:i-1]
                    let fresh = analysis.tableConfirmed && seat.flatMap { s in analysis.table?.seats.first(where:{ $0.id == s.id && $0.isHero == s.isHero }) }?.stackCents != nil
                    HStack(spacing:4) {
                        Text(i == 0 ? "You" : "P\(i)").foregroundStyle(i == 0 ? DashboardStyle.accent : .secondary).frame(width:28,alignment:.leading)
                        Text(money(seat?.stackCents)).foregroundStyle(fresh ? .primary : .secondary).frame(maxWidth:.infinity,alignment:.trailing)
                        Text(money(effective(seat))).foregroundStyle(fresh ? .primary : .secondary).frame(width:58,alignment:.trailing)
                        Text(activity(seat?.activity)).foregroundStyle(seat?.activity == .active ? DashboardStyle.accent : .secondary).frame(width:56,alignment:.trailing)
                    }.font(.system(size:10)).monospacedDigit().frame(height:18).contentTransition(.identity)
                        .help("\(i == 0 ? "You" : "Opponent screen position \(i)") · \(seat?.activity.label ?? "Unoccupied / unread")")
                }
            }
            Text("Effective = smaller remaining stack").font(.system(size:9)).foregroundStyle(.tertiary).frame(height:16)
        }.padding(12).frame(maxWidth:.infinity).frame(height:DashboardStyle.chartHeight).dashboardPanel()
    }
    private func activity(_ activity: SeatActivity?) -> String {
        switch activity { case .active: return "In hand"; case .folded: return "No cards"; case .sittingOut: return "Sit out"; case .waiting: return "Waiting"; case .unknown: return "Unclear"; case nil: return "—" }
    }
    private func effective(_ seat: TableSeat?) -> Int? {
        guard let seat, !seat.isHero, seat.activity == .active, let stack = seat.stackCents, let hero = analysis.display.table?.hero?.stackCents else { return nil }
        return min(stack,hero)
    }
    private var statusLine: some View {
        HStack(spacing:7) {
            Circle().fill(analysis.equityIsCurrent ? DashboardStyle.accent : .orange).frame(width:5,height:5)
            Text(analysis.displayStatus).font(.system(size:10,weight:.medium)).lineLimit(1)
            Image(systemName:"info.circle").foregroundStyle(.secondary).help(analysis.amountHelp)
            Text(analysis.amountHelp).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).help(analysis.amountHelp)
            Spacer(minLength:4)
            TimelineView(.periodic(from:.now,by:1)) { context in
                Text(analysis.estimateIsCurrent ? "Current EV" : analysis.display.estimateTime.map { "Last EV \(max(0,Int(context.date.timeIntervalSince($0))))s ago" } ?? "Waiting for EV")
                    .font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
            }.frame(width:125,alignment:.trailing)
        }.padding(.horizontal,4)
    }
}

struct AnalysisHelpButton: View {
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: { Image(systemName:"questionmark.circle") }
            .buttonStyle(.borderless).help("Metric definitions and reading assumptions").accessibilityLabel("Explain metrics")
            .popover(isPresented:$showing,arrowEdge:.bottom) {
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        Text("What the numbers mean").font(.title3).fontWeight(.semibold)
                        Text("Equity is your average pot share, including split-pot fractions. Win, tie and lose describe the showdown result; final-hand bars describe your best five cards, including playing the board.")
                        Text("Call EV = equity × (eligible pot + call) − call. Prior bets are sunk. The call threshold is call ÷ (eligible pot + call). A Check value assumes no later betting.")
                        Text("Remaining stacks are chips behind. Effective stack is the smaller of your stack and an opponent’s stack. Unwagered stacks do not enter the pot; side pots still need contribution history.")
                        Text("100,000 deals are locally generated possibilities for your current cards. The 95% bound covers simulation noise for each metric, not reading errors or opponent-range uncertainty. Opponents are random legal hands; future bets, folds and rake are excluded.")
                        Text("The 21.6 million historical hands supply separate starting-hand context. Revealed-card samples are biased and do not determine live equity.")
                        Text("Higher-category improvement is exact on the flop/turn. It may improve the board for everyone and is not a list of guaranteed winning outs.")
                        Text("After your cards disappear, saved-card review updates what-if equity with the visible board and remaining opponents. Last decision EV stays frozen. Board clearing/replacement ends updates; capture loss clears readings. Hidden cards cannot confirm hand identity.")
                        Text("Muted values are previous confirmed readings. Keep one entire table visible, including your cards, pot, player stacks and action controls. Seat labels identify screen positions, not player identities.")
                    }.font(.callout).padding(20).fixedSize(horizontal:false,vertical:true)
                }.frame(width:430,height:520)
            }
    }
}
