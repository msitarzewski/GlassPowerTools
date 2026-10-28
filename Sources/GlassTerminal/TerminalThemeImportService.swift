import Foundation

/// A Terminal profile as a theme for the library (the Themes window's Import), on every device:
/// read by `TerminalProfileReader`, its colours and, where this device has it, its font.
@MainActor
enum TerminalThemeImportService {
    static let maximumImportBytes = TerminalProfileReader.maximumBytes
    nonisolated static let maximumNameLength = TerminalTheme.maximumNameLength

    static func importTheme(from url: URL, fallback: TerminalTheme) throws -> TerminalTheme {
        guard url.isFileURL else { throw TerminalThemeImportError.unsupportedFileExtension }
        return TerminalTheme(profile: try TerminalProfileReader.read(contentsOf: url), fallback: fallback,
                             id: fallback.id, withFont: true)
    }

    static func importTheme(from data: Data, fallback: TerminalTheme) throws -> TerminalTheme {
        TerminalTheme(profile: try TerminalProfileReader.read(data), fallback: fallback, id: fallback.id, withFont: true)
    }
}
