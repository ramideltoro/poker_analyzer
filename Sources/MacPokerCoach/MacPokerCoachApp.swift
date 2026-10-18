import SwiftUI
import AppKit

@main struct MacPokerCoachApp: App {
    @StateObject private var model = AppModel()
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        WindowGroup("Live Card Reader") {
            RootView(model:model).preferredColorScheme(.dark).frame(minWidth:850,minHeight:720)
        }.defaultSize(width:980,height:820)
            .commands { CommandGroup(replacing:.newItem) {} }
    }
}
