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

/// Where this build keeps what its processes and devices share: the App Group, the CloudKit
/// container and the keychain access group.
///
/// Set once, in `Config/Identity.xcconfig`, and read here from the bundle's Info.plist, so a fork
/// signing under another team changes one file instead of six. The literals are this project's own
/// values, used where there is no app bundle to read (tests, previews, packages built alone).
/// These name stored things: changing them on an existing install orphans what they point at.
public enum GlassAppIdentity {
    /// The App Group whose container and defaults suite the app and its widget share.
    public nonisolated static let appGroup = infoValue("GlassAppGroup") ?? "group.sh.glas.shared"
    /// The CloudKit container the host catalog syncs through.
    public nonisolated static let cloudKitContainer = infoValue("GlassCloudKitContainer") ?? "iCloud.com.glasspowertools"
    /// The keychain access group without its team prefix (`TEAMID.` + this).
    public nonisolated static let keychainGroupSuffix = infoValue("GlassKeychainGroupSuffix") ?? "sh.glas.shared"

    /// A value from Info.plist, unless it is empty or an unexpanded build setting.
    nonisolated static func infoValue(_ key: String, in bundle: Bundle = .main) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("$(") ? nil : trimmed
    }
}
