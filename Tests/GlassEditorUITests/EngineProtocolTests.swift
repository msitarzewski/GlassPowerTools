import Testing
@testable import GlassEditorUI
import GlassEditorCore

@Suite("GlassEditorUI target links")
struct EngineProtocolTests {
    @Test("UI target compiles against Core contracts")
    func targetLinks() {
        let config = GlassEditorConfiguration()
        #expect(config.highlightDebounceMilliseconds == 75)
        #expect(config.minimumContrastRatio == 4.5)
    }
}
