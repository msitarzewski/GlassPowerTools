@testable import RDPKit
import Testing

@Test func connectionIdentityFormatsDisplayName() {
    #expect(RDPConnectionIdentity(host: "server.local").displayName == "server.local")
    #expect(
        RDPConnectionIdentity(
            host: "server.local",
            port: 3390,
            username: "casey"
        ).displayName == "casey@server.local:3390"
    )
    #expect(
        RDPConnectionIdentity(
            host: "server.local",
            username: "casey",
            domain: "LAB"
        ).displayName == "LAB\\casey@server.local"
    )
}

@Test func connectionIdentityFormatsCredentialAccountName() {
    #expect(RDPConnectionIdentity(host: "server.local").credentialAccountName == nil)
    #expect(
        RDPConnectionIdentity(
            host: "server.local",
            username: "casey"
        ).credentialAccountName == "casey@server.local:3389"
    )
    #expect(
        RDPConnectionIdentity(
            host: "server.local",
            port: 3390,
            username: "casey",
            domain: "LAB"
        ).credentialAccountName == "LAB\\casey@server.local:3390"
    )
}

@Test func connectionIdentityTrimsComponents() {
    let identity = RDPConnectionIdentity(
        host: "  Server.Local  ",
        port: 3389,
        username: "  casey  ",
        domain: "  LAB  "
    )

    #expect(identity.host == "Server.Local")
    #expect(identity.username == "casey")
    #expect(identity.domain == "LAB")
    #expect(identity.displayName == "LAB\\casey@Server.Local")
}

@Test func connectionIdentityMatchesNormalizedHostAndAccount() {
    let lhs = RDPConnectionIdentity(
        host: "SERVER.LOCAL",
        port: 3389,
        username: "casey",
        domain: ""
    )
    let rhs = RDPConnectionIdentity(
        host: "server.local",
        port: 3389,
        username: "casey",
        domain: nil
    )
    let differentAccount = RDPConnectionIdentity(
        host: "server.local",
        port: 3389,
        username: "casey",
        domain: "LAB"
    )

    #expect(lhs.hasSameConnectionIdentity(as: rhs))
    #expect(lhs.hasSameConnectionIdentity(as: differentAccount) == false)
}

@Test func connectionTargetValidatesHostAndPortText() throws {
    let target = try RDPConnectionTarget(host: "  server.local  ", portText: " 3390 ")

    #expect(target.host == "server.local")
    #expect(target.port == 3390)
}

@Test func connectionTargetRejectsMissingHostAndInvalidPort() {
    #expect(
        throws: RDPConnectionValidationError.missingHost,
        performing: {
            _ = try RDPConnectionTarget(host: "  ", portText: "3389")
        }
    )
    #expect(
        throws: RDPConnectionValidationError.invalidPort,
        performing: {
            _ = try RDPConnectionTarget(host: "server.local", portText: "99999")
        }
    )
}

@Test func desktopSizeValidatesProtocolRange() throws {
    let size = try RDPDesktopSize(widthText: " 1920 ", heightText: " 1080 ")

    #expect(size.width == 1920)
    #expect(size.height == 1080)
}

@Test func desktopSizeRejectsInvalidOrOutOfRangeValues() {
    #expect(
        throws: RDPConnectionValidationError.invalidDesktopSize,
        performing: {
            _ = try RDPDesktopSize(widthText: "639", heightText: "1080")
        }
    )
    #expect(
        throws: RDPConnectionValidationError.invalidDesktopSize,
        performing: {
            _ = try RDPDesktopSize(widthText: "1920", heightText: "not-a-height")
        }
    )
}
