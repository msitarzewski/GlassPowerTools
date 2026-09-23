//
//  GlassEditorWorkspace.swift
//  Glass Power Tools — GlassEditor
//
//  Every open document, and what the user can do to the set of them.
//
//  Deliberately free of SwiftUI: opening, closing, saving, the recents list and the find state are
//  all decisions about documents rather than about views, and keeping them here is what lets them
//  be tested without a window. The view above it is thin by design.
//

import Foundation
#if os(iOS)
import UIKit
#endif
import Observation
import GlassEditorCore
import GlassEditorUI

/// What the sidebar has selected. Documents and tree nodes share one selection because the list
/// they live in has one.
public enum GlassEditorSidebarSelection: Hashable, Sendable {
    case document(UUID)
    case node(UUID)
}

@MainActor @Observable
public final class GlassEditorWorkspace {
    /// Open documents, in the order they were opened — the order the tab list shows.
    public private(set) var documents: [GlassEditorDocument] = []
    public var selection: GlassEditorDocument.ID?
    /// What is selected in the sidebar — a document **or** a file or folder in a project tree.
    ///
    /// One value rather than two, so "a file is selected" and "a document is selected" cannot both
    /// be true and disagree. Selecting a document row keeps `selection` in step, because the detail
    /// pane reads that.
    public var sidebarSelection: GlassEditorSidebarSelection? {
        didSet {
            if case .document(let id) = sidebarSelection { selection = id }
        }
    }
    /// Folders the user has opened, by node id. Tracked here rather than left to `OutlineGroup`
    /// because the keyboard has to be able to open and close them, and because a folder is read
    /// from disk the first time it opens — a decision, not a drawing detail.
    public private(set) var expandedNodes: Set<UUID> = []
    /// Open projects — a folder on a machine (see `GlassEditorProject`). Kept beside the documents
    /// rather than owning them: a file can be opened without a project, and every file in a
    /// project is still an ordinary document.
    public private(set) var projects: [GlassEditorProject] = []
    /// The root node of each open project, by project id.
    public private(set) var projectRoots: [GlassEditorProject.ID: GlassEditorProjectNode] = [:]
    /// How each project is reached from this device, decided once when it opens.
    public private(set) var projectReach: [GlassEditorProject.ID: GlassEditorProjectReach] = [:]
    /// How each project's machine is reached — the file system for a project on this device, an
    /// SFTP session for one on another machine. Settled when the project opens, for the same reason
    /// `projectReach` is: neither the folder nor the device moves while the project is open, so
    /// deciding it at every draw would be deciding the same thing repeatedly and giving a view a
    /// choice it has no business making.
    private var projectAccess: [GlassEditorProject.ID: any GlassEditorFileAccess] = [:]
    /// What went wrong, for the one alert this surface has.
    public var message: String?
    /// Whether the find bar is showing, and what it is looking for.
    public var findIsPresented = false
    public var findQuery = ""
    public var replacement = ""
    public var findIsCaseSensitive = false
    public var findUsesRegularExpression = false

    /// Shared with every other window: text size, line numbers, wrapping, recents.
    public let preferences: GlassEditorPreferences

    /// Set when a **file** is opened with no project in this window: the sidebar is a project's
    /// tree, and a tree of nothing beside one open file is a column of empty space. Opening a
    /// project clears it again.
    public private(set) var prefersCollapsedSidebar = false

    public init(preferences: GlassEditorPreferences? = nil, defaults: UserDefaults = .standard) {
        self.preferences = preferences ?? GlassEditorPreferences(defaults: defaults)
    }

    /// Applies the shared appearance to every document this window holds. Called by the view when a
    /// preference changes, because the preferences are a value the window observes rather than an
    /// owner that reaches back into it.
    public func applyAppearance() {
        for document in documents { apply(to: document) }
    }

    private func apply(to document: GlassEditorDocument) {
        // **File over project over global.** One funnel, so no surface can apply the levels in a
        // different order than another (`GlassEditorTextOverrides`).
        let global = preferences.configuration(basedOn: document.model.configuration)
        document.model.configuration = GlassEditorTextOverrides.resolve(
            global: global,
            project: projectOverrides(for: document),
            file: document.textOverrides)
        document.model.theme = preferences.theme
    }

