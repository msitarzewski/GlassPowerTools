import SwiftUI

#if os(macOS)
private struct DesktopImportActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var desktopImportAction: (() -> Void)? {
        get { self[DesktopImportActionKey.self] }
        set { self[DesktopImportActionKey.self] = newValue }
    }
}

public struct DesktopImportCommands: Commands {
    @FocusedValue(\.desktopImportAction) private var importFile
    public init() {}
    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import RDP File…") { importFile?() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(importFile == nil)
        }
    }
}
#endif
