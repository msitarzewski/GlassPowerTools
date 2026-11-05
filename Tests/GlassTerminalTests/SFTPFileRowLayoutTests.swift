//
//  SFTPFileRowLayoutTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A Files row on Vision Pro keeps the file's name readable (the owner, 2026-11-05: "allow the names of the files to
//  be shown by default. If we need to hide rows for responsiveness, hide permissions and put the 'Actions' under a
//  drop down menu"). What must hold: a wide row shows every column; as it narrows, permissions go first, then the
//  three buttons fold into a menu, and the date only after both; at every width offered, the name keeps its minimum
//  whenever any layout can give it that.
//

import CoreGraphics
import Testing
@testable import GlassTerminal

@Suite("A Files row gives way so the name stays readable")
struct SFTPFileRowLayoutTests {
    private typealias Layout = SFTPFileRowLayout

    @Test("A wide row shows every column and the three buttons")
    func wideRowShowsEverything() {
        #expect(Layout.fitting(width: 1000) == .full)
    }

    @Test("Narrowing, the row gives way in his order: permissions, then the buttons into a menu, then the date")
    func givesWayInOrder() {
        let noPermissions = Layout(showsPermissions: false, actionsInMenu: false, showsModified: true)
        let menu = Layout(showsPermissions: false, actionsInMenu: true, showsModified: true)
        let noDate = Layout(showsPermissions: false, actionsInMenu: true, showsModified: false)
        // Each step at the widest width that no longer fits the fuller layout.
        #expect(Layout.fitting(width: Layout.full.fixedWidth + Layout.nameMinimum) == .full)
        #expect(Layout.fitting(width: Layout.full.fixedWidth + Layout.nameMinimum - 1) == noPermissions)
        #expect(Layout.fitting(width: noPermissions.fixedWidth + Layout.nameMinimum - 1) == menu)
        #expect(Layout.fitting(width: menu.fixedWidth + Layout.nameMinimum - 1) == noDate)
        #expect(Layout.fitting(width: 100) == noDate)
    }

    @Test("Every width from narrow to wide leaves the name its minimum when some layout can")
    func nameKeepsItsMinimum() {
        let narrowest = Layout(showsPermissions: false, actionsInMenu: true, showsModified: false)
        for width in stride(from: CGFloat(200), through: 1400, by: 1) {
            let layout = Layout.fitting(width: width)
            if width >= narrowest.fixedWidth + Layout.nameMinimum {
                #expect(width - layout.fixedWidth >= Layout.nameMinimum, "at \(width) the name had \(width - layout.fixedWidth)")
            } else {
                #expect(layout == narrowest)
            }
        }
    }

    @Test("A folder's empty buttons column is as wide as a file's, so the columns line up")
    func actionsColumnWidths() {
        #expect(Layout.full.actionsWidth == Layout.action * 3 + Layout.spacing * 2)
        #expect(Layout(showsPermissions: false, actionsInMenu: true, showsModified: true).actionsWidth == Layout.action)
    }
}
