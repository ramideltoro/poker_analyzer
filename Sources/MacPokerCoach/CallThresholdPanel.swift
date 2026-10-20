import SwiftUI
import PokerCore

struct CallThresholdPanel: View {
    @ObservedObject var analysis: HandAnalysisModel
    var height: CGFloat
    @State private var scenarios = false
    private func percent(_ v: Double?) -> String { v.map { String(format:"%.1f%%",$0*100) } ?? "—" }
    private func money(_ v: Double?) -> String { v.map { String(format:"$%.2f",$0) } ?? "—" }
    private var price: DecisionPrice? {
        guard let q = analysis.display.decisionEquity, let p = analysis.display.eligiblePotDollars,
              let c = analysis.display.decisionCallDollars else { return nil }
        return try? DecisionPrice(equity:q,pot:p,call:c)
    }
    private var minimum: String {
        guard let price else { return "—" }
        return price.minimumPot.map { money(ceil($0*100-1e-9)/100) } ?? "No finite pot"
    }
    private var callLine: String {
        guard let price else { return "Call: waiting for confirmed equity, pot and call." }
        if price.call == 0 { return "Check is free. No extra chips needed." }
        guard let needed = price.minimumPot else { return "Call: zero equity cannot justify a paid call." }
        if let estimate = analysis.display.estimate, estimate.lower < estimate.upper, estimate.lower <= 0, estimate.upper >= 0 {
            return "Near break-even: simulation uncertainty crosses $0 EV."
        }
        let short = max(0,needed-price.pot)
        if short > 0.005 { return "Call needs \(money(short)) more in the pot (same equity)." }
        return "Current pot meets the call price in this model."
    }
    var body: some View {
        let large = height >= 265
        VStack(alignment:.leading,spacing:large ? 6 : 3) {
            HStack {
                Text("IS THE CALL WORTH ITS PRICE?").sectionLabel().lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength:4)
                Button { scenarios = true } label: { Image(systemName:"slider.horizontal.3") }
                    .buttonStyle(.plain).help("Explore call and raise prices")
                    .popover(isPresented:$scenarios,arrowEdge:.trailing) { DecisionScenarios(analysis:analysis).padding(20).frame(width:470) }
            }.frame(height:14)
            HStack(alignment:.firstTextBaseline,spacing:8) {
                Text(minimum).font(.system(size:large ? 32 : 24,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    .foregroundStyle(analysis.estimateIsCurrent ? DashboardStyle.accent : .secondary)
                VStack(alignment:.leading,spacing:1) {
                    Text("estimated min. pot to call").font(.system(size:large ? 12 : 10,weight:.medium))
                    Text("for a \(money(price?.call)) call at \(percent(price?.equity)) equity")
                        .font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
            }.frame(height:large ? 43 : 33)
            Text(callLine).font(.system(size:large ? 12 : 10)).foregroundStyle(.secondary)
                .lineLimit(2).frame(height:large ? 30 : 25,alignment:.topLeading)
            HStack(spacing:8) {
                Text("Fold: $0 extra; give up the pot.")
                Spacer(minLength:0)
                Button("Raise: explore →") { scenarios = true }.buttonStyle(.plain).foregroundStyle(DashboardStyle.cyan)
            }.font(.system(size:large ? 11 : 9)).lineLimit(1).frame(height:14)
            if height >= 205 {
                Text("You need \(percent(analysis.display.estimate?.requiredEquity)) equity to call this pot. Your estimate is \(percent(price?.equity)).")
                    .font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2).frame(height:28,alignment:.topLeading)
            }
            if large {
                Text("Minimum pot = call × (1 − equity) ÷ equity. A raise has no single pot cutoff: the size, callers and folds matter.")
                    .font(.system(size:11)).foregroundStyle(.secondary).lineLimit(3).frame(height:42,alignment:.topLeading)
            }
            Text(analysis.isReview ? "SAVED decision price · folding ends your claim to this pot." : "One-pot price estimate · random hands, no later bets or rake. Not an action recommendation.")
                .font(.system(size:9)).foregroundStyle(.tertiary).lineLimit(2).frame(height:22,alignment:.topLeading)
        }.padding(10).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).frame(height:height)
            .dashboardPanel().transaction { $0.animation = nil }
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
