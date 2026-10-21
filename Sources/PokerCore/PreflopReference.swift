import Foundation

/// Exhaustive final-category counts only. No external matchup equity is trusted.
public struct PreflopReference: Decodable, Sendable {
    public struct Entry: Decodable, Sendable {
        public let categories: [Int]
    }
    public let schema: Int
    public let source: String
    public let commit: String
    public let boards: Int
    public let classes: [String:Entry]
    public static let shared: PreflopReference? = {
        let url=Bundle.main.url(forResource:"preflop-reference",withExtension:"json") ?? Bundle.module.url(forResource:"preflop-reference",withExtension:"json",subdirectory:"Resources")
        guard let url, let data=try? Data(contentsOf:url), let reference=try? JSONDecoder().decode(Self.self,from:data),
              reference.schema==1, reference.classes.count==169,
              reference.boards==2_118_760,
              reference.classes.values.allSatisfy({ $0.categories.count==9 && $0.categories.allSatisfy { $0>=0 } && $0.categories.reduce(0,+)==reference.boards }) else { return nil }
        return reference
    }()
}
