import Foundation
import GlassConnectionUI

/// The system-wide tag vocabulary: one flat set of collection tags across the whole library.
/// Labels, groups and clients are uses of this vocabulary, not separate tag types.
public enum GlassShellTagVocabulary {
    /// Every tag on every host, including consolidated members (`GlassShellHost.tags` is already
    /// the union of its members'), deduplicated case-insensitively with the first spelling kept,
    /// sorted case-insensitively.
    public static func tags(in hosts: [GlassShellHost]) -> [String] {
        GlassTagList.normalized(hosts.flatMap(\.tags))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

public extension GlassShellModel {
    /// The suggestions every tag editor in the shell offers.
    var tagVocabulary: [String] { GlassShellTagVocabulary.tags(in: hosts) }
}
