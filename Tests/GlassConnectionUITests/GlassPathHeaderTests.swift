import Testing
@testable import GlassConnectionUI

@Suite("The path header says where you are")
struct GlassPathHeaderTests {
    @Test func namesTheFolderAndLeavesItOutOfThePathBeneath() {
        let location = GlassPathLocation(path: "/home/ann/projects/sensor")
        #expect(location.name == "sensor")
        #expect(location.parent == "/home/ann/projects", "the folder is not repeated beneath itself")
    }

    @Test func aTrailingSeparatorIsTheSameFolder() {
        #expect(GlassPathLocation(path: "/home/ann/") == GlassPathLocation(path: "/home/ann"))
        #expect(GlassPathLocation(path: "/home/ann///").name == "michael")
    }

    @Test func theRootHasANameAndNoParent() {
        let root = GlassPathLocation(path: "/")
        #expect(root.name == "/")
        #expect(root.parent.isEmpty)
    }

    @Test func aChildOfTheRootKeepsTheRootAsItsParent() {
        let home = GlassPathLocation(path: "/home")
        #expect(home.name == "home")
        #expect(home.parent == "/", "an empty lead would hide the one fact there is")
    }

    @Test func emptyAndBlankPathsReadAsTheRootRatherThanAsNothing() {
        #expect(GlassPathLocation(path: "").name == "/")
        #expect(GlassPathLocation(path: "   ").name == "/")
    }

    @Test func aSingleRelativeComponentIsAllName() {
        let relative = GlassPathLocation(path: "sensor")
        #expect(relative.name == "sensor")
        #expect(relative.parent.isEmpty)
    }

    @Test func anAbbreviatedHomePathKeepsItsAbbreviation() {
        // The editor spells a local path with `~` before handing it over; the header must not
        // undo that by insisting on a leading separator.
        let location = GlassPathLocation(path: "~/Software/glass/GlassPowerTools")
        #expect(location.name == "GlassPowerTools")
        #expect(location.parent == "~/Software/glass")
    }

    @Test func homeBecomesATildeAndKeepsTheSeparatorAfterIt() {
        // The editor's own copy kept the last character of home instead of the separator, so a
        // simulator's container path read `~F/Documents`. Photographed before it was moved here.
        let home = "/Users/ann"
        #expect(GlassPathLocation.abbreviatingHome("\(home)/Software/glass", home: home)
                == "~/Software/glass")
        #expect(GlassPathLocation.abbreviatingHome(home, home: home) == "~")
    }

    @Test func aPathOutsideHomeIsLeftAlone() {
        let home = "/Users/ann"
        #expect(GlassPathLocation.abbreviatingHome("/etc/hosts", home: home) == "/etc/hosts")
        // A sibling whose name merely starts with home's is not inside it.
        #expect(GlassPathLocation.abbreviatingHome("/Users/michaela/notes", home: home)
                == "/Users/michaela/notes")
    }
}
