//
//  DesktopCoreTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/DesktopCoreTests.swift` on 2026-09-27.
//
//  Adapted:
//  - `GlassDesktopCore` is `GlassDesktop` here.
//  - `DesktopRepository` is no longer a file-backed actor over `connections.json`; since D26 it is a
//    `@MainActor` view of the shell's catalog (`Sources/GlassDesktop/DesktopRepository.swift`). The
//    round-trip and invalid-save tests run against a `GlassInMemoryServiceStore`, and "reload"
//    means a second repository over the same store, as a relaunch would be. "Does not create
//    storage" became "writes nothing into the catalog".
//  - Two tests were dropped because what they guarded no longer exists: the corrupted-file and the
//    unsupported-version/duplicate-identity tests checked `connections.json`'s own format (bytes,
//    a schema `version`, two records with one id in one array). The catalog stores one
//    configuration per endpoint id, so none of the three can arise (D26).
//  - The navigation tests keep glassDT's rejected URLs and add the same four faults in the form the
//    link actually has (`glassdt://connect?connectionID=…`), since glassDT's inputs used a host
//    (`connection`) that is rejected before any of the faults they name is reached.
//  - Example host names are neutral.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassShell
@testable import GlassDesktop

@Test func normalizesConnectionWithoutChangingIdentity() throws {
    var connection = DesktopConnection(name: "  Workstation  ", host: " [::1] ", username: "user")
    connection.tags = [" Work ", "work", "", "Lab"]
    let result = try connection.validated()
    #expect(result.name == "Workstation")
    #expect(result.host == "::1")
    #expect(result.address == "[::1]:3389")
    #expect(result.tags == ["Work", "Lab"])
    #expect(result.id == connection.id)
    #expect(result.credentialID == connection.credentialID)
}

@Test(arguments: ["", "rdp://host", "user@host", "two hosts", "host\nname", "a/b"])
func rejectsUnsafeHost(host: String) {
    #expect(throws: DesktopError.invalidHost) {
        try DesktopConnection(name: "Test", host: host).validated()
    }
}

@Test func certificateFingerprintsAreValidated() throws {
    var connection = DesktopConnection(name: "Test", host: "localhost")
    connection.certificateSHA256 = String(repeating: "AA:", count: 31) + "AA"
    #expect(try connection.validated().certificateSHA256 == String(repeating: "aa", count: 32))
    connection.certificateSHA256 = "not a certificate"
    #expect(throws: DesktopError.invalidCertificate) { try connection.validated() }
}

@Test(arguments: [DesktopSize(width: 199, height: 200), DesktopSize(width: 201, height: 200),
                  DesktopSize(width: 8194, height: 200), DesktopSize(width: 8192, height: 8192),
                  DesktopSize(width: Int.max, height: Int.max), DesktopSize(width: 200, height: -1)])
func rejectsUnsafeDesktop(size: DesktopSize) {
    #expect(throws: DesktopError.invalidDesktop) { try size.validate() }
}

@Test(arguments: [(100.0, 100.0), (1921, 1080), (16000, 9000), (1000, 9000), (0, 0)])
func fittingDesktopAlwaysRespectsLimits(dimensions: (Double, Double)) throws {
    let result = DesktopSize.fitting(width: dimensions.0, height: dimensions.1, scale: 2)
    try result.validate()
    #expect(result.width.isMultiple(of: 2))
}

@Test func rejectsNonfiniteGeometry() {
    #expect(DesktopSize.fitting(width: .nan, height: 800) == .standard)
    #expect(DesktopCoordinates.map(x: .infinity, y: 3, viewWidth: 100, viewHeight: 100, desktop: .standard) == nil)
    #expect(DesktopCoordinates.map(x: 0, y: 0, viewWidth: 0, viewHeight: 100, desktop: .standard) == nil)
}

@Test func mapsLetterboxedDesktopAndDraggedPointer() {
    let desktop = DesktopSize(width: 1920, height: 1080)
    #expect(DesktopCoordinates.map(x: 500, y: 500, viewWidth: 1000, viewHeight: 1000, desktop: desktop) == .init(x: 960, y: 540))
    #expect(DesktopCoordinates.map(x: 500, y: 100, viewWidth: 1000, viewHeight: 1000, desktop: desktop) == nil)
    #expect(DesktopCoordinates.map(x: 2000, y: -40, viewWidth: 1000, viewHeight: 1000, desktop: desktop, clamp: true) == .init(x: 1919, y: 0))
}

