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
}
