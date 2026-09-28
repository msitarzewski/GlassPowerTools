//
//  DesktopUnreadableRecordTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  A desktop this build will not accept is not a desktop the user deleted.
//
//  `DesktopRepository.load()` hides records that fail `validated()` — a rule a newer build relaxed,
//  or one written by hand — and every write reconciled the catalog to the loaded list, so saving,
//  starring, stamping or deleting any other desktop erased them (2026-09-27, found comparing
//  glassDT, which refused to write instead). They stay stored and hidden until a build can read them.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassShell
@testable import GlassDesktop

@MainActor
@Suite("Desktops this build rejects survive a write")
struct DesktopUnreadableRecordTests {

    @Test func aRecordThatFailsValidationSurvivesSavingAnother() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .rdp)
        let repository = DesktopRepository(store: store)
        // An empty host is refused by `validated()`, so `load()` never lists this one.
        let rejected = DesktopConnection(name: "legacy", host: "")
        let data = try JSONEncoder().encode(rejected)
        store.setConfiguration(data, kind: .rdp, for: rejected.id)

        _ = try await repository.save(DesktopConnection(name: "alpha", host: "192.0.2.10"))

        #expect(store.configuration(for: rejected.id) == data)
        #expect(try repository.load().map(\.name) == ["alpha"])
    }

    @Test func deletingAnotherDesktopLeavesItToo() async throws {
        let store = GlassInMemoryServiceStore(defaultKind: .rdp)
        let repository = DesktopRepository(store: store)
        let rejected = DesktopConnection(name: "legacy", host: "")
        let data = try JSONEncoder().encode(rejected)
        store.setConfiguration(data, kind: .rdp, for: rejected.id)
        let alpha = DesktopConnection(name: "alpha", host: "192.0.2.10")
        _ = try await repository.save(alpha)

        _ = try await repository.delete(alpha.id)

        #expect(store.configuration(for: rejected.id) == data)
        #expect(try repository.load().isEmpty)
    }
}
