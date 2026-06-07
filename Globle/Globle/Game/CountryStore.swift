import Foundation

extension String {
    /// Lowercased and stripped of accents, for forgiving search ("Côte" matches "cote").
    var searchFolded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Loads the bundled country data and powers name search / autocomplete.
final class CountryStore {
    static let shared = CountryStore()

    let all: [Country]
    let targets: [Country]
    private let byId: [String: Country]
    private let foldedName: [String: String]          // id -> folded display name
    private let foldedTokens: [String: [String]]      // id -> folded search tokens

    private init() {
        guard let url = Bundle.main.url(forResource: "countries", withExtension: "json") else {
            fatalError("countries.json is missing from the app bundle. Add Globle/Resources/countries.json to the target's Copy Bundle Resources phase.")
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Country].self, from: data)
            all = decoded.sorted { $0.name < $1.name }
        } catch {
            fatalError("Could not decode countries.json: \(error)")
        }
        targets = all.filter { $0.target }
        byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        foldedName = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.name.searchFolded) })
        foldedTokens = Dictionary(uniqueKeysWithValues: all.map { country in
            (country.id, Set(country.aliases.map { $0.searchFolded } + [country.name.searchFolded]).sorted())
        })
    }

    func country(id: String) -> Country? { byId[id] }

    /// Autocomplete suggestions for `query`, best matches first.
    /// `excluding` lets the caller hide already-guessed countries.
    func search(_ query: String, excluding excluded: Set<String> = [], limit: Int = 10) -> [Country] {
        let q = query.searchFolded
        guard !q.isEmpty else { return [] }

        var scored: [(country: Country, rank: Int)] = []
        for country in all where !excluded.contains(country.id) {
            let name = foldedName[country.id] ?? ""
            let tokens = foldedTokens[country.id] ?? []
            var rank = Int.max
            if name == q { rank = 0 }
            else if name.hasPrefix(q) { rank = 1 }
            else if tokens.contains(where: { $0.hasPrefix(q) }) { rank = 2 }
            else if name.contains(q) { rank = 3 }
            else if tokens.contains(where: { $0.contains(q) }) { rank = 4 }
            if rank != Int.max { scored.append((country, rank)) }
        }
        return scored
            .sorted { lhs, rhs in
                lhs.rank != rhs.rank ? lhs.rank < rhs.rank
                    : (lhs.country.pop != rhs.country.pop ? lhs.country.pop > rhs.country.pop
                                                          : lhs.country.name < rhs.country.name)
            }
            .prefix(limit)
            .map(\.country)
    }

    /// Exact-name resolution used when the player presses return.
    func exactMatch(_ query: String, excluding excluded: Set<String> = []) -> Country? {
        let q = query.searchFolded
        guard !q.isEmpty else { return nil }
        return all.first { country in
            guard !excluded.contains(country.id) else { return false }
            if (foldedName[country.id] ?? "") == q { return true }
            return (foldedTokens[country.id] ?? []).contains(q)
        }
    }
}
