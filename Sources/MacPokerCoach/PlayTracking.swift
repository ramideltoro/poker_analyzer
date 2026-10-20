import Foundation
import Combine
import PokerCore
import TableRecognition

struct OwnObservation: Codable, Identifiable, Equatable {
    var id = UUID()
    var time: Date
    var street: Int
    var note: String
    var stackCents: Int?
    var betCents: Int?
    var potCents: Int?
    var equity: Double?
    var callEV: Double?
    var callCents: Int?
    var opponents: Int?
}
struct OwnHandRecord: Codable, Identifiable {
    var id = UUID()
    var started: Date
    var ended: Date?
    var hole: [String]
    var board: [String]
    var startedPreflop: Bool
    var cardsDisappeared = false
    var sawFlop = false
    var reachedRiver = false
    var openingChips: Int?
    var netCents: Int?
    var observations = [OwnObservation]()
    var actions: [TrackedAction]?
    var completion = "In progress"
}
struct CashAdjustment: Codable, Identifiable {
    var id = UUID()
    var time: Date
    var cents: Int // positive = added to the table; negative = removed
}
struct OwnTableRecord: Codable, Identifiable {
    var id = UUID()
    var started: Date
    var ended: Date?
    var baselineCents: Int?
    var latestCents: Int?
    var checkpoint: Date?
    var appliedCashCents = 0
    var adjustments = [CashAdjustment]()
    var netCents: Int? {
        guard let baselineCents, let latestCents else { return nil }
        return latestCents-baselineCents-appliedCashCents
    }
    var pendingCashCents: Int { adjustments.reduce(0) { $0+$1.cents }-appliedCashCents }
}
struct OwnPlayArchive: Codable {
    var schema = 1
    var hands = [OwnHandRecord]()
    var tables = [OwnTableRecord]()
}
struct ShownHand: Identifiable {
    var id = UUID()
    var round: UUID
    var time: Date
    var cards: [Card]
    var board: [Card]
    var kind: String { board.count == 5 ? "River reveal" : "Shown cards" }
}
struct OpponentProfile: Identifiable {
    var id = UUID()
    var bounds: UnitRect
    var seatNumber: Int?
    var screenPosition: Int
    var stackCents: Int?
    var activity: SeatActivity
    var observedRounds = Set<UUID>()
    var shown = [ShownHand]()
    var actions = [TrackedAction]()
    var statistics: ActionStatistics { ActionStatistics(events:actions) }
    var label: String { seatNumber.map { "Seat \($0)" } ?? "Position \(screenPosition)" }
    // Deliberately not Codable. No opponent identity, cards or statistics enter the archive.
}

/// Hero data only. Ordered background atomic writes; errors do not overwrite unreadable history.
final class OwnPlayStore: @unchecked Sendable {
    let url: URL?
    private let queue = DispatchQueue(label:"cardreader.own-play",qos:.utility)
    init(url: URL?) { self.url = url }
    func load() throws -> OwnPlayArchive {
        guard let url, FileManager.default.fileExists(atPath:url.path) else { return OwnPlayArchive() }
        let archive = try JSONDecoder().decode(OwnPlayArchive.self,from:Data(contentsOf:url))
        guard archive.schema == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return archive
    }
    func save(_ archive: OwnPlayArchive,completion: @escaping @Sendable (Bool) -> Void) {
        guard let url else { return }
        queue.async {
            do {
                let data = try JSONEncoder().encode(archive)
                try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                try data.write(to:url,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
                completion(true)
            } catch { completion(false) }
        }
    }
    func flush() { queue.sync {} }
}

@MainActor final class PlayTracking: ObservableObject {
    @Published private(set) var archive: OwnPlayArchive
    @Published private(set) var opponents = [OpponentProfile]()
    @Published private(set) var active = false
    @Published private(set) var status = "Start scanning to begin a new table session."
    @Published private(set) var storageError: String?
    let store: OwnPlayStore
    private var writable = true
    private var previous: TableObservation?
    private var lastTable: Date?
    private var lastHero: TableSeat?
    private var missingFrames = [UUID:Int]()
    private var revealCandidates = [UUID:[Card]]()
    private var rejectedRevealRounds = [UUID:UUID]()
    private var markerVisible = Set<UUID>()
    private var actionScanners = [UUID:ActionScanner]()
    private var heroScanner = ActionScanner()
    private var round = UUID()
    private var roundBoard = [Card]()
    private var pendingBoard: [Card]?
    private var roundHasHeroDeal = false
    private var currentHandID: UUID?
    private var ownTableID: UUID?
    private var missingHeroFrames = 0
    private var dirty = false
    private var lastSaved = Date.distantPast

