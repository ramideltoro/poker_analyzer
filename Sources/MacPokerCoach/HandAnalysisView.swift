import SwiftUI
import PokerCore
import TableRecognition

struct HandAnalysisView: View {
    @ObservedObject var analysis: HandAnalysisModel
    private func percent(_ value: Double) -> String { String(format:"%.1f%%",value*100) }
    private func dollars(_ value: Double) -> String { String(format:value < 0 ? "−$%.2f" : "+$%.2f",abs(value)) }
    private func money(_ cents: Int?) -> String { cents.map { String(format:"$%.2f",Double($0)/100) } ?? "—" }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("EQUITY & EV").font(.system(size:11,weight:.semibold)).tracking(1.2)
                Spacer()
                Toggle("Read table automatically",isOn:Binding(get:{ analysis.automatic },set:{ analysis.setAutomatic($0) })).toggleStyle(.switch).controlSize(.small).fixedSize()
            }
            HStack {
                if analysis.automatic {
                    Text(analysis.table.map { "\($0.activeOpponents.count) visible active \($0.activeOpponents.count == 1 ? "opponent" : "opponents") · random hands" } ?? "Detecting active opponents…").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(analysis.tableConfirmed ? "Table confirmed" : "Waiting for stable table").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Stepper(value:Binding(get:{ analysis.opponents },set:{ analysis.setOpponents($0) }),in:1...8) {
                        Text("\(analysis.opponents) \(analysis.opponents == 1 ? "opponent" : "opponents") · random hands").font(.caption)
                    }.fixedSize()
                }
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
                    } else { Text(analysis.error ?? "Waiting for confirmed cards and opponents").font(.caption2).foregroundStyle(.secondary) }
                }.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.leading,spacing:5) {
                    Text("Call / check EV · showdown model").font(.caption).foregroundStyle(.secondary)
                    Text(analysis.callEstimate.map { dollars($0.value) } ?? "—").font(.system(size:30,weight:.semibold,design:.rounded)).monospacedDigit()
                    if let ev = analysis.callEstimate {
                        Text("Sampling range: \(dollars(ev.lower)) to \(dollars(ev.upper))").font(.caption2).foregroundStyle(.secondary)
                        Text("Break-even calling equity: \(percent(ev.requiredEquity))").font(.caption2).foregroundStyle(.secondary)
                    } else { Text(analysis.automatic ? "Analysis incomplete" : "Enter pot and call below").font(.caption2).foregroundStyle(.secondary) }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if analysis.automatic {
                HStack(spacing:28) {
                    metric("Total pot",money(analysis.table?.potCents))
                    metric("Additional call",money(analysis.table?.callCents))
                    metric("Your remaining stack",money(analysis.table?.hero?.stackCents))
                    if let context = analysis.automaticContext, context.unmatchedCents > 0 {
                        metric("Eligible pot",money(context.potCents))
                    }
                    Spacer(minLength:0)
                }
                if let table = analysis.table, !table.seats.isEmpty {
                    VStack(spacing:7) {
                        HStack {
                            Text("Detected seat").frame(maxWidth:.infinity,alignment:.leading)
                            Text("Remaining stack").frame(width:130,alignment:.trailing)
                            Text("Effective vs you").frame(width:130,alignment:.trailing)
                            Text("Visible activity").frame(width:130,alignment:.trailing)
                        }.font(.caption2).foregroundStyle(.secondary)
                        ForEach(table.seats) { seat in
                            HStack {
                                Text(seat.isHero ? "You" : "Position \(seat.id)").frame(maxWidth:.infinity,alignment:.leading)
                                Text(money(seat.stackCents)).frame(width:130,alignment:.trailing)
                                Text(!seat.isHero && seat.activity == .active ? money(effective(seat,table:table)) : "—").frame(width:130,alignment:.trailing)
                                Text(seat.activity.label).frame(width:130,alignment:.trailing)
                            }.font(.caption).monospacedDigit()
                        }
                    }.padding(12).background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:8))
                    Text("Positions identify detected screen locations. Active opponents are counted from visible card backs; other seats do not enter equity.").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
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
            }
            Text(analysis.amountHelp).font(.caption2).foregroundStyle(.secondary)
            Text("EV = equity × (eligible pot + your call) − your call. Effective stacks show remaining betting exposure; stack sizes do not change showdown hand strength.").font(.caption2).foregroundStyle(.secondary)
            Text("Assumes everyone reaches showdown, one eligible pot, no later bets and no rake. Future actions and opponent ranges are unknown. Side pots or unclear all-ins suppress automatic EV.").font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(Color.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
    }
    private func metric(_ label: String,_ value: String) -> some View {
        VStack(alignment:.leading,spacing:4) { Text(label).font(.caption2).foregroundStyle(.secondary); Text(value).font(.system(.title3,design:.rounded)).monospacedDigit() }
    }
    private func effective(_ seat: TableSeat,table: TableObservation) -> Int? {
        guard let stack = seat.stackCents, let hero = table.hero?.stackCents else { return nil }
        return min(stack,hero)
    }
}
