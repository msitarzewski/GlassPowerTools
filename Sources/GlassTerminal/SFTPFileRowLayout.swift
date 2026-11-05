//
//  SFTPFileRowLayout.swift
//  Glass Power Tools — GlassTerminal
//
//  The columns a Files row shows on Vision Pro, from the width it has (the owner, 2026-11-05, a Files window opened
//  from a terminal's folder button, every file's name shown as "…": "It should be wider, and allow the names of the
//  files to be shown by default. If we need to hide rows for responsiveness, hide permissions and put the 'Actions'
//  under a drop down menu").
//
//  The headset's row keeps the Mac's columns (name, size, modified, permissions) and a file's three buttons (Edit,
//  Get Info, Download), each column a fixed width. The name had what was left, which in the 700-point window it
//  opened at was nothing. Now the name keeps `nameMinimum` and the row gives way in his order: permissions first,
//  then the three buttons fold into one ⋯ menu, and last, only in a window narrower than any it opens at, the date.
//

import CoreGraphics

struct SFTPFileRowLayout: Equatable, Sendable {
    var showsPermissions: Bool
    var actionsInMenu: Bool
    var showsModified: Bool

    /// Every column and the three buttons.
    static let full = SFTPFileRowLayout(showsPermissions: true, actionsInMenu: false, showsModified: true)

    // MARK: Column widths, used by the row and by the arithmetic below

    static let spacing: CGFloat = 12
    static let icon: CGFloat = 28
    static let size: CGFloat = 90
    static let modified: CGFloat = 150
    static let permissions: CGFloat = 108
    /// One of a file's three buttons, and the ⋯ menu that holds them.
    static let action: CGFloat = 44
    static let actionCount = 3
    /// Below this the name would truncate to almost nothing again, so a column gives way first.
    static let nameMinimum: CGFloat = 240

    static var actionsInline: CGFloat { action * CGFloat(actionCount) + spacing * CGFloat(actionCount - 1) }

    /// The width of the buttons' column: three buttons, or the menu. A folder's row leaves the same space empty, so its
    /// size and date line up with the files'.
    var actionsWidth: CGFloat { actionsInMenu ? Self.action : Self.actionsInline }

    /// The width every column but the name takes, with the spacing before each.
    var fixedWidth: CGFloat {
        var columns: [CGFloat] = [Self.icon, Self.size, actionsWidth]
        if showsModified { columns.append(Self.modified) }
        if showsPermissions { columns.append(Self.permissions) }
        return columns.reduce(0, +) + Self.spacing * CGFloat(columns.count)
    }

    /// The fullest row that leaves the name `nameMinimum` in a row `width` wide: every column; then without
    /// permissions; then the buttons in a menu; then without the date.
    static func fitting(width: CGFloat) -> SFTPFileRowLayout {
        let givingWay = [
            full,
            SFTPFileRowLayout(showsPermissions: false, actionsInMenu: false, showsModified: true),
            SFTPFileRowLayout(showsPermissions: false, actionsInMenu: true, showsModified: true),
        ]
        return givingWay.first { $0.fixedWidth + nameMinimum <= width }
            ?? SFTPFileRowLayout(showsPermissions: false, actionsInMenu: true, showsModified: false)
    }
}
