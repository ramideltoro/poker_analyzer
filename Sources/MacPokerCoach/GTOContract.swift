import Foundation
import PokerCore
import TableRecognition

struct GTORequest: Codable, Equatable, Sendable {
    var `protocol` = 1
    var hole: [String]
    var board: [String]
    var oopRange: String
    var ipRange: String
    var heroIp: Bool
    /// Pot BEFORE the first bet on this street; stacks at that same root.
    var potCents: Int
    var stackCents: Int
    var facingBetCents: Int
    var rakePercent: Double
    var rakeCapCents: Int
    var maxIterations = 500
    var targetGapPercent = 0.5
    var seconds = 20
    static var encoder: JSONEncoder { let e=JSONEncoder();e.keyEncodingStrategy = .convertToSnakeCase;return e }
    static var decoder: JSONDecoder { let d=JSONDecoder();d.keyDecodingStrategy = .convertFromSnakeCase;return d }
}
struct GTOChoice: Codable, Equatable, Sendable, Identifiable {
    var action: SeatAction
    var amountCents: Int
    var frequency: Double
    var evCents: Double
    var id: String { action.rawValue+String(amountCents) }
    var label: String { action.label+([.bet,.raise,.call].contains(action) ? String(format:" $%.2f",Double(amountCents)/100) : "") }
}
struct GTOResult: Codable, Equatable, Sendable {
    var `protocol`: Int
    var engine: String
    var iterations: Int
    var elapsedSeconds: Double
    var exploitabilityCents: Double
    var gapPercent: Double
    var converged: Bool
    var compressed: Bool
    var memoryBytes: Int
    var equity: Double
    var evCents: Double
    var choices: [GTOChoice]
    var preferred: GTOChoice? { choices.max { $0.frequency < $1.frequency } }
    func validate(for request: GTORequest) throws {
        guard `protocol`==1,iterations>0,iterations<=request.maxIterations,
              !choices.isEmpty,choices.count<=12,Set(choices.map(\.id)).count==choices.count,
              (0...1).contains(equity),evCents.isFinite,elapsedSeconds.isFinite,elapsedSeconds>=0,
              exploitabilityCents.isFinite,exploitabilityCents>=0,gapPercent.isFinite,gapPercent>=0,
              abs(gapPercent-exploitabilityCents/Double(request.potCents)*100)<0.001,
              !converged || gapPercent<=request.targetGapPercent+0.0001,
              abs(choices.reduce(0) { $0+$1.frequency }-1)<0.001,
              choices.allSatisfy({ c in
                  guard c.evCents.isFinite,c.frequency.isFinite,(0...1).contains(c.frequency),c.amountCents>=0,c.amountCents<=request.stackCents else { return false }
                  switch c.action {
                  case .check: return request.facingBetCents==0 && c.amountCents==0
                  case .fold: return request.facingBetCents>0 && c.amountCents==0 && abs(c.evCents)<0.01
                  case .call: return request.facingBetCents>0 && c.amountCents==request.facingBetCents
                  case .bet: return request.facingBetCents==0 && c.amountCents>0
                  case .raise: return request.facingBetCents>0 && c.amountCents>request.facingBetCents && (c.amountCents>=2*request.facingBetCents || c.amountCents==request.stackCents)
                  }
              }),abs(choices.reduce(0) { $0+$1.frequency*$1.evCents }-evCents)<0.1 else {
            throw GTOError.message("The solver returned an inconsistent strategy. No solver advice was applied.")
        }
    }
}
enum GTOError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let s):return s } }
}
struct GTOForm: Equatable {
    var hole="As Kh", board="Qs Jh 2c 4d 3s"
    var oopRange="22+,A2s+,K2s+,Q5s+,J7s+,T7s+,98s,87s,76s,65s,54s,ATo+,KTo+,QTo+,JTo"
    var ipRange="22+,A2s+,K2s+,Q5s+,J7s+,T7s+,98s,87s,76s,65s,54s,ATo+,KTo+,QTo+,JTo"
    var heroIp=false
    var pot="1.00", stack="3.00", facingBet="0.00", rake="0", rakeCap="0.00"
    var iterations=500, seconds=20, target=0.5
    func request() throws -> GTORequest {
        func cards(_ text:String) throws -> [Card] {
            let raw=text.replacingOccurrences(of:"10",with:"T").filter { !$0.isWhitespace && $0 != "," }
            let chars=Array(raw)
            guard chars.count%2==0 else { throw GTOError.message("Enter cards such as As Kh, using c/d/h/s for suits.") }
            return try stride(from:0,to:chars.count,by:2).map { i in
                guard let c=Card(String(chars[i...i+1])) else { throw GTOError.message("Unrecognized card. Use ranks 2–9/T/J/Q/K/A and suits c/d/h/s.") };return c
            }
        }
        let h=try cards(hole),b=try cards(board)
        guard h.count==2,(3...5).contains(b.count),Set(h+b).count==h.count+b.count else { throw GTOError.message("Use two distinct hole cards and 3–5 community cards, without duplicates. Preflop solving is not supported.") }
        guard let p=TableMoney.cents(pot,requireCurrency:false),let s=TableMoney.cents(stack,requireCurrency:false),let c=TableMoney.cents(facingBet,requireCurrency:false),
              let cap=TableMoney.cents(rakeCap,requireCurrency:false),let r=Double(rake),r.isFinite,(0...10).contains(r),
              (1...1_000_000).contains(p),(1...1_000_000).contains(s),Double(s)/Double(p)<=20,(0...s).contains(c),(0...1_000_000).contains(cap),
              (10...2000).contains(iterations),(1...60).contains(seconds),(0.01...5).contains(target) else {
            throw GTOError.message("Use positive pot/stack, a bet no larger than the effective stack, SPR ≤20, and valid time/accuracy/rake settings.")
        }
        guard !oopRange.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,!ipRange.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,oopRange.utf8.count<=12000,ipRange.utf8.count<=12000 else { throw GTOError.message("Enter both players’ full plausible ranges.") }
        return GTORequest(hole:h.map(\.code).sorted(),board:b.map(\.code),oopRange:oopRange,ipRange:ipRange,heroIp:heroIp,potCents:p,stackCents:s,facingBetCents:c,rakePercent:r,rakeCapCents:cap,maxIterations:iterations,targetGapPercent:target,seconds:seconds)
    }
}

