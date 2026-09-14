import Testing
@testable import GlassConnectionUI

@Suite("Glass tag list and suggestions")
struct GlassTagFieldTests {
    @Test func normalisationTrimsDropsEmptiesAndDedupesCaseInsensitively() {
        let tags = GlassTagList.normalized(["  Clients ", "", "clients", "Prod", "prod", " ", "Home"])
        #expect(tags == ["Clients", "Prod", "Home"], "first spelling wins, order of entry kept")
    }

    @Test func addingSplitsOnCommasAndNewlines() {
        let tags = GlassTagList.adding("lab, Clients\nprod,,", to: ["Prod"])
        #expect(tags == ["Prod", "lab", "Clients"])
        #expect(GlassTagList.contains(tags, " CLIENTS "))
        #expect(!GlassTagList.contains(tags, "home"))
    }

    @Test func suggestionsRankPrefixBeforeSubstringAndExcludeChosen() {
        let vocabulary = ["Production", "Clients", "Acme Client", "Lab", "production"]
        let all = GlassTagSuggestions.matches(for: "", in: vocabulary, excluding: ["lab"])
        #expect(all == ["Production", "Clients", "Acme Client"], "empty query offers the vocabulary minus chosen, deduped")
        let cl = GlassTagSuggestions.matches(for: "cl", in: vocabulary, excluding: [])
        #expect(cl == ["Clients", "Acme Client"], "prefix match first, then substring")
        #expect(GlassTagSuggestions.matches(for: "zzz", in: vocabulary, excluding: []).isEmpty)
        #expect(GlassTagSuggestions.matches(for: "", in: vocabulary, excluding: [], limit: 2) == ["Production", "Clients"])
    }
}
