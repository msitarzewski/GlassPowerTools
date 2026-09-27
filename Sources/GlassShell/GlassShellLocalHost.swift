import Foundation
import GlassConnectionKit
#if canImport(UIKit)
import UIKit
#endif

/// The device itself, as a host (D8). It behaves like any other machine in the library — it takes
/// services, it is favourited, it appears in collections — and differs in four ways, each of which
/// follows from it being *this* device rather than one to reach:
///
/// - **It has no address and is never asked for one.** Its services bind to `address` below, or to
///   a file path. The setup sheet's address gate exempts it.
/// - **It is never published to the shared catalog.** Its record lives in this app's own storage,
///   not in the App Group file the three source applications also read, so nothing appears in
///   glas.sh, glassdb or glassDT that they cannot open. Each device therefore has its own.
/// - **Its services never tunnel.** There is nothing to tunnel through: the machine is here.
/// - **Connecting "the machine" has no meaning**, so the row offers only the service picker. See
///   `GlassShellModel.connectAll(hostID:)`.
public enum GlassLocalHost {
    /// Fixed, so the device's host keeps its services, favourite and collections across launches
    /// and across reinstalls of the record file. Chosen to be recognisable in a JSON dump
    /// ("LOCAL") and to be one no generated `UUID` will ever produce by accident.
    public static let id = HostID(rawValue: UUID(uuidString: "4c4f4341-4c00-0000-0000-000000000001")!)

    /// What a service on this device connects to when it speaks over the network at all — a local
    /// MySQL or PostgreSQL. SQLite uses a file path instead and needs no address whatsoever.
    /// This is never shown as the host's address, because the host has none.
    public static let address = "127.0.0.1"

    /// Beside the shared catalog's own relative path, under this app's private storage.
    static let storeRelativePath = "GlassHostCatalog/local-host.json"

    /// What the device is called. Deliberately not the machine's own name: a Mac called "bravo"
    /// may also be in the shared library as a machine reached over SSH, and two rows with one name
    /// would be indistinguishable. "This Mac" is what the user called it.
    public static var displayName: String {
        #if os(macOS)
        "This Mac"
        #elseif os(visionOS)
        "This Apple Vision Pro"
        #elseif canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad ? "This iPad" : "This iPhone"
        #else
        "This Device"
        #endif
    }
}
