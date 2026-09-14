import Foundation

/// The canonical accessor for `GlassEditorCore`'s own resource bundle.
///
/// `Bundle.module` is generated per-target, so a test target or a consumer that
/// writes `Bundle.module` gets *its* bundle, not this one — the highlight queries
/// declared by `.copy("Grammar/Queries")` in `Package.swift` live here and nowhere
/// else. Everything that needs a shipped resource goes through this type rather
/// than reconstructing bundle paths by hand.
public enum GlassEditorCoreResources {
    /// The bundle holding `GlassEditorCore`'s shipped resources.
    public static var bundle: Bundle { Bundle.module }

    /// URL of a highlight query shipped under `Grammar/Queries`.
    ///
    /// - Parameter name: the resource's base name, e.g. `"sql-highlights"`.
    /// - Returns: `nil` when the resource is absent from the bundle.
    public static func highlightQueryURL(named name: String) -> URL? {
        bundle.url(forResource: name, withExtension: "scm", subdirectory: "Queries")
    }
}
