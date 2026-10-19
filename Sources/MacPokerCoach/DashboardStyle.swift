import SwiftUI

enum DashboardStyle {
    static let accent = Color(red:0.38,green:0.9,blue:0.75)
    static let cyan = Color(red:0.32,green:0.77,blue:0.98)
    static let loss = Color(red:0.99,green:0.44,blue:0.53)
    static let background = Color(red:0.045,green:0.06,blue:0.095)
    static let analysisHeight: CGFloat = 510
}
struct DashboardMetrics {
    let size: CGSize
    var padding: CGFloat { size.width >= 1400 ? 20 : 14 }
    var gap: CGFloat { size.width >= 1400 ? 14 : 8 }
    var header: CGFloat { size.height >= 900 ? 40 : 34 }
    var cards: CGFloat { size.height >= 900 ? 132 : 108 }
    var analysis: CGFloat { max(510,size.height-padding*2-header-cards-16-gap*3) }
}
struct AnalysisMetrics {
    let size: CGSize
    var gap: CGFloat { size.width >= 1300 ? 14 : 8 }
    var summary: CGFloat { min(174,max(124,size.height*0.21)) }
    var body: CGFloat { size.height-summary-24-gap*2 }
    var outcome: CGFloat { max(132,body*0.36) }
    var details: CGFloat { body-outcome-gap }
    var threshold: CGFloat { max(144,body*0.43) }
    var categories: CGFloat { body-threshold-gap }
    var leftWidth: CGFloat { (size.width-gap*2)*0.39 }
    var middleWidth: CGFloat { (size.width-gap*2)*0.37 }
    var rightWidth: CGFloat { (size.width-gap*2)*0.24 }
}
extension View {
    func dashboardPanel() -> some View {
        background(LinearGradient(colors:[Color.white.opacity(0.055),Color.white.opacity(0.025)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:14))
            .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(Color.white.opacity(0.065),lineWidth:1))
    }
    func sectionLabel() -> some View {
        font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(.secondary)
    }
}
