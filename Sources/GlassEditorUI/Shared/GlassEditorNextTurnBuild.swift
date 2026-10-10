import Foundation

/// Builds something on the **next turn of the main queue**, never inside the call that asked.
///
/// For a view SwiftUI asks for from inside its own update. On Vision Pro, a UIKit text view built
/// there can bring up the scene's text-effects window, which adds an ornament and moves focus, and
/// the focus change re-enters the same SwiftUI view graph while its layout still runs: every
/// headset "SwiftUI layout over-release" crash before 0.4.313 was that, from the terminal's view
/// (rule 64, `SwiftTermHostView`). The editor's text view is a `UITextView`, so it is built the same
/// way: the representable returns a plain host view at once, and this builds the editor into it a
/// turn later.
///
/// Platform-neutral so the rule can be tested on the Mac, where the suite runs.
@MainActor
public final class GlassEditorNextTurnBuild<Built: AnyObject> {
    /// What was built, once it has been.
    public private(set) var built: Built?
    private var isScheduled = false

    public init() {}

    /// Schedules `make` for the next main-queue turn. Once only: a second call while one is waiting,
    /// or after the build, does nothing. `make` returns nil when there is nothing left to build into
    /// — the host view went away in the meantime.
    public func schedule(_ make: @escaping @MainActor () -> Built?) {
        guard !isScheduled, built == nil else { return }
        isScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.built = make()
            }
        }
    }
}
