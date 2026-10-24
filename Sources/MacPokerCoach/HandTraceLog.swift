import Foundation
import AppKit
import PokerCore
import TableRecognition

/// User-requested local hand traces. Separate from metadata-only diagnostics; never stores images.
@MainActor final class HandTraceLog {
    static let shared=HandTraceLog()
    static let disabled=HandTraceLog(enabled:false)
    let writer: DiagnosticLog
    var fileURL: URL? { writer.fileURL }
    private var lastFields=[String:String]()
    private var handID=UUID()
    private var priorHole=[String](), priorBoard=[String]()
    init(directory: URL? = nil,enabled: Bool = true,limit: Int = 2_000_000) {
        let folder=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LiveCardReader/HandTraces",isDirectory:true)
        if enabled {
            let existing=(try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []
            let ordered=existing.filter { $0.pathExtension=="jsonl" }.sorted { a,b in
                ((try? a.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? b.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            for file in ordered.dropFirst(5) { try? FileManager.default.removeItem(at:file) }
        }
        writer=DiagnosticLog(directory:folder,enabled:enabled,limit:limit)
    }
    func record(hand: LiveHand?,observed: TableObservation?,analysis: HandAnalysisModel,display: AnalysisDisplay,status: String) {
        guard fileURL != nil else { return }
        if let hand {
            let hole=hand.hole.map { $0.card.code }.sorted(), board=hand.board.map { $0.card.code }
            if hole != priorHole || (!hand.isReview && board.isEmpty && !priorBoard.isEmpty) { handID=UUID() }
            priorHole=hole; priorBoard=board
        }
        let advice=analysis.decisionAdvice, forecast=analysis.forecast
        var fields:[String:String]=[
            "hand_id":handID.uuidString,
            "app_version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development",
            "hole_cards":hand?.hole.map { $0.card.code }.joined(separator:" ") ?? "",
            "board_cards":hand?.board.map { $0.card.code }.joined(separator:" ") ?? "",
            "cards_mode":hand == nil ? "absent" : hand!.isReview ? "saved_what_if" : "confirmed_current",
            "observed_timestamp":hand.map { ISO8601DateFormatter().string(from:$0.timestamp) } ?? "unknown",
            "recognition_stage":analysis.reading.availability.rawValue,"recognition_message":analysis.reading.message,
            "recognition_hole_cards":analysis.reading.confirmedHole.map { $0.card.code }.joined(separator:" "),
            "status":status,"position":analysis.position.rawValue,"preflop_situation":analysis.preflopSituation.rawValue,
            "effective_position":analysis.effectivePosition.rawValue,"position_source":analysis.positionSource,
            "recognized_dealer_seat":analysis.recognizedPosition.map { String($0.dealerID) } ?? "unknown",
            "observed_dealer_seat":observed?.dealerSeatID.map(String.init) ?? "unknown",
            "effective_preflop_situation":analysis.effectiveSituation.rawValue,
            "raise_response_preset":analysis.raiseRange.rawValue,
            "tracked_preflop_call":"\(analysis.preflopEvidence.heroCalled)","tracked_preflop_raise":"\(analysis.preflopEvidence.heroRaised)","observed_opponent_raises":"\(analysis.preflopEvidence.opponentRaises)",
            "raise_response_ranges":analysis.responseKey?.ranges.map(\.notation).joined(separator:" | ") ?? "none",
            "raise_response_equity":analysis.raiseResponseResult.map { String($0.equity) } ?? "unavailable",
            "raise_response_samples":analysis.raiseResponseResult.map { String($0.samples) } ?? "0",
            "raise_response_price_basis":analysis.raiseResponseResult == nil ? "none" : analysis.responseUsesQuotedPrice ? "confirmed_call_control" : "visible_wager_gap",
            "big_blind_cents":analysis.preflopContext.bigBlindCents.map(String.init) ?? "unknown",
            "observed_pot_cents":observed?.potCents.map(String.init) ?? "unknown",
            "observed_call_cents":observed?.callCents.map(String.init) ?? "unknown",
            "observed_opponents":"\(observed?.activeOpponents.count ?? 0)",
            "table_issue":observed?.incompleteReason ?? "none",
            "table_confirmed":"\(analysis.tableConfirmed)","equity_table_confirmed":"\(analysis.equityTableConfirmed)",
            "controls_confirmed":"\(analysis.actionControlsConfirmed)",
            "observed_controls":observed?.controls.map { "fold=\($0.canFold),check=\($0.canCheck),call=\($0.canCall),bet=\($0.canBet),raise=\($0.canRaise),raise_to=\($0.raiseToCents.map(String.init) ?? "unknown")" } ?? "none",
            "live_action":analysis.actionAdvice.kind?.rawValue ?? "none",
            "displayed_action":advice.kind?.rawValue ?? "none","displayed_reason":advice.reason,
            "displayed_basis":advice.basis,"displayed_provisional":String(advice.provisional),"displayed_historical":String(analysis.decisionIsHistory || advice.retained),"displayed_retained":String(advice.retained),
            "display_mode":analysis.decisionIsHistory ? "last_displayed_move_or_plan" : advice.retained ? "last_verified_turn" : advice.basis=="DEFAULT PLAN" ? "default_plan" : analysis.isPlanning ? "forecast" : "live_or_waiting",
            "equity_current":"\(analysis.equityIsCurrent)",
            "visible_player_equity":analysis.result.map { String($0.equity) } ?? "unavailable",
            "equity_samples":analysis.result.map { String($0.samples) } ?? "0",
            "equity_sampling_bound":analysis.result.map { String($0.samplingBound) } ?? "unknown",
            "equity_model":"uniform_random_legal_hands_no_future_bets_or_rake",
            "forecast_assumed_fold_ids":forecast?.assumedFoldIDs.map(String.init).joined(separator:",") ?? "",
            "forecast_assumption":forecast?.assumption ?? "none",
            "forecast_opponents":forecast.map { String($0.opponents) } ?? "unknown",
            "forecast_call_cents":forecast?.callCents.map(String.init) ?? "unknown",
            "forecast_equity":forecast?.result.map { String($0.equity) } ?? "unavailable",
            "forecast_ev":forecast?.estimate.map { String($0.value) } ?? "unavailable",
            "live_ev":analysis.callEstimate.map { String($0.value) } ?? "unavailable"
        ]
        // Hand-local geometry IDs only. No opponent shown cards, persistent identity or raw OCR.
        let seats=(observed?.seats ?? []).map { s in
            ["id":String(s.id),"hero":String(s.isHero),"stack_cents":s.stackCents.map(String.init) ?? "unknown",
             "bet_cents":s.betCents.map(String.init) ?? "unknown","activity":s.activity.rawValue,
             "observed_action":s.action?.rawValue ?? "none","acting":String(s.isActing)]
        }
        if let data=try? JSONSerialization.data(withJSONObject:seats,options:[.sortedKeys]), let json=String(data:data,encoding:.utf8) { fields["observed_seats_json"]=json }
        var identity=fields; identity.removeValue(forKey:"observed_timestamp")
        guard identity != lastFields else { return }
        lastFields=identity; writer.write("hand_state",fields)
    }
    func end(_ reason: String) {
        guard !priorHole.isEmpty else { return }
        writer.write("capture_end",["hand_id":handID.uuidString,"reason":reason]); writer.flush()
        priorHole=[]; priorBoard=[]; lastFields=[:]; handID=UUID()
    }
    func reveal() { writer.flush(); if let fileURL { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) } }
    func flush() { writer.flush() }
}
