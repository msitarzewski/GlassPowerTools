import Testing
@testable import GlassEditorCore

@Suite("Shared contract types")
struct ContractTests {
    @Test("TextEdit length math")
    func textEditLengths() {
        let insert = TextEdit.insert("héllo", at: 3)
        #expect(insert.replacementRange == 3..<3)
        #expect(insert.insertedLength == 5)
        #expect(insert.lengthDelta == 5)

        let delete = TextEdit.delete(2..<7)
        #expect(delete.lengthDelta == -5)

        // Astral-plane character counts as two UTF-16 units.
        let emoji = TextEdit.insert("🙂", at: 0)
        #expect(emoji.insertedLength == 2)
    }

    @Test("ContentDigest round-trips hex")
    func digestHex() {
        let hex = String(repeating: "ab", count: 32)
        let digest = ContentDigest(hexString: hex)
        #expect(digest?.hexString == hex)
        #expect(ContentDigest(hexString: "abcd") == nil)
        #expect(ContentDigest(bytes: [1, 2, 3]) == nil)
    }

    @Test("WCAG contrast ratio: black on white is 21")
    func contrastMath() {
        let ratio = ResolvedColor.contrastRatio(.black, .white)
        #expect(abs(ratio - 21.0) < 0.01)
        #expect(ResolvedColor.contrastRatio(.white, .white) == 1.0)
    }

    @Test("Unknown file extensions resolve to plaintext, never a guess")
    func extensionFallback() {
        #expect(LanguageID.forFileExtension("xyz") == .plaintext)
        #expect(LanguageID.forFileExtension("SQL") == .sql)
        #expect(LanguageID.forFileExtension("yml") == .yaml)
    }
}