    /// The overrides of the project this document belongs to, if it belongs to one.
    func projectOverrides(for document: GlassEditorDocument) -> GlassEditorTextOverrides? {
        guard let path = document.path else { return nil }
        return project(owning: path)?.textOverrides
    }

    /// What the file inherits when it says nothing of its own — what a settings row calls
    /// "Default", and where that default comes from.
    public func inheritedConfiguration(for document: GlassEditorDocument) -> GlassEditorConfiguration {
        GlassEditorTextOverrides.resolve(
            global: preferences.configuration(basedOn: document.model.configuration),
            project: projectOverrides(for: document),
            file: nil)
    }

    /// Sets this file's overrides. Not stored: a document holds them while it is open.
    public func setTextOverrides(_ overrides: GlassEditorTextOverrides,
                                 for document: GlassEditorDocument) {
        document.textOverrides = overrides
        apply(to: document)
    }

    /// Sets a project's overrides on this window's copy. The library is updated by the runtime,
    /// which owns the durable list — this keeps the open window in step immediately.
    public func setTextOverrides(_ overrides: GlassEditorTextOverrides,
                                 forProject id: GlassEditorProject.ID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].textOverrides = overrides.isEmpty ? nil : overrides
        applyAppearance()
    }

    // MARK: The preview tab

    /// The document opened by a single click, if there is one.
    ///
    /// **The pattern every editor uses**, and the one a user coming from Xcode or VS Code already
    /// has in their hands: clicking a file in the list opens it *provisionally* — one slot, reused
    /// by the next single click, so walking a folder does not leave twenty tabs behind. The file
    /// stays the moment you commit to it: a double click, a keystroke that opens it deliberately,
    /// an edit, or a save.
    ///
    /// One id rather than a flag on each document, because "two documents are both the preview" is
    /// a state that must not be representable.
    public private(set) var previewDocumentID: GlassEditorDocument.ID?

    public func isPreview(_ id: GlassEditorDocument.ID) -> Bool { previewDocumentID == id }

    /// Keeps the document — the other half of the pattern. Idempotent, and called from everywhere
    /// that counts as committing to a file.
    public func makePermanent(_ id: GlassEditorDocument.ID) {
        if previewDocumentID == id { previewDocumentID = nil }
    }

    /// Empties the preview slot for a new occupant, and says where the old one sat so the new tab
    /// takes its place rather than appearing at the end — the tab must not move while you are
    /// clicking down a list.
    ///
    /// An **edited** preview is not evicted: editing is what makes a file worth keeping, so it is
    /// promoted and the new document is appended beside it.
    private func vacatePreviewSlot() -> Int? {
        guard let id = previewDocumentID,
              let index = documents.firstIndex(where: { $0.id == id }) else { return nil }
        previewDocumentID = nil
        guard !documents[index].isDirty else { return nil }
        _ = close(id, force: true)
        return min(index, documents.count)
    }

    // MARK: The open set

    public var selectedDocument: GlassEditorDocument? {
        guard let selection else { return nil }
        return documents.first { $0.id == selection }
    }

    public var hasUnsavedChanges: Bool { documents.contains { $0.isDirty } }

    /// Opens a file, or selects it when it is already open.
    ///
    /// Re-opening a file that is already open must never produce a second copy: two editors over
    /// one file is a way to lose work, and it is the first thing a user does by accident.
    ///
    /// **A picked or dropped file is security-scoped on iOS**, and reading it without asking for
    /// access fails — every file chosen through Open File on a phone, text and pictures alike,
    /// ended at "No Document" (2026-09-23). Access is asked for here and **held while the document
    /// is open**, because saving writes back to the same file; `close` gives it back. A URL that is
    /// not scoped answers false and nothing is held.
    @discardableResult
    public func open(_ url: URL, asPreview: Bool = false) async -> GlassEditorDocument? {
        let scoped = url.startAccessingSecurityScopedResource()
        let document = await open(path: url.standardizedFileURL.path(percentEncoded: false), asPreview: asPreview)
        if scoped {
            if let document, securityScopedURLs[document.id] == nil {
                securityScopedURLs[document.id] = url
            } else {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return document
    }

    /// Scoped access held for documents opened from a picker or a drop, returned on close.
    private var securityScopedURLs: [GlassEditorDocument.ID: URL] = [:]

    /// Opens a file on whichever machine its project is on.
    ///
    /// **One method for both**, because after "which machine" there is no second difference: the
    /// same duplicate check, the same encoding work, the same recents list, the same tab. The
    /// machine decides which `GlassEditorFileAccess` the bytes travel through and nothing else.
    @discardableResult
    public func open(path rawPath: String, asPreview: Bool = false) async -> GlassEditorDocument? {
        let path = GlassEditorProject.normalized(rawPath)
        let owner = project(owning: path)
        return await open(path: path,
                          through: owner.flatMap { projectAccess[$0.id] } ?? GlassEditorLocalFileAccess(),
                          machine: owner.flatMap { machineName(of: $0.id) },
                          asPreview: asPreview)
    }

    /// Opens a file with the machine named explicitly — a file on a server with no project around
    /// it, which is what **Edit** in the Files browser opens.
    ///
    /// The access is remembered against the document, because there is no project to look it up
    /// from later and saving has to go back the way the file came. Without that, a file opened
    /// this way would be read over SSH and written to a path on this Mac.
    @discardableResult
    public func open(path rawPath: String,
                     through access: any GlassEditorFileAccess,
                     machine: String?,
                     asPreview: Bool = false,
                     asText: Bool = false,
                     allowLargeRemote: Bool = false) async -> GlassEditorDocument? {
        let path = GlassEditorProject.normalized(rawPath)
        if let existing = documents.first(where: { $0.path == path && $0.machine == machine }),
           !(asText && existing.viewer != nil) {
            selection = existing.id
            // Opening it deliberately keeps it; a single click on a file already previewing
            // leaves it exactly where it is.
            if !asPreview { makePermanent(existing.id) }
            return existing
        }

        // Only this device's file system can be asked this, and only this device's needs to be:
        // a folder on a server fails the read below, which is where its reason comes from.
        if machine == nil {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                message = GlassEditorWorkspaceError
                    .notAFile((path as NSString).lastPathComponent).localizedDescription
                return nil
            }
        }
        do {
            let document = try await GlassEditorDocument.open(path: path, through: access,
                                                             machine: machine, asText: asText,
                                                             allowLargeRemote: allowLargeRemote)
            apply(to: document)
            // Into the preview's place when there is one, so the tab does not jump while a user
            // clicks down a file list.
            if asPreview, let slot = vacatePreviewSlot() {
                documents.insert(document, at: slot)
            } else {
                documents.append(document)
            }
            if asPreview { previewDocumentID = document.id }
            // A phone cannot draw a line this long at all — its text view stays blank — so a file
            // that has a picture opens as the picture, with the text one press away (2026-09-23:
            // *"previews only on iOS, that's fine"*).
            if Self.isPhone, document.hasVeryLongLine, previewKind(for: document) != nil {
                previewModes[document.id] = .previewOnly
            }
            if machine != nil { documentAccess[document.id] = access }
            selection = document.id
            // Recents are this device's list of files it can reopen. A file on another machine is
            // reopened through its project, so putting it here would offer a path that resolves to
            // nothing the next time the app starts.
            if machine == nil { preferences.noteRecent(URL(filePath: path)) }
            if projects.isEmpty { prefersCollapsedSidebar = true }
            return document
        } catch let error as GlassEditorOpenError {
            // A question, not a failure: the window asks, and `confirmLargeOpen` goes ahead.
            pendingLargeOpen = GlassEditorPendingOpen(path: path, access: access, machine: machine,
                                                      asPreview: asPreview, reason: error)
            return nil
        } catch {
            message = "\((path as NSString).lastPathComponent) could not be opened: \(error.localizedDescription)"
            return nil
        }
    }

    /// Whether this device is a phone, where a very long line opens in Preview.
    static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// How each document with a preview is being shown (`GlassEditorPreviewMode`), text by default.
    public var previewModes: [GlassEditorDocument.ID: GlassEditorPreviewMode] = [:]

    /// The preview a document offers, if any. Viewers offer none: they already are the picture.
    public func previewKind(for document: GlassEditorDocument) -> GlassEditorPreviewKind? {
        guard document.viewer == nil else { return nil }
        return GlassEditorPreviewKind.kind(language: document.model.language, fileName: document.url?.lastPathComponent)
    }

    /// What a document's preview may read beside it: its project when it has one, else its folder.
    public func previewRoot(for document: GlassEditorDocument) -> String {
        if let path = document.path, let owner = project(owning: path) { return owner.path }
        return document.path.map { ($0 as NSString).deletingLastPathComponent } ?? "/"
    }

    /// A remote media file that asked before downloading (`GlassEditorOpenError.largeRemoteFile`).
    public private(set) var pendingLargeOpen: GlassEditorPendingOpen?

    /// The user said yes: download it and show it.
    public func confirmLargeOpen() async {
        guard let pending = pendingLargeOpen else { return }
        pendingLargeOpen = nil
        await open(path: pending.path, through: pending.access, machine: pending.machine,
                   asPreview: pending.asPreview, allowLargeRemote: true)
    }

    public func cancelLargeOpen() { pendingLargeOpen = nil }

    /// The not-text screen's **Open as Text**: the same file, decoded after all, in the viewer's
    /// place. Asked for deliberately, so it is the old behaviour on request rather than by accident.
    public func openAsText(_ document: GlassEditorDocument) async {
        guard document.viewer != nil, let path = document.path else { return }
        let access = access(for: document)
        let machine = document.machine
        let index = documents.firstIndex { $0.id == document.id }
        close(document.id, force: true)
        guard let reopened = await open(path: path, through: access, machine: machine, asText: true),
              let index, let now = documents.firstIndex(where: { $0.id == reopened.id }), now != index,
              documents.indices.contains(index) else { return }
        documents.move(fromOffsets: IndexSet(integer: now), toOffset: index)
    }

    /// The project a path belongs to, by the prefix its root shares with it.
    func project(owning path: String) -> GlassEditorProject? {
        projects.first { path == $0.path || path.hasPrefix($0.path + "/") }
    }

    /// The machine a project is on, when it is not this one.
    func machineName(of id: GlassEditorProject.ID) -> String? {
        switch projectReach[id] {
        case .overSSH(let host), .unreachable(let host): host
        case .thisMachine, nil: nil
        }
    }

    /// Where a standalone document's bytes travel, when no project answers for it.
    private var documentAccess: [GlassEditorDocument.ID: any GlassEditorFileAccess] = [:]

    /// How a document's bytes travel: the one it was opened with, or its project's, or this
    /// device's file system. In that order, because a file opened on its own has no project and
    /// falling through to the local disk would write it to the wrong machine.
    public func access(for document: GlassEditorDocument) -> any GlassEditorFileAccess {
        if let access = documentAccess[document.id] { return access }
        guard let path = document.path, let owner = project(owning: path),
              let access = projectAccess[owner.id] else {
            return GlassEditorLocalFileAccess()
        }
        return access
    }

    @discardableResult
    public func newDocument(language: LanguageID = .plaintext) -> GlassEditorDocument {
        let document = GlassEditorDocument.untitled(named: untitledName(), language: language)
        apply(to: document)
        documents.append(document)
        selection = document.id
        return document
    }

    /// Closes a document. Returns false when it has unsaved changes and `force` was not given, so
    /// the caller can ask first — losing an edit silently is the one thing an editor cannot do.
    @discardableResult
    public func close(_ id: GlassEditorDocument.ID, force: Bool = false) -> Bool {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return true }
        if documents[index].isDirty, !force { return false }
        documentAccess[id] = nil
        previewModes[id] = nil
        securityScopedURLs.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        if previewDocumentID == id { previewDocumentID = nil }
        documents.remove(at: index)
        if selection == id {
            // The neighbour, not the first: closing a tab should leave you where you were looking.
            selection = documents.indices.contains(index) ? documents[index].id : documents.last?.id
        }
        return true
    }

    // MARK: Saving

    /// A save that stopped to ask, because the file changed underneath the editor.
    ///
    /// Held here rather than on the document so the window has exactly one of them to present: two
    /// documents conflicting at once is two questions in a queue, not two dialogs on top of
    /// each other.
    public private(set) var pendingConflict: GlassEditorConflict?

    /// Saves one document, on whichever machine it lives.
    ///
    /// **The check is the same on both.** A local file changes underneath an editor too — a
    /// checkout, a build, another editor — and the tier-1 stat comparison that catches it costs
    /// one `stat` call. Saving over a change without asking is the one failure an editor cannot
    /// come back from, so it is asked about wherever the file is.
    public func save(_ id: GlassEditorDocument.ID) async {
        guard let document = documents.first(where: { $0.id == id }) else { return }
        // Saving a file is committing to it, whatever opened it.
        makePermanent(id)
        await saveChecking(document)
    }

    private func saveChecking(_ document: GlassEditorDocument) async {
        let access = access(for: document)
        let check = await document.checkBeforeSaving(through: access)
        switch check.state {
        case .noConflict:
            await write(document, through: access, expecting: check.observed)
        case .remoteChangedLocalClean, .remoteChangedLocalDirty, .indeterminate:
            pendingConflict = GlassEditorConflict(documentID: document.id,
                                                  name: document.displayName,
                                                  machine: document.machine,
                                                  state: check.state,
                                                  observed: check.observed)
        }
    }

    /// Goes ahead with a save the user was asked about.
    public func resolveConflict(_ resolution: ConflictResolution) async {
        guard let conflict = pendingConflict,
              let document = documents.first(where: { $0.id == conflict.documentID }) else {
            pendingConflict = nil
            return
        }
        let access = access(for: document)
        let authorized = conflict.observed
        pendingConflict = nil
        switch resolution {
        case .overwriteRemote:
            // Replacing what was on screen when the question was asked, not whatever is there by
            // the time it is answered.
            await write(document, through: access, expecting: authorized)
        case .discardLocalAndReload:
            do { try await document.reload(through: access) } catch {
                message = "\(document.displayName) could not be re-read: \(error.localizedDescription)"
            }
        case .saveLocalCopy, .keepEditing:
            // Nothing is written. "Save a copy" needs a file panel, which is the view's to raise.
            break
        }
    }

    private func write(_ document: GlassEditorDocument,
                       through access: any GlassEditorFileAccess,
                       expecting: RemoteStat?) async {
        do {
            try await document.save(through: access, expecting: expecting)
        } catch {
            message = "\(document.displayName) could not be saved: \(error.localizedDescription)"
        }
    }

    public func save(_ id: GlassEditorDocument.ID, to url: URL) async {
        guard let document = documents.first(where: { $0.id == id }) else { return }
        do {
            try await document.save(to: url)
            preferences.noteRecent(url)
        } catch {
            message = "\(document.displayName) could not be saved: \(error.localizedDescription)"
        }
    }

    /// Saves everything that has a location and is dirty. Reports the ones it could not.
    public func saveAll() async {
        var failures: [String] = []
        for document in documents where document.isDirty {
            guard document.url != nil else { continue }
            let access = access(for: document)
            do { try await document.save(through: access) } catch {
                failures.append(document.displayName)
            }
        }
        if !failures.isEmpty {
            message = "These documents could not be saved: \(failures.joined(separator: ", "))."
        }
    }

    // MARK: Find

    public var findQueryValue: FindQuery {
        FindQuery(pattern: findQuery,
                  kind: findUsesRegularExpression ? .regex : .literal,
                  caseSensitive: findIsCaseSensitive)
    }

    /// Moves the selection to the next match, wrapping. Nothing happens when there is no match,
    /// which is the honest response to a search that found nothing.
    public func findNext(reverse: Bool = false) {
        guard let document = selectedDocument, !findQuery.isEmpty else { return }
        let from = document.model.selectedRange
        let match = reverse
            ? try? document.model.previousMatch(of: findQueryValue, before: from.lowerBound)
            : try? document.model.nextMatch(of: findQueryValue, after: from.upperBound)
        guard let found = match ?? nil else { return }
        document.model.selectedRange = found
    }

    @discardableResult
    public func replaceAll() -> Int {
        guard let document = selectedDocument, !findQuery.isEmpty else { return 0 }
        do {
            return try document.model.replaceAll(of: findQueryValue, with: replacement)
        } catch {
            message = "Replace failed: \(error.localizedDescription)"
            return 0
        }
    }

    // MARK: Projects

    /// Opens a folder as a project on this device.
    ///
    /// The reach is settled here rather than at every draw: whether these files come off a disk or
    /// an SSH connection is a property of where the folder is and where you are, and neither moves
    /// while the project is open.
    @discardableResult
    public func openProject(_ url: URL, access: any GlassEditorFileAccess = GlassEditorLocalFileAccess()) -> GlassEditorProject? {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            message = "\(standardized.lastPathComponent) is not a folder."
            return nil
        }
        // Compared in the same spelling the project is stored in. `URL.path` on a directory keeps
        // its trailing slash, so comparing it against a stored path that has none matched nothing
        // and opened the same folder as a second project every time.
        let wanted = GlassEditorProject.normalized(standardized.path(percentEncoded: false))
        if let existing = projects.first(where: { $0.path == wanted }) {
            return existing
        }
        let project = GlassEditorProject.local(standardized)
        projects.append(project)
        prefersCollapsedSidebar = false
        let root = GlassEditorProjectNode(name: project.displayName, path: project.path, isDirectory: true)
        projectAccess[project.id] = access
        root.beginLoadingChildrenIfNeeded(using: access)
        projectRoots[project.id] = root
        projectReach[project.id] = .thisMachine
        return project
    }

    /// Opens a project that already exists — a folder on another machine, or one from the library.
    ///
    /// The local entry point above asks the file system whether the folder is there; here the
    /// **reader** is the only thing that can answer that, so it is not asked twice. A folder that
    /// has gone, or a machine that is not answering, arrives as the root's `loadError` and is shown
    /// on the row rather than swallowed.
    @discardableResult
    public func openProject(_ project: GlassEditorProject,
                            access: any GlassEditorFileAccess,
                            reach: GlassEditorProjectReach) -> GlassEditorProject {
        // The same folder on the same machine is one project. Both halves matter: `/srv/app` on
        // two machines is two projects, and the path alone would merge them.
        if let existing = projects.first(where: {
            $0.path == project.path && $0.hostID == project.hostID
        }) {
            return existing
        }
        projects.append(project)
        prefersCollapsedSidebar = false
        let root = GlassEditorProjectNode(name: project.displayName, path: project.path,
                                          isDirectory: true)
        projectAccess[project.id] = access
        root.beginLoadingChildrenIfNeeded(using: access)
        projectRoots[project.id] = root
        projectReach[project.id] = reach
        return project
    }

    // MARK: The tree, and where "here" is

    /// The node with this id, anywhere in any open project. Only loaded folders are searched: a
    /// folder nobody has opened has no children to find.
    public func node(_ id: UUID) -> GlassEditorProjectNode? {
        func search(_ node: GlassEditorProjectNode) -> GlassEditorProjectNode? {
            if node.id == id { return node }
            for child in node.children ?? [] {
                if let found = search(child) { return found }
            }
            return nil
        }
        for root in projectRoots.values {
            if let found = search(root) { return found }
        }
        return nil
    }

    public func isExpanded(_ id: UUID) -> Bool { expandedNodes.contains(id) }

    /// Opens or closes a folder, reading it the first time it opens through whichever reader its
    /// project was opened with.
    public func setExpanded(_ expanded: Bool, for id: UUID) {
        guard let node = node(id), node.isDirectory else { return }
        if expanded {
            expandedNodes.insert(id)
            node.beginLoadingChildrenIfNeeded(using: access(for: node))
        } else {
            expandedNodes.remove(id)
        }
    }

    /// The machine a node is on when that machine is not this one, as a name to say out loud.
    /// Nil for a file on this device, which is the ordinary case and needs no sentence.
    public func machineOf(_ node: GlassEditorProjectNode) -> String? {
        let owner = projects.first {
            node.path == $0.path || node.path.hasPrefix($0.path + "/")
        }
        guard let owner, let reach = projectReach[owner.id] else { return nil }
        switch reach {
        case .thisMachine: return nil
        case .overSSH(let host), .unreachable(let host): return host
        }
    }

    /// The reader for the project this node belongs to, found by the path prefix its project root
    /// shares with it — which holds because a child's path is built from its parent's. Falls back
    /// to this device's file system, which is what a node with no project is.
    public func access(for node: GlassEditorProjectNode) -> any GlassEditorFileAccess {
        let owner = projects.first {
            node.path == $0.path || node.path.hasPrefix($0.path + "/")
        }
        guard let owner, let access = projectAccess[owner.id] else {
            return GlassEditorLocalFileAccess()
        }
        return access
    }

    /// The folder the user is in: the selected folder, the **parent** of the selected file, or the
    /// root when exactly one project is open and nothing is selected.
    ///
    /// Choosing a file and asking for something new should put it beside that file — what every
    /// file browser on this platform means by "here". With no projects open at all this is nil, and
    /// New means an untitled document with no home, which is still worth having.
    public var currentFolder: String? {
        if case .node(let id) = sidebarSelection, let node = node(id) {
            return node.isDirectory ? node.path : (node.path as NSString).deletingLastPathComponent
        }
        if projects.count == 1, let only = projects.first, let root = projectRoots[only.id] {
            return root.path
        }
        return nil
    }

    /// Every project at once — what closing the window means. Projects are a view of a folder,
    /// not work in progress: there is nothing to lose by letting go of them, which is why they need
    /// no separate Close command (2026-09-17).
    public func closeAllProjects() {
        for project in projects { closeProject(project.id) }
    }

    public func closeProject(_ id: GlassEditorProject.ID) {
        if let root = projectRoots[id] { forget(root) }
        projects.removeAll { $0.id == id }
        projectRoots[id] = nil
        // Closing the project is what ends the connection it opened. A local reader's close does
        // nothing, so there is no branch here.
        if let access = projectAccess.removeValue(forKey: id) {
            Task { await access.close() }
        }
        projectReach[id] = nil
    }

    /// Drops a closed project's nodes out of the expansion set and the selection, so neither grows
    /// without bound across a session of opening and closing projects.
    private func forget(_ root: GlassEditorProjectNode) {
        func walk(_ node: GlassEditorProjectNode) {
            expandedNodes.remove(node.id)
            if case .node(node.id) = sidebarSelection { sidebarSelection = nil }
            for child in node.children ?? [] { walk(child) }
        }
        walk(root)
    }

    /// What the user calls this project. The folder's own name is the default, not a rule.
    public func rename(_ id: GlassEditorProject.ID, to name: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        projects[index].displayName = trimmed.isEmpty
            ? (projects[index].path as NSString).lastPathComponent
            : trimmed
    }

    /// Re-reads a project's tree from disk — after a build, a checkout, anything that happened
    /// outside the editor.
    public func refreshProject(_ id: GlassEditorProject.ID) {
        guard let root = projectRoots[id] else { return }
        root.invalidate()
        root.beginLoadingChildrenIfNeeded(using: projectAccess[id] ?? GlassEditorLocalFileAccess())
    }

    // MARK: Recents

    /// "Untitled", then "Untitled 2" — never two documents with the same name in one window.
    private func untitledName() -> String {
        let taken = Set(documents.map(\.displayName))
        guard taken.contains("Untitled") else { return "Untitled" }
        var index = 2
        while taken.contains("Untitled \(index)") { index += 1 }
        return "Untitled \(index)"
    }
}

/// An open that stopped to ask, and everything needed to finish it.
public struct GlassEditorPendingOpen {
    public let path: String
    let access: any GlassEditorFileAccess
    public let machine: String?
    let asPreview: Bool
    public let reason: GlassEditorOpenError
}

