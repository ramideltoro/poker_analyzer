import Foundation
import CoreGraphics

enum RankRecognizer {
    struct Match { var rank: String; var score: Double; var margin: Double }
    private static let templates: [(String,[Bool])] = {
        var result = [(String,[Bool])]()
        for font in ["Arial","Arial-BoldMT","ArialNarrow-Bold","Georgia","Georgia-Bold","Times New Roman","TimesNewRomanPS-BoldMT","Helvetica Neue","HelveticaNeue-Bold","HelveticaNeue-CondensedBold","HelveticaNeue-CondensedBlack","AvenirNextCondensed-DemiBold","AvenirNextCondensed-Bold","AvenirNextCondensed-Heavy","DINAlternate-Bold","DINCondensed-Bold"] {
            for rank in "23456789TJQKA".map(String.init) {
                let glyph = rank == "T" ? "10" : rank
                if let mask = SuitRecognizer.mask(SuitRecognizer.renderGlyph(glyph,fontName:font),largestOnly:false) { result.append((rank,mask)) }
            }
        }
        return result
    }()
    static func match(_ image: CGImage) -> Match? {
        guard let sample = SuitRecognizer.mask(image,largestOnly:false) else { return nil }
        // A small width tolerance handles condensed web fonts and resize sampling.
        // Keep the same acceptance score and separation from competing ranks.
        let samples = [0.92,1.0,1.08].map { scale in
            (0..<784).map { index -> Bool in
                let x = index%28, y = index/28
                let sourceX = Int(((Double(x)-13.5)/scale+13.5).rounded())
                return (0..<28).contains(sourceX) && sample[y*28+sourceX]
            }
        }
        var scores = [(String,Double)]()
        for rank in "23456789TJQKA".map(String.init) {
            var best = 0.0
            for template in templates where template.0 == rank {
                for variant in samples { best = max(best,SuitRecognizer.alignedDice(variant,template.1)) }
            }
            scores.append((rank,best))
        }
        scores.sort { $0.1 > $1.1 }
        return Match(rank:scores[0].0,score:scores[0].1,margin:scores[0].1-scores[1].1)
    }
}
