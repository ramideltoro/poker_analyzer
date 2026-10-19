import SwiftUI

struct CallThresholdPanel: View {
    @ObservedObject var analysis: HandAnalysisModel
    var height: CGFloat
    private var expanded: Bool { height >= 216 }
    private func percent(_ v: Double?) -> String { v.map { String(format:"%.1f%%",$0*100) } ?? "—" }
    private func money(_ v: Double?) -> String { v.map { String(format:"$%.2f",$0) } ?? "—" }
    private var edge: Double? {
        guard let equity = analysis.display.decisionEquity, let required = analysis.display.estimate?.requiredEquity else { return nil }
        return equity-required
    }
    private var comparison: String {
        guard let edge else { return "Waiting for a supported decision" }
        if analysis.display.decisionCallDollars == 0 { return "Check costs $0 · threshold is 0%" }
        let direction = edge >= 0 ? "above" : "below"
        let crossing = analysis.display.estimate.map { $0.lower < $0.upper && $0.lower <= 0 && $0.upper >= 0 } ?? false
        if abs(edge) < 1e-10 && !crossing { return "At break-even in this model" }
        return String(format:"%.1f pp %@ break-even",abs(edge)*100,direction)+(crossing ? " · sampling overlaps" : "")
    }
    private var odds: String {
        guard let call = analysis.display.decisionCallDollars, let pot = analysis.display.eligiblePotDollars else { return "Pot odds —" }
        return call == 0 ? "No additional call" : String(format:"Pot odds %.2f : 1",pot/call)
    }
    private var evFormula: String {
        guard let equity = analysis.display.decisionEquity, let call = analysis.display.decisionCallDollars,
              let pot = analysis.display.eligiblePotDollars, let ev = analysis.display.estimate else { return "Call EV: equity × (eligible pot + call) − call" }
        return "EV: \(percent(equity)) × \(money(pot+call)) − \(money(call)) ≈ \(String(format:"%+.2f",ev.value)) USD"
    }
    var body: some View {
        VStack(alignment:.leading,spacing:expanded ? 7 : 5) {
            HStack {
                Text("CALL THRESHOLD EXPLAINED").sectionLabel()
                Spacer()
                Text(analysis.estimateIsCurrent ? "CURRENT" : "SAVED / WAITING").font(.system(size:8,weight:.medium)).foregroundStyle(.secondary)
            }.frame(height:14)
            HStack(alignment:.firstTextBaseline) {
                Text(percent(analysis.display.estimate?.requiredEquity)).font(.system(size:expanded ? 35 : 25,weight:.semibold,design:.rounded))
                    .foregroundStyle(analysis.estimateIsCurrent ? .orange : .secondary).monospacedDigit()
                Text("minimum pot share").font(.system(size:expanded ? 12 : 10)).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment:.trailing,spacing:2) {
                    Text("Decision equity").font(.system(size:9)).foregroundStyle(.secondary)
                    Text(percent(analysis.display.decisionEquity)).font(.system(size:expanded ? 20 : 15,weight:.medium,design:.rounded)).monospacedDigit()
                }
            }.foregroundStyle(analysis.estimateIsCurrent ? .primary : .secondary).frame(height:expanded ? 45 : 33)
            Text("\(money(analysis.display.decisionCallDollars)) ÷ (\(money(analysis.display.eligiblePotDollars)) + \(money(analysis.display.decisionCallDollars))) = \(percent(analysis.display.estimate?.requiredEquity))")
                .font(.system(size:expanded ? 12 : 10,design:.monospaced)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8).frame(height:16)
                .help("Additional call divided by eligible pot plus that call. The pot includes earlier contributions and the opponent’s existing bet.")
            HStack {
                Text(odds)
                Spacer(minLength:8)
                Text(comparison).foregroundStyle(analysis.estimateIsCurrent ? ((edge ?? 0) >= 0 ? DashboardStyle.accent : DashboardStyle.loss) : .secondary)
            }.font(.system(size:expanded ? 11 : 9)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8).frame(height:15)
            if height >= 175 {
                Text("Call ÷ (eligible pot + call) is the equity needed for zero call EV. Compare it with expected pot share, including ties.")
                    .font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2).frame(height:30,alignment:.topLeading)
            }
            if height >= 230 {
                Text(evFormula).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8).frame(height:14)
            }
            Text(expanded ? "Above the threshold gives positive call EV only within this model. Future bets, folds, rake and range errors can change profitability. After folding, these decision inputs stay frozen." : "Single-pot model · no later bets or rake. Saved inputs stay frozen after a fold.")
                .font(.system(size:expanded ? 10 : 9)).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
        }.padding(expanded ? 14 : 10).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .frame(height:height).dashboardPanel().transaction { $0.animation = nil }
    }
}
