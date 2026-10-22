import Foundation
import TableRecognition

/// Current recognition evidence, independent from the complete hand used by poker math.
struct CardReadiness {
    var faces=0
    var confirmedHole=[DetectedCard]()
    var message=""
    var received=false
    var availability: AdviceAvailability {
        if confirmedHole.count==2 { return .boardReading }
        return faces>0 ? .cardConfirmation : .cardRecognition
    }
    var reason: String {
        if confirmedHole.count==2 { return "Your two hole cards are read. Reading the full board before resuming advice and EV." }
        if faces>0 { return "Screen scanning is active, but a current hole-card pair is not confirmed. "+message }
        return "The current screen reading contains no accepted card faces. "+message+" If your cards are visible in Safari, select its poker window with Stop → Start and keep that tab open."
    }
}
