import Foundation
import Testing
@testable import GlassConnectionKit

struct GlassConnectionLinkTests {
    private let id = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!

    @Test func acceptedRoutesReferOnlyToSavedIdentity() throws {
        #expect(GlassConnectionLink(url: try #require(URL(string: "glassdb://connect?connectionID=\(id)"))) == .database(connectionID: id))
        #expect(GlassConnectionLink(url: try #require(URL(string: "glassh://connect?serverID=\(id)"))) == .ssh(serverID: id))
    }

    @Test func constructedURLsRoundTripEveryServiceWithoutAdditionalPayload() throws {
        for link: GlassConnectionLink in [.ssh(serverID: id), .database(connectionID: id), .desktop(connectionID: id)] {
            let url = try #require(link.url)
            #expect(GlassConnectionLink(url: url) == link)
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.count == 1)
        }
    }

    @Test func rejectsAuthorityChangesCommandsSecretsDuplicatesAndInvalidIdentity() throws {
        let suffix = "connectionID=\(id)"
        for value in [
            "glassdb://other?\(suffix)", "https://connect?\(suffix)",
            "glassdb://user@connect?\(suffix)", "glassdb://connect:123?\(suffix)",
            "glassdb://connect/path?\(suffix)", "glassdb://connect?\(suffix)#fragment",
            "glassdb://connect?\(suffix)&password=secret", "glassdb://connect?\(suffix)&sql=DROP",
            "glassdb://connect?\(suffix)&\(suffix)", "glassdb://connect?serverID=\(id)",
            "glassdb://connect?connectionID=invalid", "glassdb://connect",
            "glassdt://connect?connectionID=invalid", "glassdt://connect?\(suffix)&password=secret"
        ] {
            #expect(GlassConnectionLink(url: try #require(URL(string: value))) == nil)
        }
    }
}