@Test func originalPixelsRemainOpaqueRegardlessOfMask() {
    #expect(PresentationSettings.alpha(red: 0, green: 0, blue: 0, reference: .zero, mode: .original, threshold: 1, feather: 0) == 1)
    #expect(PresentationSettings.alpha(red: 0, green: 0, blue: 0, reference: nil, mode: .removeWallpaper, threshold: 1, feather: 0) == 1)
}

@Test func masksOnlyAccordingToChosenReference() {
    #expect(PresentationSettings.alpha(red: 0, green: 0, blue: 0, reference: nil, mode: .removeBlack, threshold: 0.02, feather: 0.02) == 0)
    #expect(PresentationSettings.alpha(red: 1, green: 0, blue: 0, reference: nil, mode: .removeBlack, threshold: 0.02, feather: 0.02) == 1)
    #expect(PresentationSettings.alpha(red: 0.4, green: 0.5, blue: 0.6, reference: SIMD3(0.4, 0.5, 0.6), mode: .removeWallpaper, threshold: 0.02, feather: 0.02) == 0)
    let feathered = PresentationSettings.alpha(red: 0.03, green: 0, blue: 0, reference: nil, mode: .removeBlack, threshold: 0.02, feather: 0.02)
    #expect(abs(feathered - 0.5) < 0.001)
}

@Test func navigationContainsOnlyOpaqueIdentity() throws {
    let id = EndpointID()
    let url = try GlassDestination.desktopURL(id)
    #expect(try GlassDestination.desktopID(from: url) == id)
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) == ["connectionID"])
    #expect(url.user == nil)
}

@Test(arguments: ["glassdt://user:password@connection/00000000-0000-0000-0000-000000000000",
                  "glassdt://connection/00000000-0000-0000-0000-000000000000?password=bad",
                  "https://connection/00000000-0000-0000-0000-000000000000",
                  "glassdt://connection/not-an-id",
                  // The same four faults in the form the link actually takes.
                  "glassdt://user:password@connect?connectionID=00000000-0000-0000-0000-000000000000",
                  "glassdt://connect?connectionID=00000000-0000-0000-0000-000000000000&password=bad",
                  "https://connect?connectionID=00000000-0000-0000-0000-000000000000",
                  "glassdt://connect?connectionID=not-an-id"])
func rejectsInvalidNavigation(value: String) {
    #expect(throws: DesktopError.invalidDestination) { try GlassDestination.desktopID(from: #require(URL(string: value))) }
}

@Test @MainActor func persistenceRoundTripEditsAndDelete() async throws {
    let catalog = GlassInMemoryServiceStore(defaultKind: .rdp)
    let store = DesktopRepository(store: catalog)
    #expect(try store.load().isEmpty)
    var value = DesktopConnection(name: "Ubuntu", host: "localhost", username: "user")
    value.authentication = .tls
    _ = try await store.save(value)
    value.isFavorite = true
    _ = try await store.save(value)
    #expect(try DesktopRepository(store: catalog).load() == [value])
    let now = Date(timeIntervalSince1970: 100)
    #expect(try await store.recordConnection(value.id, at: now).first?.lastConnectedAt == now)
    #expect(try await store.delete(value.id).isEmpty)
    #expect(try store.load().isEmpty)
}

@Test @MainActor func invalidSaveDoesNotCreateStorage() async throws {
    let catalog = GlassInMemoryServiceStore(defaultKind: .rdp)
    let value = DesktopConnection(name: "Test", host: "")
    await #expect(throws: DesktopError.invalidHost) { try await DesktopRepository(store: catalog).save(value) }
    #expect(catalog.configuration(for: value.id) == nil)
    #expect(catalog.configurations(ofKind: .rdp).isEmpty)
}

@Test func protocolDefaultsToRDPForExistingDocuments() throws {
    var value = DesktopConnection(name: "Legacy", host: "desktop.example")
    value.protocol = .vnc
    let data = try JSONEncoder().encode(value)
    var json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"protocol\":\"vnc\""))
    json = json.replacingOccurrences(of: "\"protocol\":\"vnc\",", with: "").replacingOccurrences(of: ",\"protocol\":\"vnc\"", with: "")
    #expect(!json.contains("protocol"))
    let decoded = try JSONDecoder().decode(DesktopConnection.self, from: Data(json.utf8))
    #expect(decoded.protocol == .rdp)
    #expect(decoded.id == value.id)
    #expect(DesktopProtocol.rdp.defaultPort == 3389 && DesktopProtocol.vnc.defaultPort == 5900)
}

