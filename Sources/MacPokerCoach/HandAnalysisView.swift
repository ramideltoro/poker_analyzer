import SwiftUI
import PokerCore

struct HandAnalysisView: View {
    @ObservedObject var analysis: HandAnalysisModel
    private func percent(_ value: Double) -> String { String(format:"%.1f%%",value*100) }
    private func dollars(_ value: Double) -> String { String(format:value < 0 ? "−$%.2f" : "+$%.2f",abs(value)) }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("EQUITY & CALL EV").font(.system(size:11,weight:.semibold)).tracking(1.2)
                Spacer()
                Stepper(value:Binding(get:{ analysis.opponents },set:{ analysis.setOpponents($0) }),in:1...8) {
                    Text("\(analysis.opponents) \(analysis.opponents == 1 ? "opponent" : "opponents") · random hands").font(.caption)
                }.fixedSize()
            }
            HStack(alignment:.top,spacing:36) {
                VStack(alignment:.leading,spacing:5) {
                    Text("Showdown equity").font(.caption).foregroundStyle(.secondary)
                    Text(analysis.result.map { percent($0.equity) } ?? "—").font(.system(size:30,weight:.semibold,design:.rounded)).monospacedDigit()
                    if analysis.calculating {
                        HStack { ProgressView().controlSize(.small); Text("Calculating locally…").font(.caption) }
                    } else if let result = analysis.result {
                        Text(result.exact ? "Exact · \(result.samples) possible opponent hands" : "\(result.samples) simulated deals · 95% sampling bound ±\(String(format:"%.1f",result.samplingBound*100)) pp")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else { Text(analysis.error ?? "Waiting for confirmed cards").font(.caption2).foregroundStyle(.secondary) }
                }.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.leading,spacing:5) {
                    Text("Call EV · showdown model").font(.caption).foregroundStyle(.secondary)
                    Text(analysis.callEstimate.map { dollars($0.value) } ?? "—").font(.system(size:30,weight:.semibold,design:.rounded)).monospacedDigit()
                    if let ev = analysis.callEstimate {
                        Text("Sampling range: \(dollars(ev.lower)) to \(dollars(ev.upper))").font(.caption2).foregroundStyle(.secondary)
                        Text("Break-even calling equity: \(percent(ev.requiredEquity))").font(.caption2).foregroundStyle(.secondary)
                    } else { Text("Enter pot and call below").font(.caption2).foregroundStyle(.secondary) }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack(spacing:18) {
                VStack(alignment:.leading,spacing:4) {
                    Text("Current pot before your call ($)").font(.caption)
                    TextField("e.g. 1.50",text:$analysis.potText).textFieldStyle(.roundedBorder)
                }
                VStack(alignment:.leading,spacing:4) {
                    Text("Your additional call ($)").font(.caption)
                    TextField("e.g. 0.50",text:$analysis.callText).textFieldStyle(.roundedBorder)
                }
            }.disabled(!analysis.hasCards)
            Text(analysis.amountHelp).font(.caption2).foregroundStyle(.secondary)
            Text("EV = equity × (pot + call) − call. Manual amounts reset when cards or opponent count change; update them when betting changes.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Assumes one shared pot and everyone reaching showdown, with no later bets or rake. Opponent ranges and recognition errors are outside the sampling bound.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(Color.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
    }
}
