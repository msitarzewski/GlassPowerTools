//
//  GlassServiceDrag.swift
//  Glass Power Tools — GlassShell
//
//  A service dragged out of the library opens its own window where it is let go (D72, 2026-10-13:
//  "Be sure visionOS is well represented!"). On Vision Pro that window stands where you drop it in
//  the room — a machine's terminal beside its desktop, placed by hand; on an iPad, a desktop's
//  window opens beside the library.
//
//  SwiftUI's `Transferable` cannot make a window (developers report it, and Apple's feedback
//  FB13545880 asks for it); a dragged `NSUserActivity` can. The activity names the service; the
//  window group that claims it (`handlesExternalEvents`) is created at the drop and becomes that
//  service's window. Declared in Info.plist (`NSUserActivityTypes`).
//

#if os(iOS) || os(visionOS)
import Foundation
import GlassConnectionKit
import SwiftUI
import UIKit

public enum GlassServiceDrag {
    /// A terminal, on Vision Pro: its window is a workgroup window (`GlassTerminalScenes`).
    public static let terminalActivity = "com.glasspowertools.open-terminal"
    /// A desktop, on Vision Pro and iPad (`GlassDesktopScenes`).
    public static let desktopActivity = "com.glasspowertools.open-desktop"

    /// The activity a service's drag carries, or nil for a kind that opens no window of its own here.
    public static func activityType(for kind: HostServiceKind) -> String? {
        switch kind {
        case .ssh:
            #if os(visionOS)
            terminalActivity
            #else
            nil   // An iPad shows terminals in the library's place, not in windows of their own.
            #endif
        case .rdp: desktopActivity
        case .database: nil
        }
    }

    /// What dragging `endpoint` hands the system: an activity a window group claims at the drop.
    public static func itemProvider(endpoint: EndpointID, kind: HostServiceKind) -> NSItemProvider? {
        guard let type = activityType(for: kind) else { return nil }
        let activity = NSUserActivity(activityType: type)
        activity.targetContentIdentifier = type
        activity.userInfo = ["endpoint": endpoint.rawValue.uuidString]
        return NSItemProvider(object: activity)
    }

    /// Whether a drag of `kind` can open a window here: a device with windows, and a kind with one.
    public static func canDrag(_ kind: HostServiceKind) -> Bool {
        GlassWindowPresentation.canOpenWindows && activityType(for: kind) != nil
    }

    /// The service a dropped activity names.
    public static func endpoint(from activity: NSUserActivity) -> UUID? {
        (activity.userInfo?["endpoint"] as? String).flatMap(UUID.init(uuidString:))
    }
}

public extension View {
    /// Drags `endpoint` out to a window of its own where that can open one (`GlassServiceDrag`);
    /// otherwise the view as it is, with no drag at all.
    @ViewBuilder
    func glassServiceDrag(endpoint: EndpointID, kind: HostServiceKind, enabled: Bool) -> some View {
        if enabled, GlassServiceDrag.canDrag(kind) {
            onDrag { GlassServiceDrag.itemProvider(endpoint: endpoint, kind: kind) ?? NSItemProvider() }
        } else {
            self
        }
    }
}
#endif
