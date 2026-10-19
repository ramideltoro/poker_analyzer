import SwiftUI

enum DashboardStyle {
    static let accent = Color(red:0.38,green:0.9,blue:0.75)
    static let cyan = Color(red:0.32,green:0.77,blue:0.98)
    static let loss = Color(red:0.99,green:0.44,blue:0.53)
    static let background = Color(red:0.045,green:0.06,blue:0.095)
    static let analysisHeight: CGFloat = 478
    static let chartHeight: CGFloat = 250
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
