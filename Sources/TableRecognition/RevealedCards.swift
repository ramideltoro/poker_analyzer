import Foundation
import PokerCore

/// Associate two full-size faces immediately above ONE occupied opponent capsule.
/// History thumbnails, the board, overlaps and partial reveals are rejected.
public enum RevealedCards {
    public static func associate(cards: [DetectedCard],seats: [TableSeat],known: [Card]) -> [[Card]] {
        var result = [[Card]](repeating:[],count:seats.count)
        for (index,seat) in seats.enumerated() where !seat.isHero && !seat.isNewPlayer {
            let panel = seat.bounds
            let area = CGRect(x:panel.x,y:panel.y-panel.height*2.2,width:panel.width,height:panel.height*2.2)
            let matches = cards.filter {
                !known.contains($0.card) && $0.rankScore >= 0.86 && $0.suitScore >= 0.82 &&
                (0.8...2.5).contains($0.bounds.height/panel.height) &&
                area.contains(CGPoint(x:$0.bounds.rect.midX,y:$0.bounds.rect.midY)) &&
                $0.bounds.rect.maxY <= panel.rect.maxY
            }.sorted { $0.bounds.x < $1.bounds.x }
            guard matches.count == 2, matches[0].card != matches[1].card,
                  abs(matches[0].bounds.y-matches[1].bounds.y) < panel.height*0.4,
                  matches[1].bounds.x-matches[0].bounds.rect.maxX < panel.width*0.2 else { continue }
            result[index] = matches.map(\.card)
        }
        let all = result.flatMap { $0 }
        for i in result.indices where result[i].contains(where:{ card in all.filter { $0 == card }.count > 1 }) { result[i] = [] }
        return result
    }
}
