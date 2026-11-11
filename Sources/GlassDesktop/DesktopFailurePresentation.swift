import Foundation

struct DesktopFailurePresentation: Equatable {
    let title: String
    let message: String
    let details: String

    init(hadDesktop: Bool, details: String) {
        title = hadDesktop ? "Connection Lost" : "Unable to Connect"
        message = hadDesktop
            ? "The remote desktop connection was interrupted. You can reconnect or close this window."
            : "The remote desktop could not be opened. Check the connection and try again."
        self.details = String(details.prefix(4096))
    }

    private init(title: String, message: String, details: String) {
        self.title = title
        self.message = message
        self.details = details
    }

    /// The machine is on a tailnet and Tailscale is off on this device (2026-11-10): what to do is turn it on.
    static func needsTailscale(_ message: String) -> DesktopFailurePresentation {
        DesktopFailurePresentation(title: "Tailscale Is Off", message: message, details: message)
    }
}
