import SwiftUI
import AppKit

@main struct MacPokerCoachApp: App {
    @StateObject private var model = AppModel()
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        WindowGroup("Live Card Reader") {
            RootView(model:model).background(MaximizedWindow()).preferredColorScheme(.dark).frame(minWidth:1000,minHeight:720)
        }.defaultSize(width:1440,height:900)
            .commands { CommandGroup(replacing:.newItem) {} }
    }
}
