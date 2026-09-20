import Testing
import Foundation
import GlassEditorCore
@testable import GlassEditor

@Suite("Text settings cascade: file over project over global")
struct GlassEditorTextOverridesTests {
    private var global: GlassEditorConfiguration {
        var configuration = GlassEditorConfiguration()
        configuration.fontSize = 13
        configuration.showsLineNumbers = true
        configuration.wrapsLines = true
        return configuration
    }

    @Test func nothingOverriddenIsTheGlobalAnswer() {
        let resolved = GlassEditorTextOverrides.resolve(global: global, project: nil, file: nil)
        #expect(resolved.fontSize == 13)
        #expect(resolved.showsLineNumbers)
        #expect(resolved.wrapsLines)
    }

    @Test func aProjectChangesOnlyWhatItSets() {
        let project = GlassEditorTextOverrides(wrapsLines: false)
        let resolved = GlassEditorTextOverrides.resolve(global: global, project: project, file: nil)
        #expect(!resolved.wrapsLines, "the project disagreed about wrapping")
        #expect(resolved.fontSize == 13, "and said nothing about size, so the global answer stands")
        #expect(resolved.showsLineNumbers)
    }

    @Test func aFileOutranksItsProject() {
        let project = GlassEditorTextOverrides(fontSize: 11, wrapsLines: false)
        let file = GlassEditorTextOverrides(wrapsLines: true)
        let resolved = GlassEditorTextOverrides.resolve(global: global, project: project, file: file)
        #expect(resolved.wrapsLines, "the file is the last word")
        #expect(resolved.fontSize == 11, "the project's size survives a file that says nothing about size")
    }

    @Test func clearingALevelFallsBackRatherThanPinningTodaysValue() {
        // The whole reason each level stores optionals: change the default and everything that
        // never disagreed follows it.
        var project = GlassEditorTextOverrides(fontSize: 11)
        #expect(GlassEditorTextOverrides.resolve(global: global, project: project, file: nil).fontSize == 11)
        project.fontSize = nil
        #expect(project.isEmpty)
        #expect(GlassEditorTextOverrides.resolve(global: global, project: project, file: nil).fontSize == 13)
    }

    @Test func aSizeFromAnotherDeviceIsClampedToWhatThisBuildAllows() {
        let absurd = GlassEditorTextOverrides(fontSize: 400)
        let resolved = absurd.applied(to: global)
        #expect(resolved.fontSize == GlassEditorTextOverrides.fontSizeRange.upperBound)
        #expect(GlassEditorTextOverrides(fontSize: 1).applied(to: global).fontSize
                == GlassEditorTextOverrides.fontSizeRange.lowerBound)
    }

    @Test func whatAFileInheritsIsItsProjectsAnswer() {
        let project = GlassEditorTextOverrides(fontSize: 11)
        let inherited = GlassEditorTextOverrides.inherited(global: global, project: project, forFile: true)
        #expect(inherited.fontSize == 11, "\"Default\" in a file's settings means the project's size")
        let forProject = GlassEditorTextOverrides.inherited(global: global, project: project, forFile: false)
        #expect(forProject.fontSize == 13, "and in a project's settings it means the app's")
    }

    @Test @MainActor func aProjectsOverridesSurviveTheRecordTheyTravelIn() throws {
        // They ride the synced payload, so they have to decode from a record written before the
        // field existed — and be there when one written today is read back.
        let old = #"{"id":"\#(UUID().uuidString)","path":"/work/thing","displayName":"thing","openedAt":0}"#
        let decoded = try JSONDecoder().decode(GlassEditorProject.self, from: Data(old.utf8))
        #expect(decoded.textOverrides == nil, "a record from before the field is not a broken record")

        var project = decoded
        project.textOverrides = GlassEditorTextOverrides(fontSize: 11, wrapsLines: false)
        let round = try JSONDecoder().decode(GlassEditorProject.self,
                                             from: JSONEncoder().encode(project))
        #expect(round.textOverrides?.fontSize == 11)
        #expect(round.textOverrides?.wrapsLines == false)
        #expect(round.textOverrides?.showsLineNumbers == nil)
    }
}
