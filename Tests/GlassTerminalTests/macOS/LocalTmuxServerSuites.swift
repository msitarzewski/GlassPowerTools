#if os(macOS)
import Testing

/// Every suite that swaps `MacLocalTmux.server` for a stand-in, one at a time (2026-10-12). Each
/// was serialized within itself, but nine of them ran beside each other and one's stand-in
/// answered another's test: three tests failed on a full run and passed alone. `.serialized` here
/// covers every suite nested in this one.
@Suite(.serialized)
enum LocalTmuxServerSuites {}

/// The fake server the suites share, by the name the tests use.
typealias MacLocalTmuxTests = LocalTmuxServerSuites.MacLocalTmuxTests
#endif
