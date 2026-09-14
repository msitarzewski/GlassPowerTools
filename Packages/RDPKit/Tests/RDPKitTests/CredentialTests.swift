@testable import RDPKit
import Foundation
import Testing

@Test func qualifiedUsernameOmitsEmptyDomain() {
    let credentials = RDPCredentials(username: "rdp-user", domain: "", password: "secret")

    #expect(credentials.qualifiedUsername == "rdp-user")
}

@Test func qualifiedUsernameIncludesDomainWhenPresent() {
    let credentials = RDPCredentials(username: "rdp-user", domain: "KDE", password: "secret")

    #expect(credentials.qualifiedUsername == "KDE\\rdp-user")
}

@Test func credentialValidationReturnsNilWhenFieldsAreEmpty() throws {
    let credentials = try RDPCredentials.validated(username: "  ", domain: "  ", password: "")

    #expect(credentials == nil)
}

@Test func credentialValidationTrimsUsernameAndDomain() throws {
    let validatedCredentials = try RDPCredentials.validated(
        username: "  rdp-user  ",
        domain: "  KDE  ",
        password: "secret"
    )
    let credentials = try #require(validatedCredentials)

    #expect(credentials.username == "rdp-user")
    #expect(credentials.domain == "KDE")
    #expect(credentials.password == "secret")
}

@Test func credentialValidationDropsEmptyDomain() throws {
    let validatedCredentials = try RDPCredentials.validated(
        username: "rdp-user",
        domain: "  ",
        password: "secret"
    )
    let credentials = try #require(validatedCredentials)

    #expect(credentials.domain == nil)
    #expect(credentials.qualifiedUsername == "rdp-user")
}

@Test func credentialValidationRejectsIncompleteCredentials() {
    #expect(
        throws: RDPCredentialValidationError.missingUsernameOrPassword,
        performing: {
            _ = try RDPCredentials.validated(username: "", domain: "KDE", password: "")
        }
    )
    #expect(
        throws: RDPCredentialValidationError.missingUsernameOrPassword,
        performing: {
            _ = try RDPCredentials.validated(username: "rdp-user", domain: "", password: "")
        }
    )
}

@Test func incompleteCredentialErrorRemainsActionableThroughFoundation() throws {
    do {
        _ = try RDPCredentials.validated(username: "rdp-user", password: "")
        Issue.record("An account without a password must fail validation.")
    } catch {
        #expect(error.localizedDescription == "Username and password are required when credentials are provided.")
        #expect((error as NSError).localizedDescription == error.localizedDescription)
    }
}
