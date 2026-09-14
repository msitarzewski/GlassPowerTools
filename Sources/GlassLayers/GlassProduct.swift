import Foundation

/// The product's own name, for text the user reads.
///
/// It exists because the name was written out by hand in alerts and messages inherited from the
/// source applications, so the app introduced itself as "glas.sh" in its own quit dialog long after
/// the merge. A literal cannot be renamed by a compiler, and the next rename will have the same
/// problem unless there is one place to change.
///
/// **Only for text a person reads.** Storage identifiers — UserDefaults keys, Keychain service
/// names, App Group and access group identifiers — are *names of stored things*, not of the
/// product, and renaming those silently orphans what they point at. Historical references in
/// comments are provenance and stay as they are: `glas.sh` is where a behaviour came from, and
/// rewriting that makes the record a lie.
public enum GlassProduct {
    /// As it appears in sentences and dialog titles.
    public static let name = "Glass Power Tools"

    /// Reads back from the bundle when it is available, so a renamed build says the right thing
    /// without a code change, and falls back to the literal above for tests and previews that have
    /// no app bundle.
    public static var displayName: String {
        let info = Bundle.main.infoDictionary
        let candidate = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
        guard let candidate, !candidate.isEmpty else { return name }
        return candidate
    }
}
