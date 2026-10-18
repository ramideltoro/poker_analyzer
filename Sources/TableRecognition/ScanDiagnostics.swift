import Foundation

public enum ScanRejection: String,CaseIterable,Codable,Sendable {
    case geometry, readerWindow, duplicateProposal, nonLightFace, rankInkMissing, rankShapeUncertain, suitInkMissing, suitShapeUncertain
}
public struct ScanDiagnostics: Sendable {
    public var width = 0
    public var height = 0
    public var visionCandidates = 0
    public var brightCandidates = 0
    public var hintCandidates = 0
    public var excludedFraction = 0.0
    public var rejections = [ScanRejection:Int]()
    public var bestRankScore = 0.0
    public var bestRankMargin = 0.0
    public var bestSuitScore = 0.0
    public var bestSuitMargin = 0.0
    private var candidateDetails = [String]()
    public init() {}
    public mutating func reject(_ reason: ScanRejection) { rejections[reason,default:0] += 1 }
    mutating func record(_ attempt: ScanDiagnostics,bounds: UnitRect,method: String) {
        for (reason,count) in attempt.rejections { rejections[reason,default:0] += count }
        if attempt.bestRankScore >= bestRankScore { bestRankScore = attempt.bestRankScore; bestRankMargin = attempt.bestRankMargin }
        if attempt.bestSuitScore >= bestSuitScore { bestSuitScore = attempt.bestSuitScore; bestSuitMargin = attempt.bestSuitMargin }
        if candidateDetails.count < 96 {
            let reasons = attempt.rejections.keys.map(\.rawValue).sorted().joined(separator:",")
            candidateDetails.append(String(format:"x=%.4f,y=%.4f,w=%.4f,h=%.4f;r=%.4f,%.4f;s=%.4f,%.4f;",bounds.x,bounds.y,bounds.width,bounds.height,attempt.bestRankScore,attempt.bestRankMargin,attempt.bestSuitScore,attempt.bestSuitMargin)+"method=\(method);rejected=\(reasons)")
        }
    }
    public var fields: [String:String] {
        var result = ["width":"\(width)","height":"\(height)","vision_candidates":"\(visionCandidates)","bright_candidates":"\(brightCandidates)","hint_candidates":"\(hintCandidates)",
                      "excluded_fraction":String(format:"%.4f",excludedFraction),"best_rank_score":String(format:"%.4f",bestRankScore),"best_rank_margin":String(format:"%.4f",bestRankMargin),
                      "best_suit_score":String(format:"%.4f",bestSuitScore),"best_suit_margin":String(format:"%.4f",bestSuitMargin)]
        for reason in ScanRejection.allCases { result["rejected_"+reason.rawValue] = "\(rejections[reason,default:0])" }
        result["candidate_details"] = candidateDetails.joined(separator:" | ")
        return result
    }
    public var summary: String {
        if excludedFraction >= 0.95 { return "The reader covers nearly all of the shared screen. Move it beside the table or minimize it." }
        if visionCandidates+brightCandidates == 0 { return "Screen received; no card-shaped areas found. Keep the cards visible and increase the table size." }
        let glyphFailures = [ScanRejection.rankInkMissing,.rankShapeUncertain,.suitInkMissing,.suitShapeUncertain].reduce(0) { $0+rejections[$1,default:0] }
        if glyphFailures > 0 { return "Screen received; card-like shapes found, but ranks or suits are not recognized. Details are in the log." }
        if rejections[.readerWindow,default:0] > 0 { return "Screen received; candidate areas overlap a reader window. Keep the reader away from the cards." }
        return "Screen received; no readable card faces found. Details are in the log."
    }
}
