import SwiftUI
import PokerCore

struct CallThresholdPanel: View {
    @ObservedObject var analysis: HandAnalysisModel
    var height: CGFloat
    @State private var scenarios = false
    @State private var preflopSetup = false
    private func money(_ v: Double?) -> String { v.map { String(format:"$%.2f",$0) } ?? "—" }
    private var price: DecisionPrice? {
        if analysis.isPlanning {
            guard let f=analysis.forecast, let q=f.result?.equity, let c=f.callCents, let p=f.context?.potCents else { return nil }
            return try? DecisionPrice(equity:q,pot:Double(p)/100,call:Double(c)/100)
        }
        guard let q = analysis.display.decisionEquity, let p = analysis.display.eligiblePotDollars, let c = analysis.display.decisionCallDollars else { return nil }
        return try? DecisionPrice(equity:q,pot:p,call:c)
    }
    private var odds: String { guard let p = price else { return "—" }; return p.call == 0 ? "Free" : String(format:"%.2f : 1",p.pot/p.call) }
    private var edge: String {
        guard let q = price?.equity, let required = analysis.display.estimate?.requiredEquity else { return "—" }
        return String(format:"%+.1f pp",(q-required)*100)
    }
    private var maxCall: String {
        guard let price else { return "—" }
        let cap = analysis.display.table?.hero?.stackCents.map { Double($0)/100 }
        let maximum = price.maximumCall.map { min($0,cap ?? $0) } ?? cap
        return maximum.map { money(floor($0*100+1e-9)/100) } ?? "No cap"
    }
    private var spr: String {
        guard let context = (analysis.isPlanning ? analysis.forecast?.context : analysis.display.context), let effective = context.effectiveStacks.max(), context.potCents > 0 else { return "—" }
        return String(format:"%.1f ×",Double(effective)/Double(context.potCents))
    }
    var body: some View {
        let advice = analysis.presentedAdvice
        let large = height >= 210
        let tint = advice.kind == .fold ? DashboardStyle.loss : advice.kind == .raise ? DashboardStyle.cyan : DashboardStyle.accent
        VStack(alignment:.leading,spacing:large ? 6 : 3) {
            HStack {
                Text(analysis.showsLastForecast ? "LAST FORECAST" : analysis.showsLastAdvice ? "LAST SUGGESTION" : analysis.isPlanning ? "BEFORE YOUR TURN" : advice.kind == nil ? "DECISION STATUS" : "SUGGESTED ACTION").sectionLabel()
                Spacer()
                Button("Position") { preflopSetup = true }.font(.system(size:9)).buttonStyle(.plain).foregroundStyle(DashboardStyle.cyan)
                    .popover(isPresented:$preflopSetup) { PreflopSetup(analysis:analysis).padding(20).frame(width:390) }
                Button { scenarios = true } label: { Image(systemName:"info.circle") }.buttonStyle(.plain)
                    .help("Decision assumptions and raise scenarios")
                    .popover(isPresented:$scenarios,arrowEdge:.trailing) { DecisionScenarios(analysis:analysis).padding(20).frame(width:470) }
            }.frame(height:12)
            HStack(alignment:.firstTextBaseline) {
                Text(advice.kind?.label.uppercased() ?? advice.state.label).font(.system(size:advice.kind == nil ? (large ? 20 : 16) : (large ? 32 : 23),weight:.bold,design:.rounded)).foregroundStyle(advice.kind == nil ? .secondary : tint)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityLabel(advice.kind.map { "\(analysis.showsLastAdvice ? "Last suggestion" : "Suggested action"): \($0.label)" } ?? "\(advice.state.label). No suggested action available")
                Spacer(minLength:4)
                Text(analysis.isPlanning ? "CONDITIONAL" : advice.marginal ? "LOW CONFIDENCE" : advice.kind != nil ? advice.basis : "STATUS")
                    .font(.system(size:8,weight:.semibold)).foregroundStyle(.secondary)
            }.frame(height:large ? 37 : 26)
            Text(advice.reason).font(.system(size:large ? 12 : 10)).foregroundStyle(.secondary).lineLimit(3)
                .fixedSize(horizontal:false,vertical:true).frame(height:large ? 48 : 40,alignment:.topLeading).help(advice.reason)
            HStack(spacing:5) {
                metric("Pot odds",odds,"Eligible pot divided by your additional call. A 3:1 price requires 25% equity in this model.")
                metric(analysis.isPlanning ? "Plan equity" : "Equity edge",analysis.isPlanning ? analysis.forecast?.result.map { String(format:"%.1f%%",$0.equity*100) } ?? "—" : edge,analysis.isPlanning ? "Conditional equity against players left after the stated assumed folds. The headline showdown equity retains every actually active opponent." : "Your decision equity minus required calling equity, in percentage points.")
                metric("Max call*",maxCall,"Break-even extra call at the current pot: equity × pot ÷ (1 − equity), capped at your readable stack. Assumes the same equity and no later betting or rake.")
                metric("Eff. SPR",spr,"Largest effective remaining stack matchup divided by eligible pot. Multiway matchups differ; this is future exposure, not extra money in the pot.")
            }.frame(height:large ? 36 : 26)
            if large {
                Text(price.map { "Call price: \(money($0.call)) · minimum pot \(money($0.minimumPot.map { max(0,ceil($0*100-1e-9)/100) }))" } ?? "Waiting for current decision inputs")
                    .font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8).frame(height:14)
            }
            Text(analysis.isPlanning ? analysis.forecast?.assumption ?? "Assumptions pending; scanning continues." : "Value / price heuristics · actual calling ranges and future responses unknown.")
                .font(.system(size:8)).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.8).frame(height:12)
        }.padding(8).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).frame(height:height)
            .dashboardPanel().transaction { $0.animation = nil }
    }
    private func metric(_ label: String,_ value: String,_ definition: String) -> some View {
        VStack(alignment:.leading,spacing:2) {
            Text(label).font(.system(size:8)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size:height >= 210 ? 18 : 13,weight:.medium,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                .foregroundStyle((analysis.isPlanning ? analysis.forecastConfirmed : analysis.estimateIsCurrent) ? .primary : .secondary)
        }.frame(maxWidth:.infinity,alignment:.leading).help(definition)
    }
}