    init(url: URL? = nil,persist: Bool = true) {
        let destination = persist ? (url ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LiveCardReader/History/own-play.json")) : nil
        store = OwnPlayStore(url:destination)
        do {
            var loaded = try store.load()
            // A restarted app never resumes an anonymous identity or an unfinished money interval.
            for i in loaded.hands.indices where loaded.hands[i].ended == nil {
                loaded.hands[i].ended = Date(); loaded.hands[i].completion = "Capture ended · result unmeasured"
            }
            for i in loaded.tables.indices where loaded.tables[i].ended == nil { loaded.tables[i].ended = Date() }
            archive = loaded
        } catch {
            archive = OwnPlayArchive(); writable = false
            storageError = "Saved history could not be read. It is preserved; new tracking is memory-only."
        }
    }
    var tableRecord: OwnTableRecord? { ownTableID.flatMap { id in archive.tables.first { $0.id == id } } }
    var totalNetCents: Int? {
        let values = archive.tables.compactMap(\.netCents)
        return values.isEmpty ? nil : values.reduce(0,+)
    }
    var measuredHands: [OwnHandRecord] { archive.hands.filter { $0.netCents != nil } }
    var currentHand: OwnHandRecord? { currentHandID.flatMap { id in archive.hands.first { $0.id == id } } }
    var ownStatistics: ActionStatistics { ActionStatistics(events:archive.hands.flatMap { $0.actions ?? [] }) }

    /// Called for every fresh frame, independent of hero visibility and analysis availability.
    func observe(table: TableObservation?,hand: LiveHand?,time: Date) {
        guard let table, table.issue == nil, let hero = table.hero, table.seats.count >= 2 else {
            previous = nil; revealCandidates.removeAll()
            heroScanner.interrupt()
            for key in actionScanners.keys { actionScanners[key]?.interrupt() }
            if let lastTable, time.timeIntervalSince(lastTable) > 2.5 { endTable("Table visibility lost · opponent records cleared",time:time) }
            return
        }
        if let lastTable, time.timeIntervalSince(lastTable) > 2.5 { endTable("Capture gap · opponent records cleared",time:time) }
        lastTable = time
        // Identity is based on uninterrupted screen location plus a readable seat badge, never sorted array IDs.
        if active, let oldHero = lastHero {
            if !Self.sameSeat(oldHero.bounds,hero.bounds) || (oldHero.seatNumber != nil && hero.seatNumber != nil && oldHero.seatNumber != hero.seatNumber) {
                endTable("Table layout or your seat changed · opponent records cleared",time:time)
                lastTable = time
            }
        }
        guard let old = previous, old.hero.map({ Self.sameSeat($0.bounds,hero.bounds) }) == true else { previous = table; return }
        defer { previous = table; lastHero = hero; saveIfNeeded(time:time) }
        if !active {
            active = true
            let record = OwnTableRecord(started:time)
            archive.tables.append(record); ownTableID = record.id; dirty = true
            status = "Table session active · opponent records stay in memory only."
        }
        // Confirm board transitions twice. A vanished board or a different flop starts an observed round.
        if pendingBoard == table.boardCards {
            let board = table.boardCards
            if board != roundBoard {
                if !roundBoard.isEmpty && (board.isEmpty || !board.starts(with:roundBoard)) { beginRound() }
                roundBoard = board
            }
        }
        pendingBoard = table.boardCards
        observeOwn(hand:hand,table:table,old:old,time:time)
        reconcileOpponents(table,previous:old,time:time)
        for i in opponents.indices { opponents[i].observedRounds.insert(round) }
        recordReveals(table,previous:old,time:time)
        recordActions(table,previous:old,hand:hand,time:time)
    }
    private static func sameSeat(_ a: UnitRect,_ b: UnitRect) -> Bool {
        abs(a.rect.midX-b.rect.midX) < 0.022 && abs(a.rect.midY-b.rect.midY) < 0.022 &&
        (0.85...1.18).contains(a.width/b.width) && (0.75...1.3).contains(a.height/b.height)
    }
    private func reconcileOpponents(_ table: TableObservation,previous old: TableObservation,time: Date) {
        let visible = table.seats.filter { !$0.isHero }
        for profile in opponents {
            if !visible.contains(where:{ Self.sameSeat($0.bounds,profile.bounds) }) {
                missingFrames[profile.id,default:0] += 1
                if missingFrames[profile.id,default:0] >= 2 { removeOpponent(profile.id) }
            } else { missingFrames[profile.id] = nil }
        }
        for seat in visible {
            guard old.seats.contains(where:{ !$0.isHero && Self.sameSeat($0.bounds,seat.bounds) }) else { continue }
            if let i = opponents.firstIndex(where:{ Self.sameSeat($0.bounds,seat.bounds) }) {
                let profile = opponents[i]
                let numberChanged = seat.seatNumber != nil && profile.seatNumber != nil && seat.seatNumber != profile.seatNumber
                let newMarker = seat.isNewPlayer && !markerVisible.contains(profile.id)
                if numberChanged || newMarker { removeOpponent(profile.id) }
            }
            if let i = opponents.firstIndex(where:{ Self.sameSeat($0.bounds,seat.bounds) }) {
                opponents[i].bounds = seat.bounds
                if let number = seat.seatNumber { opponents[i].seatNumber = number }
                opponents[i].screenPosition = seat.id; opponents[i].stackCents = seat.stackCents; opponents[i].activity = seat.activity
                if seat.isNewPlayer { markerVisible.insert(opponents[i].id) } else { markerVisible.remove(opponents[i].id) }
            } else {
                let profile = OpponentProfile(bounds:seat.bounds,seatNumber:seat.seatNumber,screenPosition:seat.id,stackCents:seat.stackCents,activity:seat.activity)
                opponents.append(profile)
                if seat.isNewPlayer { markerVisible.insert(profile.id) }
            }
        }
    }
    private func removeOpponent(_ id: UUID) {
        opponents.removeAll { $0.id == id }; revealCandidates[id] = nil; rejectedRevealRounds[id] = nil; missingFrames[id] = nil; markerVisible.remove(id); actionScanners[id] = nil
    }
    func forgetOpponent(_ id: UUID) { removeOpponent(id); status = "Seat history cleared. A visible player starts a fresh profile on the next scan." }
    private func recordReveals(_ table: TableObservation,previous old: TableObservation,time: Date) {
        // Repeated frames and later streets of the same revealed hand do not inflate samples.
        for i in opponents.indices {
            let id = opponents[i].id
            guard rejectedRevealRounds[id] != round else { continue }
            guard let seat = table.seats.first(where:{ !$0.isHero && Self.sameSeat($0.bounds,opponents[i].bounds) }),
                  seat.revealedCards.count == 2, Set(seat.revealedCards).count == 2,
                  !seat.revealedCards.contains(where:table.boardCards.contains), !seat.isNewPlayer else { revealCandidates[id] = nil; continue }
            if roundHasHeroDeal, let own = currentHand, seat.revealedCards.contains(where:{ own.hole.contains($0.code) }) {
                revealCandidates[id] = nil; continue
            }
            guard table.boardCards == old.boardCards else { revealCandidates[id] = nil; continue }
            let cards = seat.revealedCards.sorted { $0.code < $1.code }
            guard revealCandidates[id] == cards else { revealCandidates[id] = cards; continue }
            if let j = opponents[i].shown.firstIndex(where:{ $0.round == round }) {
                guard opponents[i].shown[j].cards == cards else {
                    // An inconsistent reveal cannot be attributed safely, even within the same round.
                    opponents[i].shown.remove(at:j); revealCandidates[id] = nil; rejectedRevealRounds[id] = round
                    status = "Conflicting shown-card readings ignored for this observed round."; continue
                }
                if table.boardCards.starts(with:opponents[i].shown[j].board) { opponents[i].shown[j].board = table.boardCards }
            } else {
                opponents[i].shown.append(ShownHand(round:round,time:time,cards:cards,board:table.boardCards))
            }
        }
    }
    private func beginRound() {
        round = UUID(); roundBoard = []; roundHasHeroDeal = false; revealCandidates.removeAll(); rejectedRevealRounds.removeAll()
        heroScanner = ActionScanner(); actionScanners.removeAll()
    }
    private func recordActions(_ table: TableObservation,previous old: TableObservation,hand: LiveHand?,time: Date) {
        guard table.boardCards == old.boardCards else { return }
        let street = table.boardCards.count
        guard [0,3,4,5].contains(street) else { return }
        for i in opponents.indices {
            let profile = opponents[i]
            guard let seat = table.seats.first(where:{ !$0.isHero && Self.sameSeat($0.bounds,profile.bounds) }) else { actionScanners[profile.id]?.interrupt(); continue }
            let previous = old.seats.first(where:{ !$0.isHero && Self.sameSeat($0.bounds,profile.bounds) })
            var scanner = actionScanners[profile.id] ?? ActionScanner()
            if let event = scanner.accept(seat,previous:previous,round:round,street:street,time:time) { opponents[i].actions.append(event) }
            actionScanners[profile.id] = scanner
        }
        guard roundHasHeroDeal, let i = handIndex, let hero = table.hero else { heroScanner.interrupt(); return }
        if let hand, !hand.isReview, hand.hole.map({ $0.card.code }).sorted() != archive.hands[i].hole { heroScanner.interrupt(); return }
        if let event = heroScanner.accept(hero,previous:old.hero,round:round,street:street,time:time) {
            archive.hands[i].actions = (archive.hands[i].actions ?? [])+[event]; dirty = true
        }
    }
    private func observeOwn(hand: LiveHand?,table: TableObservation,old: TableObservation,time: Date) {
        guard let hero = table.hero else { return }
        let stableStack = hero.stackCents != nil && hero.stackCents == old.hero?.stackCents && hero.betCents == old.hero?.betCents
        if hero.activity == .folded && old.hero?.activity == .folded { missingHeroFrames += 1 } else if hero.activity == .active { missingHeroFrames = 0 }
        if let hand, !hand.isReview {
            let hole = hand.hole.map { $0.card.code }.sorted()
            let board = hand.board.map { $0.card.code }
            let current = currentHand
            // A brief missing-card reading alone cannot prove another preflop deal.
            // Identical back-to-back preflop cards may merge until a clearer boundary is observed.
            let newDeal = current == nil || current?.hole != hole || (board.isEmpty && !(current?.board.isEmpty ?? true))
            if newDeal {
                // Do not close the previous hand with a one-frame amount or a mixture of old/new stacks.
                if board.isEmpty && !stableStack { return }
                // A confirmed new preflop hand is a bankroll checkpoint BEFORE any street sweep.
                var chips: Int?
                if board.isEmpty && stableStack, let stack = hero.stackCents { chips = stack+(hero.betCents ?? 0) }
                closeOwnHand(chips:chips,time:time,reason:"Next observed deal")
                if roundHasHeroDeal { beginRound() }
                roundHasHeroDeal = true
                var record = OwnHandRecord(started:time,hole:hole,board:board,startedPreflop:board.isEmpty,openingChips:chips)
                record.sawFlop = board.count >= 3; record.reachedRiver = board.count == 5
                archive.hands.append(record); currentHandID = record.id; dirty = true
                if let chips { checkpoint(chips,time:time) }
                addObservation("Cards confirmed",table:table,time:time)
            }
            if let i = handIndex {
                if archive.hands[i].board != board { archive.hands[i].board = board; dirty = true; addObservation("Board updated",table:table,time:time) }
                if board.count >= 3 { archive.hands[i].sawFlop = true }
                if board.count == 5 { archive.hands[i].reachedRiver = true }
                // Allow an opening checkpoint once stacks have stabilized, only while this deal is preflop.
                if archive.hands[i].openingChips == nil, archive.hands[i].startedPreflop, board.isEmpty, stableStack, let stack = hero.stackCents {
                    let chips = stack+(hero.betCents ?? 0)
                    archive.hands[i].openingChips = chips; checkpoint(chips,time:time); dirty = true
                }
            }
        }
        if let i = handIndex {
            if roundHasHeroDeal, table.boardCards == old.boardCards,
               table.boardCards.count > archive.hands[i].board.count,
               table.boardCards.map({ $0.code }).starts(with:archive.hands[i].board) {
                archive.hands[i].board = table.boardCards.map(\.code); dirty = true
                addObservation("Visible board continued",table:table,time:time)
            }
            if let hand, hand.isReview, hand.hole.map({ $0.card.code }).sorted() == archive.hands[i].hole,
               hand.board.count > archive.hands[i].board.count,
               hand.board.map({ $0.card.code }).starts(with:archive.hands[i].board) {
                archive.hands[i].board = hand.board.map { $0.card.code }; dirty = true
                addObservation("Visible board after saved cards",table:table,time:time)
            }
            if missingHeroFrames >= 2 && !archive.hands[i].cardsDisappeared {
                archive.hands[i].cardsDisappeared = true; dirty = true
                addObservation("Cards disappeared · possible fold / muck",table:table,time:time)
            }
            // Stack/bet movements are observations, not invented call/raise classifications.
            if stableStack, let stack = hero.stackCents,
               (archive.hands[i].observations.last(where:{ $0.stackCents != nil })?.stackCents != stack || archive.hands[i].observations.last(where:{ $0.stackCents != nil })?.betCents != hero.betCents) {
                addObservation("Chips changed",table:table,time:time)
            }
        }
    }
    private var handIndex: Int? { currentHandID.flatMap { id in archive.hands.firstIndex { $0.id == id } } }
    private var tableIndex: Int? { ownTableID.flatMap { id in archive.tables.firstIndex { $0.id == id } } }
    private func checkpoint(_ chips: Int,time: Date) {
        guard let i = tableIndex else { return }
        if archive.tables[i].baselineCents == nil { archive.tables[i].baselineCents = chips }
        archive.tables[i].latestCents = chips; archive.tables[i].checkpoint = time
        archive.tables[i].appliedCashCents = archive.tables[i].adjustments.reduce(0) { $0+$1.cents }
        dirty = true
    }
    private func closeOwnHand(chips: Int?,time: Date,reason: String) {
        guard let i = handIndex else { return }
        archive.hands[i].ended = time; archive.hands[i].completion = reason
        if let chips, let opening = archive.hands[i].openingChips {
            archive.hands[i].netCents = chips-opening-(tableRecord?.pendingCashCents ?? 0)
        }
        currentHandID = nil; dirty = true
    }
    private func addObservation(_ note: String,table: TableObservation,time: Date) {
        guard let i = handIndex, archive.hands[i].observations.count < 500 else { return }
        archive.hands[i].observations.append(OwnObservation(time:time,street:archive.hands[i].board.count,note:note,
            stackCents:table.hero?.stackCents,betCents:table.hero?.betCents,potCents:table.potCents))
        dirty = true
    }
    func recordDecision(_ display: AnalysisDisplay,current: Bool) {
        guard current, let i = handIndex, let hand = display.hand, !hand.isReview,
              hand.hole.map({ $0.card.code }).sorted() == archive.hands[i].hole,
              let equity = display.decisionEquity, let ev = display.estimate,
              let call = display.decisionCallDollars, let pot = display.eligiblePotDollars,
              (0...999_999.99).contains(call), (0...999_999.99).contains(pot) else { return }
        let cents = Int((call*100).rounded()), potCents = Int((pot*100).rounded())
        let last = archive.hands[i].observations.last(where:{ $0.note == "Decision estimate" })
        if last?.street == hand.board.count && last?.equity == equity && last?.callCents == cents && last?.potCents == potCents && last?.opponents == display.opponents { return }
        guard archive.hands[i].observations.count < 500 else { return }
        archive.hands[i].observations.append(OwnObservation(time:Date(),street:hand.board.count,note:"Decision estimate",equity:equity,callEV:ev.value,callCents:cents,opponents:display.opponents))
        archive.hands[i].observations[archive.hands[i].observations.count-1].potCents = potCents
        dirty = true; saveIfNeeded(time:Date())
    }
    @discardableResult func addCashAdjustment(cents: Int,time: Date = Date()) -> Bool {
        guard cents != 0, (-99_999_999...99_999_999).contains(cents), let i = tableIndex else { return false }
        guard archive.tables[i].baselineCents != nil else { status = "Wait for the first preflop balance checkpoint before recording cash changes."; return false }
        archive.tables[i].adjustments.append(CashAdjustment(time:time,cents:cents)); dirty = true
        status = "Cash change saved; adjusted net updates at the next preflop checkpoint."
        saveIfNeeded(time:time,force:true); return true
    }
    func endTable(_ reason: String = "Table ended · opponent records cleared",time: Date = Date()) {
        closeOwnHand(chips:nil,time:time,reason:"Capture / table ended · result unmeasured")
        if let i = tableIndex { archive.tables[i].ended = time; dirty = true }
        ownTableID = nil; opponents.removeAll(); previous = nil; lastTable = nil; lastHero = nil; missingFrames.removeAll()
        revealCandidates.removeAll(); markerVisible.removeAll(); pendingBoard = nil; beginRound(); missingHeroFrames = 0
        active = false; status = reason; saveIfNeeded(time:time,force:true)
    }
    func saveIfNeeded(time: Date,force: Bool = false) {
        guard dirty, writable, force || time.timeIntervalSince(lastSaved) >= 2 else { return }
        dirty = false; lastSaved = time
        store.save(archive) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                if success { self.storageError = nil }
                else { self.storageError = "History could not be saved. Tracking continues in memory; check available disk space."; self.dirty = true }
            }
        }
    }
}
