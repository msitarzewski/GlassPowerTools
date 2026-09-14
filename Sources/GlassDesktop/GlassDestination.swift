import Foundation
import GlassConnectionKit

public enum GlassDestination {
    public static func desktopURL(_ id: EndpointID) throws -> URL {
        guard let url = GlassConnectionLink.desktop(connectionID: id.rawValue).url else { throw DesktopError.invalidDestination }
        return url
    }

    public static func desktopID(from url: URL) throws -> EndpointID {
        guard case .desktop(let identifier) = GlassConnectionLink(url: url) else { throw DesktopError.invalidDestination }
        return EndpointID(rawValue: identifier)
    }
}