struct DecisionScenarios: View {
    @ObservedObject var analysis: HandAnalysisModel
    @State private var risk = ""
    @State private var added = ""
    @State private var calledEquity = ""
    @State private var foldRate = ""
    private func money(_ v: Double?) -> String { v.map { String(format:"$%.2f",$0) } ?? "—" }
    private var scenario: RaiseScenario? {
        guard let pot = analysis.display.eligiblePotDollars, let r = Double(risk), let a = Double(added),
              let q = Double(calledEquity), let f = Double(foldRate) else { return nil }
        return try? RaiseScenario(pot:pot,risk:r,opponentAdds:a,equityWhenCalled:q/100,foldFrequency:f/100)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Call, fold and raise prices").font(.title3).fontWeight(.semibold)
            Text("\(analysis.estimateIsCurrent ? "Current" : "Saved / waiting") eligible pot: \(money(analysis.display.eligiblePotDollars)) · additional call: \(money(analysis.display.decisionCallDollars))")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Text("A call buys a share of money already in the pot. For a $1 call with 25% equity, the pot needs to be $3 before your call. A larger pot improves the call’s price; a smaller pot makes it worse in this simplified model.")
            Text("Before your turn, the forecast assumes readable players between the current actor and you fold. All-ins remain. Without reliable turn order, all players remain. Actual calls, raises and folds update the plan; forecast actions are not legal-action confirmations or observed folds. Position must be confirmed for first-in charts. Headline equity retains actual active players; Plan equity uses projected players. Ranges stay uniform random; a raise is not an inferred opponent range.")
            Text("Check-down EV assumes every counted opponent stays to showdown with no more chips added. A value raise can change who continues and how much they pay, so the AA/KK preflop rule is separate. Max call is not a maximum raise size. Opponents’ actual ranges remain unknown.")
            Text("Folding costs $0 more from this decision. Money already bet is sunk. A negative call EV favors folding over calling in this model, but checking is free when offered.")
            Divider()
            Text("Heads-up raise scenario").font(.headline)
            Text("This is a what-if calculator, not a recommended or verified legal raise. Enter fresh assumptions. Calling ranges are usually stronger than random hands, so showdown equity is not filled in automatically.")
            Grid(alignment:.leading,horizontalSpacing:12,verticalSpacing:8) {
                row("Your extra chips now ($)",text:$risk)
                row("Opponent adds if calling ($)",text:$added)
                row("Your equity when called (%)",text:$calledEquity)
                row("Opponent folds (%)",text:$foldRate)
            }
            HStack {
                metric("Raise EV",scenario.map { String(format:"%+.2f USD",$0.ev) } ?? "—")
                metric("Min. pot",scenario.flatMap(\.minimumPot).map { money(ceil($0*100-1e-9)/100) } ?? "—")
                metric("Break-even folds",scenario.flatMap(\.requiredFoldFrequency).map { String(format:"%.1f%%",$0*100) } ?? "—")
            }.monospacedDigit().frame(height:45)
            Text("EV = fold% × pot + (1 − fold%) × [called equity × (pot + your extra chips + their extra chips) − your extra chips]. No later betting or rake. Extra chips include your call; they are not a raise-to amount. Respect available stacks and table minimum raises. Multiway raises need more outcomes.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Pot odds explained · PokerStars Learn",destination:URL(string:"https://www.pokerstars.com/poker/learn/lesson/pot-odds/")!)
        }.font(.callout).fixedSize(horizontal:false,vertical:true)
    }
    private func row(_ label: String,text: Binding<String>) -> some View {
        GridRow { Text(label); TextField("Enter assumption",text:text).textFieldStyle(.roundedBorder).frame(width:150) }
    }
    private func metric(_ title: String,_ value: String) -> some View {
        VStack(alignment:.leading,spacing:3) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline) }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