@Test func vncConnectionsAreCanonicalized() throws {
    var value = DesktopConnection(name: "Mac", host: "mac.example", port: 5900, username: "", domain: "CORP", protocol: .vnc)
    value.authentication = .tls
    value.certificateSHA256 = String(repeating: "a", count: 64)
    value.audioEnabled = true
    let validated = try value.validated()
    #expect(validated.domain.isEmpty && validated.authentication == .networkLevel && validated.certificateSHA256 == nil)
    #expect(!validated.audioEnabled)
    #expect(validated.credentialAccountName == DesktopConnection.passwordOnlyAccount)
    value.username = "alice"
    #expect(try value.validated().credentialAccountName == "alice")
    value.username = String(repeating: "u", count: 64)
    #expect(throws: DesktopError.invalidAccount) { try value.validated() }
    var rdp = DesktopConnection(name: "Win", host: "win.example", username: "")
    rdp.domain = "CORP"
    #expect(try rdp.validated().domain == "CORP")
    #expect(rdp.credentialAccountName.isEmpty)
}

@Test func visibleRegionCropsToASelectedDisplay() {
    let whole = DesktopRegion.whole(width: 3000, height: 1600)
    #expect(whole.origin == DesktopPoint(x: 0, y: 0))
    let normalized = try? #require(whole.normalized(inWidth: 3000, height: 1600))
    #expect(normalized?.extentX == 1 && normalized?.extentY == 1)

    let second = DesktopRegion(origin: .init(x: 2000, y: 0), size: DesktopSize(width: 1000, height: 600))
    let mapped = second.normalized(inWidth: 3000, height: 1600)
    #expect(mapped?.originX == 2000.0 / 3000.0)
    #expect(mapped?.extentX == 1000.0 / 3000.0)
    #expect(mapped?.extentY == 600.0 / 1600.0)

    // A region reaching outside the framebuffer has no valid texture rectangle.
    #expect(DesktopRegion(origin: .init(x: 2500, y: 0), size: DesktopSize(width: 1000, height: 600))
        .normalized(inWidth: 3000, height: 1600) == nil)
    #expect(second.normalized(inWidth: 0, height: 0) == nil)
}

@Test func pointerMappingFollowsTheVisibleDisplay() throws {
    // A 1000 x 600 display starting 2000 pixels into the framebuffer, shown in a 500 x 300 view.
    let origin = DesktopPoint(x: 2000, y: 0)
    let size = DesktopSize(width: 1000, height: 600)
    let topLeft = try #require(DesktopCoordinates.map(x: 0, y: 0, viewWidth: 500, viewHeight: 300, desktop: size, origin: origin))
    #expect(topLeft == DesktopPoint(x: 2000, y: 0))
    let middle = try #require(DesktopCoordinates.map(x: 250, y: 150, viewWidth: 500, viewHeight: 300, desktop: size, origin: origin))
    #expect(middle == DesktopPoint(x: 2500, y: 300))
    let bottomRight = try #require(DesktopCoordinates.map(x: 499, y: 299, viewWidth: 500, viewHeight: 300, desktop: size, origin: origin))
    #expect(bottomRight.x < 3000 && bottomRight.y < 600 && bottomRight.x >= 2000)
    // Without an origin the mapping is unchanged for single-display hosts.
    let plain = try #require(DesktopCoordinates.map(x: 250, y: 150, viewWidth: 500, viewHeight: 300, desktop: size))
    #expect(plain == DesktopPoint(x: 500, y: 300))
}

