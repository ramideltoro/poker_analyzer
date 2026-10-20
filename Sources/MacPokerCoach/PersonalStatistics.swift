import Foundation

struct PersonalStatistics {
    var archive: OwnPlayArchive
    var measured: [OwnHandRecord] { archive.hands.filter { $0.netCents != nil }.sorted { $0.started < $1.started } }
    var actions: ActionStatistics { ActionStatistics(events:archive.hands.flatMap { $0.actions ?? [] }) }
    var grossWon: Int { measured.compactMap(\.netCents).filter { $0 > 0 }.reduce(0,+) }
    var grossLost: Int { -measured.compactMap(\.netCents).filter { $0 < 0 }.reduce(0,+) }
    var wins: Int { measured.filter { ($0.netCents ?? 0) > 0 }.count }
    var losses: Int { measured.filter { ($0.netCents ?? 0) < 0 }.count }
    var even: Int { measured.filter { $0.netCents == 0 }.count }
    var winRate: Double? { measured.isEmpty ? nil : Double(wins)/Double(measured.count) }
    var averageCents: Double? { measured.isEmpty ? nil : Double(grossWon-grossLost)/Double(measured.count) }
    var largestWin: Int? { measured.compactMap(\.netCents).filter { $0 > 0 }.max() }
    var largestLoss: Int? { measured.compactMap(\.netCents).filter { $0 < 0 }.min() }
    var trend: [Int] {
        var total = 0, points = [0]
        for hand in measured { total += hand.netCents ?? 0; points.append(total) }
        return points
    }
    var drawdown: Int? {
        guard !measured.isEmpty else { return nil }
        var peak = 0, largest = 0
        for point in trend { peak = max(peak,point); largest = max(largest,peak-point) }
        return largest
    }
}
