import SwiftUI
import PokerCore
import TableRecognition

struct HandAnalysisView: View {
    @ObservedObject var analysis: HandAnalysisModel
    private func percent(_ value: Double) -> String { String(format:"%.1f%%",value*100) }
    private func dollars(_ value: Double) -> String { String(format:value < 0 ? "−$%.2f" : "+$%.2f",abs(value)) }
    private func money(_ cents: Int?) -> String { cents.map { String(format:"$%.2f",Double($0)/100) } ?? "—" }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("HAND PROBABILITIES & EV").font(.system(size:11,weight:.semibold)).tracking(1.2)
                Spacer()
                Toggle("Read table automatically",isOn:Binding(get:{ analysis.automatic },set:{ analysis.setAutomatic($0) })).toggleStyle(.switch).controlSize(.small).fixedSize()
            }.frame(height:24)
            statusLine
            HStack(alignment:.top,spacing:24) {
                VStack(alignment:.leading,spacing:6) {
                    Text("Showdown equity · expected pot share").font(.caption).foregroundStyle(.secondary)
                    number(analysis.display.result.map { percent($0.equity) },current:analysis.equityIsCurrent)
                    Text("Includes your share of tied pots.").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.leading,spacing:6) {
                    Text(analysis.isReview ? "Last decision EV · saved dollars" : "Call / check EV · expected dollars").font(.caption).foregroundStyle(.secondary)
                    number(analysis.display.estimate.map { dollars($0.value) },current:analysis.estimateIsCurrent)
                    Text(analysis.display.estimate.map { "95% sampling range: \(dollars($0.lower)) to \(dollars($0.upper))" } ?? "Sampling range: —")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.frame(height:92,alignment:.top)
            Text(analysis.simulationSummary).font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(height:28,alignment:.topLeading).frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:12) {
                amountCell("Current total pot",value:money(analysis.display.table?.potCents),current:potCurrent,manual:!analysis.automatic,text:$analysis.potText,detail:"All chips already in the pot, before your new call.")
                amountCell("Additional call",value:money(analysis.display.table?.callCents),current:callCurrent,manual:!analysis.automatic,text:$analysis.callText,detail:"New chips needed to call. Check means zero.")
                readout("Your remaining stack",money(analysis.display.table?.hero?.stackCents),current:analysis.tableConfirmed && analysis.table?.hero?.stackCents != nil,detail:"Chips you have behind, excluding money already bet.")
                readout("Eligible pot",analysis.display.eligiblePotDollars.map { String(format:"$%.2f",$0) } ?? "—",current:analysis.estimateIsCurrent,detail:"Pot used for EV after any supported unmatched-wager adjustment. Unwagered stacks are excluded.")
            }.frame(height:70)
            ProbabilityCharts(result:analysis.display.result,requiredEquity:analysis.display.estimate?.requiredEquity,equityCurrent:analysis.equityIsCurrent,estimateCurrent:analysis.estimateIsCurrent)
            HStack {
                Text("Opponents / random hands").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(analysis.display.table.map { "\($0.activeOpponents.count) detected" } ?? "— detected").font(.caption).monospacedDigit().frame(width:100,alignment:.trailing)
                Stepper(value:Binding(get:{ analysis.opponents },set:{ analysis.setOpponents($0) }),in:1...8) { Text("Manual: \(analysis.opponents)").font(.caption) }.fixedSize().disabled(analysis.automatic)
            }.frame(height:26)
            handDetails
            seatTable
            Text(analysis.amountHelp).font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(height:34,alignment:.topLeading).frame(maxWidth:.infinity,alignment:.leading)
            metricGuide
        }.padding(18).background(Color.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
            .transaction { $0.animation = nil }
    }
    private var statusLine: some View {
        HStack(spacing:8) {
            Circle().fill(analysis.estimateIsCurrent ? Color.mint : Color.orange).frame(width:6,height:6)
            Text(analysis.displayStatus).font(.caption).lineLimit(1)
            Spacer(minLength:8)
            TimelineView(.periodic(from:.now,by:1)) { context in
                let age = analysis.display.estimateTime.map { max(0,Int(context.date.timeIntervalSince($0))) }
                Text(analysis.estimateIsCurrent ? "Current reading" : age.map { "Last EV \($0)s ago · muted" } ?? "Waiting for values")
                    .font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(width:205,alignment:.trailing)
        }.frame(height:24).padding(.horizontal,10).background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:6))
    }
    private var potCurrent: Bool { analysis.tableConfirmed && analysis.table?.potCents != nil }
    private var callCurrent: Bool { analysis.tableConfirmed && analysis.table?.callCents != nil }
    private func number(_ value: String?,current: Bool) -> some View {
        Text(value ?? "—").font(.system(size:30,weight:.semibold,design:.rounded)).monospacedDigit()
            .foregroundStyle(current ? .primary : .secondary).frame(height:38,alignment:.leading).contentTransition(.identity)
    }
    private func amountCell(_ title: String,value: String,current: Bool,manual: Bool,text: Binding<String>,detail: String) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            ZStack(alignment:.leading) {
                Text(value).opacity(manual ? 0 : 1).foregroundStyle(current ? .primary : .secondary)
                TextField("Dollars",text:text).textFieldStyle(.plain).opacity(manual ? 1 : 0).disabled(!manual || !analysis.hasCards).accessibilityHidden(!manual)
            }.font(.system(size:18,weight:.medium,design:.rounded)).monospacedDigit().frame(height:24).contentTransition(.identity)
        }.padding(10).frame(maxWidth:.infinity,alignment:.leading).frame(height:70)
            .background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:8)).help(detail)
    }
    private func readout(_ title: String,_ value: String,current: Bool,detail: String) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size:18,weight:.medium,design:.rounded)).monospacedDigit().foregroundStyle(current ? .primary : .secondary).frame(height:24).contentTransition(.identity)
        }.padding(10).frame(maxWidth:.infinity,alignment:.leading).frame(height:70)
            .background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:8)).help(detail)
    }
    private var seatTable: some View {
        VStack(spacing:0) {
            HStack {
                Text("Detected seats").frame(maxWidth:.infinity,alignment:.leading)
                Text("Remaining").frame(width:100,alignment:.trailing)
                Text("Effective vs you").frame(width:116,alignment:.trailing)
                Text("Activity").frame(width:152,alignment:.trailing)
            }.font(.caption2).foregroundStyle(.secondary).frame(height:26)
            ForEach(0..<9,id:\.self) { i in
                let seat = i == 0 ? analysis.display.table?.hero : analysis.display.table?.seats.filter { !$0.isHero }[safe:i-1]
                let fresh = analysis.tableConfirmed && seat.flatMap { s in analysis.table?.seats.first(where:{ $0.id == s.id && $0.isHero == s.isHero }) }?.stackCents != nil
                HStack {
                    Text(i == 0 ? "You" : "Opponent position \(i)").frame(maxWidth:.infinity,alignment:.leading)
                    Text(money(seat?.stackCents)).foregroundStyle(fresh ? .primary : .secondary).frame(width:100,alignment:.trailing)
                    Text(money(effective(seat))).foregroundStyle(fresh ? .primary : .secondary).frame(width:116,alignment:.trailing)
                    Text(seat?.activity.label ?? "—").foregroundStyle(.secondary).frame(width:152,alignment:.trailing)
                }.font(.system(size:11)).monospacedDigit().frame(height:24).contentTransition(.identity)
            }
        }.padding(.horizontal,12).padding(.vertical,6).background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:8))
    }
    private func effective(_ seat: TableSeat?) -> Int? {
        guard let seat, !seat.isHero, seat.activity == .active, let stack = seat.stackCents, let hero = analysis.display.table?.hero?.stackCents else { return nil }
        return min(stack,hero)
    }
    private var handDetails: some View {
        let hole = analysis.display.hand?.hole.map(\.card) ?? []
        let board = analysis.display.hand?.board.map(\.card) ?? []
        let starting = HandDetails.startingClass(hole)
        let reference = starting.flatMap { ReferenceData.shared?.classes[$0] }
        return VStack(alignment:.leading,spacing:7) {
            Text("HAND DETAILS · \(starting ?? "—")").font(.system(size:10,weight:.semibold)).tracking(1)
            Text("Current hand: \(analysis.details?.madeHand ?? "Two hole cards / waiting for flop")").font(.caption)
            Text(HandDetails.texture(board)).font(.caption2).foregroundStyle(.secondary)
            Text("Higher category next card: \(analysis.details?.nextCardImprovement.map(percent) ?? "—") · by river: \(analysis.details?.riverImprovement.map(percent) ?? "—")")
                .font(.caption).monospacedDigit()
            Text(analysis.details.map { "\($0.improvingCards.count) category-improving cards · \($0.runouts) exact runouts. These can improve the board alone; they are not guaranteed winning outs." } ?? "Exact improvement probabilities become available on the flop and turn.")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(height:30,alignment:.topLeading)
            Text("Next-card improvements: \(analysis.details?.improvingCards.map(\.display).joined(separator:" ") ?? "—")")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(height:30,alignment:.topLeading)
            Text(reference.map { "Historical \(starting ?? "") samples: \($0.known.formatted()) revealed hands · \($0.river.formatted()) with a full board. Most common recorded finish: \($0.mostCommonFinish)." } ?? "Historical starting-hand samples: —")
                .font(.caption2).monospacedDigit().lineLimit(1)
            Text(ReferenceData.shared.map { "Curated archive: \($0.hands.formatted()) Hold’em hands. Revealed-card samples are biased and historical; they do not determine live equity." } ?? "Reference archive is unavailable in this build.")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(height:30,alignment:.topLeading)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).frame(height:250,alignment:.topLeading)
            .background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:8))
    }
    private var metricGuide: some View {

        VStack(alignment:.leading,spacing:7) {
            Text("WHAT THE NUMBERS MEAN").font(.system(size:10,weight:.semibold)).tracking(1)
            Text("Equity is your average pot share. Win/tie/lose describe the showdown result; final-hand bars describe your best five cards, even when the board supplies them.")
            Text("Call EV is equity × (eligible pot + call) − call, measured from this decision. Prior bets are sunk. The call threshold is the equity needed for zero EV. A Check value assumes no later betting.")
            Text("Remaining stacks are chips behind. Effective stack is the smaller of your stack and that opponent’s stack; it limits possible future betting, not the money already in the pot.")
            Text("The 95% bound covers simulation noise for each metric, not reading errors or opponent-range uncertainty. Opponents are random legal hands; future bets, folds and rake are excluded. Side pots still need contribution history.")
            Text("Saved-card review keeps your confirmed hole cards after they disappear and updates what-if equity with the visible board and remaining opponents. Last decision EV stays frozen. Board clearing or replacement ends updates; capture loss clears readings. Hidden cards cannot confirm hand identity, so review is hypothetical.")
        }.font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
    }
}
