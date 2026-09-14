import Foundation

/// Foreground routes to existing saved records. Links carry neither credentials
/// nor arbitrary host addresses, commands or SQL. Apps still authorize activation.
public enum GlassConnectionLink: Equatable, Sendable {
    case ssh(serverID: UUID)
    case database(connectionID: UUID)
    case desktop(connectionID: UUID)

    /// Constructed from fixed schemes/keys and a UUID, never from host or secret text.
    public var url: URL? {
        let scheme: String
        let key: String
        let identifier: UUID
        switch self {
        case .ssh(let id): scheme = "glassh"; key = "serverID"; identifier = id
        case .database(let id): scheme = "glassdb"; key = "connectionID"; identifier = id
        case .desktop(let id): scheme = "glassdt"; key = "connectionID"; identifier = id
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "connect"
        components.queryItems = [URLQueryItem(name: key, value: identifier.uuidString.lowercased())]
        return components.url
    }

    public init?(url: URL) {
        guard url.absoluteString.utf8.count <= 256,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == "connect", components.path.isEmpty,
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil,
              let query = components.queryItems, query.count == 1,
              let value = query[0].value, let id = UUID(uuidString: value) else { return nil }
        switch (components.scheme?.lowercased(), query[0].name) {
        case ("glassh", "serverID"): self = .ssh(serverID: id)
        case ("glassdb", "connectionID"): self = .database(connectionID: id)
        case ("glassdt", "connectionID"): self = .desktop(connectionID: id)
        default: return nil
        }
    }
}
