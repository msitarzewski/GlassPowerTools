import Testing
import Foundation
import GlassEditorCore
@testable import GlassEditorUI

@Suite("Asking for the keyboard")
@MainActor
struct GlassEditorKeyboardRequestTests {
    private func model() -> GlassEditorModel {
        GlassEditorModel(snapshot: DocumentLoader.make(content: "one\ntwo\n",
                                                       origin: .ephemeral(id: UUID())))
    }

    @Test func aRequestCarriesWhatWasAskedFor() {
        let model = model()
        #expect(!model.keyboardRequest.wantsKeyboard)

        model.requestKeyboard(true)
        #expect(model.keyboardRequest.wantsKeyboard)

        model.requestKeyboard(false)
        #expect(!model.keyboardRequest.wantsKeyboard)
    }

    @Test func askingTwiceForTheSameThingIsTwoRequests() {
        // The user can dismiss the keyboard with the system's own swipe between two presses of
        // Show, and a control that works every other time is worse than none (rule 45).
        let model = model()
        model.requestKeyboard(true)
        let first = model.keyboardRequest
        model.requestKeyboard(true)
        #expect(model.keyboardRequest != first, "the second ask has to reach the view too")
        #expect(model.keyboardRequest.serial == first.serial + 1)
    }
}
