import SwiftUI
import AppKit
import PokerCore
import TableRecognition

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var capture: CaptureController
    @ObservedObject private var analysis: HandAnalysisModel
    init(model: AppModel) { self.model = model; capture = model.capture; analysis = model.analysis }
    var body: some View {
        GeometryReader { geometry in
            let layout = DashboardMetrics(size:geometry.size)
            VStack(spacing:layout.gap) {
                header.frame(height:layout.header)
                HandAnalysisView(analysis:analysis,height:layout.analysis)
                cardsDock(height:layout.cards).frame(height:layout.cards)
                footer
            }.padding(layout.padding).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
        }.background(LinearGradient(colors:[Color(red:0.065,green:0.085,blue:0.13),DashboardStyle.background],startPoint:.topLeading,endPoint:.bottomTrailing))
            .transaction { $0.animation = nil }
    }
    private var header: some View {
        HStack(spacing:12) {
            Image(systemName:"viewfinder").font(.system(size:21,weight:.medium)).foregroundStyle(DashboardStyle.accent)
            Text("Live Card Reader").font(.system(size:17,weight:.semibold))
            HStack(spacing:5) {
                Circle().fill(capture.choosing ? .orange : capture.running ? DashboardStyle.accent : .gray).frame(width:5,height:5)
                Text(capture.choosing ? "SELECTING" : capture.running ? "SCANNING" : "STOPPED").font(.system(size:8,weight:.semibold)).tracking(0.7)
            }.padding(.horizontal,8).padding(.vertical,5).background(Color.white.opacity(0.04),in:Capsule())
            Spacer(minLength:8)
            Toggle("Auto table",isOn:Binding(get:{ analysis.automatic },set:{ analysis.setAutomatic($0) }))
                .toggleStyle(.switch).tint(DashboardStyle.accent).controlSize(.mini).font(.system(size:11)).fixedSize().help("Read pot, stacks and opponents automatically. Turn off for manual inputs.")
            Stepper(value:Binding(get:{ analysis.opponents },set:{ analysis.setOpponents($0) }),in:1...8) {
                Text("\(analysis.opponents) opp.").font(.system(size:11)).monospacedDigit().frame(width:42,alignment:.trailing)
            }.fixedSize().controlSize(.small).disabled(analysis.automatic).help("Manual opponent count; automatic mode uses detected active players.")
            Divider().frame(height:20)
            Button {
                if let window = NSApp.keyWindow, let screen = window.screen { window.setFrame(screen.visibleFrame,display:true,animate:false) }
            } label: { Image(systemName:"arrow.up.left.and.arrow.down.right") }.buttonStyle(.borderless).help("Fill the screen")
            AnalysisHelpButton()
            Button { model.showLogs() } label: { Image(systemName:"doc.text.magnifyingglass") }.buttonStyle(.borderless).help("Show diagnostic logs").accessibilityLabel("Show logs")
            Button(capture.running || capture.choosing ? "Stop" : "Start",systemImage:capture.running || capture.choosing ? "stop.fill" : "play.fill") {
                if capture.running || capture.choosing { model.stop() } else { model.start() }
            }.buttonStyle(.borderedProminent).tint(DashboardStyle.accent).foregroundStyle(.black).controlSize(.small).frame(width:82)
        }.frame(height:34)
    }
    private func cardsDock(height: CGFloat) -> some View {
        let scale: CGFloat = height >= 125 ? 1.25 : 1
        return HStack(spacing:22) {
            VStack(alignment:.leading,spacing:6) {
                Text("YOUR CARDS").sectionLabel()
                HStack(spacing:7) { ForEach(0..<2,id:\.self) { i in PlayingCard(card:analysis.display.hand?.hole[safe:i]?.card,muted:model.hand == nil,scale:scale) } }
            }.frame(maxWidth:.infinity)
            Divider().frame(height:76)
            VStack(alignment:.leading,spacing:6) {
                Text("COMMUNITY CARDS").sectionLabel()
                HStack(spacing:7) { ForEach(0..<5,id:\.self) { i in PlayingCard(card:analysis.display.hand?.board[safe:i]?.card,small:true,muted:model.hand == nil,scale:scale) } }
            }.frame(maxWidth:.infinity)
            Divider().frame(height:76)
            VStack(alignment:.trailing,spacing:7) {
                Label(analysis.isReview ? "Saved-card review" : model.hand == nil ? "Waiting for cards" : "Confirmed cards",systemImage:analysis.isReview ? "clock.arrow.circlepath" : "suit.club")
                    .font(.system(size:12,weight:.medium)).foregroundStyle(analysis.isReview ? .orange : DashboardStyle.accent)
                Text(analysis.isReview ? "Your saved cards + the visible board.\nLast decision EV stays frozen." : "Keep the captured table unobstructed.\nMove or resize this dashboard if needed.")
                    .font(.system(size:10)).foregroundStyle(.secondary).multilineTextAlignment(.trailing).lineLimit(2)
            }.frame(width:210,alignment:.trailing)
        }.padding(.horizontal,16).padding(.vertical,8).frame(maxWidth:.infinity,maxHeight:.infinity).dashboardPanel()
    }
    private var footer: some View {
        HStack {
            Text(model.status).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).help(model.status)
            Spacer(minLength:12)
            Text("\(model.scanned) scans · \(model.faces) faces · \(model.milliseconds) ms · v\(model.version)")
                .font(.system(size:9,design:.monospaced)).monospacedDigit().foregroundStyle(.tertiary).fixedSize()
                .help("\(model.receivedFrames) received frames · \(model.candidates) candidates. Processing is local. Images, card values and amounts are not logged.")
        }.frame(height:16)
    }
}
struct PlayingCard: View {
    var card: Card?
    var small = false
    var muted = false
    var scale: CGFloat = 1
    var body: some View {
        VStack(spacing:1) {
            Text(card.map { String($0.code.dropLast()) } ?? "—").font(.system(size:(small ? 23 : 26)*scale,weight:.semibold,design:.rounded))
            Text(card?.suit.symbol ?? " ").font(.system(size:(small ? 23 : 25)*scale))
        }.foregroundStyle(card?.suit.red == true ? DashboardStyle.loss : .white).opacity(muted ? 0.42 : 1)
            .frame(width:(small ? 51 : 58)*scale,height:72*scale)
            .background(LinearGradient(colors:[Color.white.opacity(0.085),Color.white.opacity(0.03)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(Color.white.opacity(0.08)))
            .accessibilityLabel(card?.display ?? "Card not detected")
    }
}
extension Array { subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