/// A supported current-street subgame, never a reconstruction of an unknown raise sequence.
struct GTOSnapshot: Equatable {
    var hole: [String], board: [String]
    var heroID: Int, opponentID: Int, dealerID: Int
    var heroStack: Int, opponentStack: Int, pot: Int, bet: Int, heroIp: Bool
    static func read(hand: LiveHand?,table:TableObservation?,confirmed:Bool,position:RecognizedPosition?) -> GTOSnapshot? {
        guard confirmed,let hand,!hand.isReview,hand.hole.count==2,(3...5).contains(hand.board.count),
              let t=table,t.incompleteReason==nil,!t.sidePots,t.trackingUsable,t.activeOpponents.count==1,
              let h=t.hero,h.activity == .active,h.betCents==0,let hs=h.stackCents,hs>0,
              let f=t.activeOpponents.first,!f.isNewPlayer,f.revealedCards.isEmpty,let fs=f.stackCents,fs>=0,
              let bet=f.betCents,bet>=0,let p=t.potCents,p>bet,t.callCents==bet,
              t.boardCards==hand.board.map(\.card),t.seats.filter({ !$0.isHero && $0.id != f.id }).allSatisfy({ ($0.betCents ?? 0)==0 }),
              let pos=position,t.dealerSeatID==pos.dealerID,
              let oi=pos.ring.firstIndex(where:{ $0.id==f.id }),
              t.controls.map({ bet==0 ? $0.canCheck && !$0.canCall : $0.canCall && !$0.canCheck })==true else { return nil }
        let effective=min(hs,fs+bet),rootPot=p-bet
        guard bet<=effective,effective>0,Double(effective)/Double(rootPot)<=20 else { return nil }
        let n=pos.ring.count
        func order(_ index:Int)->Int { let d=(index-pos.dealerIndex+n)%n;return d==0 ? n : d }
        return GTOSnapshot(hole:hand.hole.map { $0.card.code }.sorted(),board:hand.board.map { $0.card.code },heroID:h.id,opponentID:f.id,dealerID:pos.dealerID,heroStack:hs,opponentStack:fs,pot:p,bet:bet,heroIp:order(pos.heroIndex)>order(oi))
    }
    func fill(_ form: inout GTOForm) {
        form.hole=hole.joined(separator:" ");form.board=board.joined(separator:" ");form.heroIp=heroIp
        form.pot=String(format:"%.2f",Double(pot-bet)/100);form.stack=String(format:"%.2f",Double(min(heroStack,opponentStack+bet))/100);form.facingBet=String(format:"%.2f",Double(bet)/100)
    }
    func matches(_ request:GTORequest)->Bool {
        hole==request.hole && board==request.board && heroIp==request.heroIp && request.potCents==pot-bet && request.stackCents==min(heroStack,opponentStack+bet) && request.facingBetCents==bet
    }
}
