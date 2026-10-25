import Foundation
import Testing
@testable import GlassShell

/// A host library refused as "no permission" (2026-10-21, the owner's headset: "The file hosts.json
/// couldn't be opened because you don't have permission to view it"). While the device is locked it
/// is read again on unlocking; only with it unlocked does it mean a build without the App Group.
@MainActor
@Suite("A library read while the device is locked")
struct GlassLibraryLockedReadTests {
    /// What Foundation gives a read of a file locked with the device, as the headset showed it.
    private let lockedRead = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
                                     userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])

    @Test("locked: read again on unlocking — not the app's own library, and not an alert")
    func locked() {
        #expect(GlassShellModel.response(to: lockedRead, protectedDataAvailable: false, hasSharedContainer: true)
                == .readAgainWhenUnlocked)
        #expect(GlassShellModel.response(to: lockedRead, protectedDataAvailable: false, hasSharedContainer: false)
                == .readAgainWhenUnlocked)
    }

    @Test("unlocked and refused: a build without the App Group keeps the app's own library")
    func noAppGroup() {
        #expect(GlassShellModel.response(to: lockedRead, protectedDataAvailable: true, hasSharedContainer: true)
                == .useAppLibrary)
        #expect(GlassShellModel.response(to: lockedRead, protectedDataAvailable: true, hasSharedContainer: false)
                == .report)
    }

    @Test("anything else is said as it is, locked or not")
    func otherErrors() {
        let corrupt = NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        #expect(GlassShellModel.response(to: corrupt, protectedDataAvailable: false, hasSharedContainer: true) == .report)
        #expect(GlassShellModel.response(to: corrupt, protectedDataAvailable: true, hasSharedContainer: true) == .report)
    }
}
