import SwiftUI

// `visibilityPriority` is above the product floor on every platform that has it, and unavailable
// on visionOS. This guard is deliberately **duplicated per module rather than shared**: an
// `if #available` inside a `@ToolbarContentBuilder` makes the compiler emit
// `ToolbarContentBuilder.buildLimitedAvailability`, whose opaque type descriptor does not resolve
// across a module boundary — Release fails to link with "symbol(s) not found" while Debug builds
// clean, and `@inlinable` does not rescue it. Keep the copy local. (2026-09-12)
extension ToolbarContent {
    @ToolbarContentBuilder
    func glassKeepVisibleWhenCompact() -> some ToolbarContent {
        #if os(macOS)
        if #available(macOS 26.1, *) { visibilityPriority(.high) } else { self }
        #elseif os(iOS)
        if #available(iOS 27.0, *) { visibilityPriority(.high) } else { self }
        #else
        self
        #endif
    }

    @ToolbarContentBuilder
    func glassOverflowFirstWhenCompact() -> some ToolbarContent {
        #if os(macOS)
        if #available(macOS 26.1, *) { visibilityPriority(.low) } else { self }
        #elseif os(iOS)
        if #available(iOS 27.0, *) { visibilityPriority(.low) } else { self }
        #else
        self
        #endif
    }
}