@Test func sourceScaleStaysInsideTheNegotiableRange() {
    #expect(DesktopSourceScale.automatic.factor(displayScale: 2) == 2)
    #expect(DesktopSourceScale.automatic.factor(displayScale: 1) == 1)
    // A display scale below one, or a nonsense value, never shrinks the request.
    #expect(DesktopSourceScale.automatic.factor(displayScale: 0.5) == 1)
    #expect(DesktopSourceScale.automatic.factor(displayScale: .nan) == 1)
    #expect(DesktopSourceScale.automatic.factor(displayScale: 99) == 5)
    #expect(DesktopSourceScale.standard.factor(displayScale: 3) == 1)
    #expect(DesktopSourceScale.oneAndAHalf.factor(displayScale: 1) == 1.5)
    #expect(DesktopSourceScale.double.factor(displayScale: 1) == 2)
    // MS-RDPEDISP accepts 100 through 500 only.
    #expect(DesktopSourceScale.automatic.desktopScaleFactor(displayScale: 2) == 200)
    #expect(DesktopSourceScale.oneAndAHalf.desktopScaleFactor(displayScale: 1) == 150)
    #expect(DesktopSourceScale.automatic.desktopScaleFactor(displayScale: 99) == 500)
    #expect(DesktopSourceScale.automatic.desktopScaleFactor(displayScale: 0) == 100)
    #expect(DesktopSourceScale.allCases.allSatisfy { (100...500).contains($0.desktopScaleFactor(displayScale: 2)) })
}

@Test func zoomedPanStaysOverlappingTheWindow() {
    let viewport = CGSize(width: 400, height: 300)
    // At 100% there is nothing hidden, so the image cannot be moved at all.
    let none = PresentationSettings.clampedPan(x: 50, y: 50, zoom: 1, viewport: viewport)
    #expect(none.x == 0 && none.y == 0)
    // At 200% half the width and height overflow, so each edge can move by that much.
    let doubled = PresentationSettings.clampedPan(x: 1000, y: -1000, zoom: 2, viewport: viewport)
    #expect(doubled.x == 200 && doubled.y == -150)
    let inside = PresentationSettings.clampedPan(x: 30, y: -20, zoom: 2, viewport: viewport)
    #expect(inside.x == 30 && inside.y == -20)
    // A zoom at or below the fitted size never allows movement, and nonsense values centre it.
    let out = PresentationSettings.clampedPan(x: 10, y: 10, zoom: 0.5, viewport: viewport)
    #expect(out.x == 0 && out.y == 0)
    let broken = PresentationSettings.clampedPan(x: .nan, y: .infinity, zoom: 2, viewport: viewport)
    #expect(broken.x == 0 && broken.y == 0)
    #expect(PresentationSettings.clampedPan(x: 5, y: 5, zoom: .nan, viewport: viewport) == (0, 0))
}

@Test func zoomNeverShrinksBelowTheFittedSize() {
    // The image already fills the window's tallest or widest edge at 100%, so anything smaller
    // would only pull it away from that edge.
    #expect(DesktopZoomLimits.minimum == 1)
    #expect(DesktopZoomLimits.maximum == 2)
    #expect(DesktopZoomLimits.minimum < DesktopZoomLimits.maximum)
    // At the smallest zoom nothing overflows, so the image cannot be panned away from the window.
    let pinned = PresentationSettings.clampedPan(x: 100, y: 100, zoom: DesktopZoomLimits.minimum,
                                                 viewport: CGSize(width: 400, height: 300))
    #expect(pinned.x == 0 && pinned.y == 0)
}

/// 2026-10-22: stamping one desktop wrote every desktop back as this build encodes it, so a field a
/// newer build had added to another was dropped, and the drop synced to every device.
@Test @MainActor func stampingOneDesktopKeepsAnotherDesktopsUnknownField() async throws {
    let catalog = GlassInMemoryServiceStore(defaultKind: .rdp)
    let store = DesktopRepository(store: catalog)
    let other = DesktopConnection(name: "Windows", host: "192.0.2.20", username: "user")
    let mine = DesktopConnection(name: "Ubuntu", host: "192.0.2.21", username: "user")
    _ = try await store.save(other)
    _ = try await store.save(mine)
    let written = try #require(catalog.configuration(for: other.id))
    var newer = try #require(try JSONSerialization.jsonObject(with: written) as? [String: Any])
    newer["fieldFromTheFuture"] = "kept"
    catalog.setConfiguration(try JSONSerialization.data(withJSONObject: newer), kind: .rdp, for: other.id)

    _ = try await store.recordConnection(mine.id, at: Date(timeIntervalSince1970: 100))

    let after = try #require(catalog.configuration(for: other.id))
    let stored = try #require(try JSONSerialization.jsonObject(with: after) as? [String: Any])
    #expect(stored["fieldFromTheFuture"] as? String == "kept")
}
