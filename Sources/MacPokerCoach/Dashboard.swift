import SwiftUI
import PokerCore
import TableRecognition

private let accent = Color(red:0.43,green:0.89,blue:0.72)
struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var capture: CaptureController
    init(model: AppModel) { self.model = model; capture = model.capture }
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            HStack(spacing:12) {
                Image(systemName:"viewfinder").font(.title).foregroundStyle(accent)
                VStack(alignment:.leading,spacing:5) {
                    Text("Live card reader").font(.system(size:25,weight:.semibold))
                    Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer()
                Button("Show logs",systemImage:"doc.text.magnifyingglass") { model.showLogs() }
                if capture.running || capture.choosing { Button("Stop",systemImage:"stop.fill") { model.stop() } }
                else { Button("Start",systemImage:"play.fill") { model.start() }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black) }
            }
            Divider()
            HStack(alignment:.top,spacing:32) {
                VStack(alignment:.leading,spacing:16) {
                    label("YOUR CARDS")
                    HStack(spacing:12) { ForEach(0..<2,id:\.self) { i in PlayingCard(card:model.hand?.hole[safe:i]?.card) } }
                }
                Spacer(minLength:0)
                VStack(alignment:.leading,spacing:16) {
                    label("COMMUNITY CARDS")
                    HStack(spacing:10) { ForEach(0..<5,id:\.self) { i in PlayingCard(card:model.hand?.board[safe:i]?.card,small:true) } }
                }
            }.padding(.vertical,16)
            Text(model.hand?.combination ?? (model.hand != nil ? "Two-card hand detected" : "Waiting for visible cards")).font(.title3).fontWeight(.medium)
            HandAnalysisView(analysis:model.analysis)
            Text("Assumes the single two-card group below the board is yours. Keep the entire table, player stacks and action buttons visible.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Spacer(minLength:0)
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Circle().fill(capture.running ? accent : .gray).frame(width:7,height:7)
                    Text(capture.running ? "Watching the selected monitor continuously" : "Screen reading stopped").font(.caption)
                    Spacer()
                    if capture.running { Text("\(model.receivedFrames) frames · \(model.scanned) scans · \(model.candidates) candidates · \(model.faces) faces").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary) }
                }
                Text("v\(model.version) · \(model.log.fileURL == nil ? "Logging unavailable" : "Local diagnostic logging on") · Images, card values and amounts are not logged.").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(28) }.background(Color(red:0.055,green:0.075,blue:0.11))
    }
    private func label(_ text: String) -> some View { Text(text).font(.system(size:10,weight:.semibold)).tracking(1.2).foregroundStyle(.secondary) }
}
struct PlayingCard: View {
    var card: Card?
    var small = false
    var body: some View {
        VStack(spacing:4) {
            if let card {
                Text(String(card.code.dropLast())).font(.system(size:small ? 26 : 34,weight:.semibold,design:.rounded))
                Text(card.suit.symbol).font(.system(size:small ? 25 : 32))
            } else { Text("—").font(.title2).opacity(0.3) }
        }.foregroundStyle(card?.suit.red == true ? Color(red:0.77,green:0.19,blue:0.25) : card == nil ? .gray : Color(red:0.12,green:0.18,blue:0.24))
            .frame(width:small ? 61 : 77,height:small ? 87 : 109)
            .background(card == nil ? Color.white.opacity(0.055) : Color(red:0.95,green:0.95,blue:0.91),in:RoundedRectangle(cornerRadius:9))
            .accessibilityLabel(card?.display ?? "Card not detected")
    }
}
extension Array { subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
