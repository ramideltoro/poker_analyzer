import Foundation

/// Explicit local raise/fold reference for standard unopened cash pots at 20–49 BB.
/// These are conservative policy assumptions, not licensed solver charts or solved EV.
/// Separate from the 100 BB Little cutoff chart. Facing a raise uses range equity instead.
public enum ShortCashRange: String,CaseIterable,Sendable {
    case early,hijack,cutoff,button,smallBlind
    public var notation: String {
        switch self {
        case .early: return "55+,A9s+,KTs+,QTs+,JTs,T9s,AJo+,KQo"
        case .hijack: return "44+,A2s+,K9s+,Q9s+,J9s+,T9s,98s,87s,ATo+,KJo+,QJo"
        case .cutoff: return "22+,A2s+,K7s+,Q8s+,J8s+,T8s+,98s,97s,87s,76s,65s,A8o+,KTo+,QTo+,JTo"
        case .button: return "22+,A2s+,K2s+,Q5s+,J7s+,T7s+,98s,97s,87s,86s,76s,65s,54s,A2o+,K8o+,Q9o+,J9o+,T9o"
        case .smallBlind: return "22+,A2s+,K2s+,Q5s+,J7s+,T7s+,98s,97s,87s,86s,76s,65s,54s,A2o+,K5o+,Q8o+,J8o+,T8o+,98o"
        }
    }
    public func contains(_ hole: [Card]) -> Bool {
        guard hole.count==2,Set(hole).count==2 else { return false }
        let h=max(hole[0].rank,hole[1].rank),l=min(hole[0].rank,hole[1].rank),s=hole[0].suit==hole[1].suit
        if h==l { return h >= (self == .early ? 5 : self == .hijack ? 4 : 2) }
        switch self {
        case .early:
            return s ? h==14 && l>=9 || h==13 && l>=10 || h==12 && l>=10 || h==11 && l==10 || h==10 && l==9 : h==14 && l>=11 || h==13 && l==12
        case .hijack:
            return s ? h==14 || h==13 && l>=9 || h==12 && l>=9 || h==11 && l>=9 || h-l==1 && l>=7 : h==14 && l>=10 || h==13 && l>=11 || h==12 && l==11
        case .cutoff:
            return s ? h==14 || h==13 && l>=7 || h==12 && l>=8 || h==11 && l>=8 || h==10 && l>=8 || h==9 && l>=7 || h-l==1 && l>=5 : h==14 && l>=8 || h>=11 && l>=10
        case .button,.smallBlind:
            if s { return h==14 || h==13 || h==12 && l>=5 || h==11 && l>=7 || h==10 && l>=7 || (h==9 || h==8) && l>=h-2 || h-l==1 && l>=4 }
            return h==14 || h==13 && l >= (self == .smallBlind ? 5 : 8) || (h==12 || h==11) && l >= (self == .smallBlind ? 8 : 9) || h==10 && l >= (self == .smallBlind ? 8 : 9) || self == .smallBlind && h==9 && l==8
        }
    }
}
