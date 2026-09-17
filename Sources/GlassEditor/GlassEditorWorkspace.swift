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
        document.model.configuration = preferences.configuration(basedOn: document.model.configuration)
        document.model.theme = preferences.theme
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
    @discardableResult
    public func open(_ url: URL) -> GlassEditorDocument? {
        let standardized = url.standardizedFileURL
        if let existing = documents.first(where: { $0.url?.standardizedFileURL == standardized }) {
            selection = existing.id
            return existing
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            message = GlassEditorWorkspaceError.notAFile(standardized.lastPathComponent).localizedDescription
            return nil
        }
        do {
            let document = try GlassEditorDocument.open(standardized)
            apply(to: document)
            documents.append(document)
            selection = document.id
            preferences.noteRecent(standardized)
            if projects.isEmpty { prefersCollapsedSidebar = true }
            return document
        } catch {
            message = "\(standardized.lastPathComponent) could not be opened: \(error.localizedDescription)"
            return nil
        }
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
        documents.remove(at: index)
        if selection == id {
            // The neighbour, not the first: closing a tab should leave you where you were looking.
            selection = documents.indices.contains(index) ? documents[index].id : documents.last?.id
        }
        return true
    }

    // MARK: Saving

    /// Saves one document. A document with no location reports that rather than inventing one.
    public func save(_ id: GlassEditorDocument.ID) {
        guard let document = documents.first(where: { $0.id == id }) else { return }
        do {
            try document.save()
        } catch {
            message = "\(document.displayName) could not be saved: \(error.localizedDescription)"
        }
    }

    public func save(_ id: GlassEditorDocument.ID, to url: URL) {
        guard let document = documents.first(where: { $0.id == id }) else { return }
        do {
            try document.save(to: url)
            preferences.noteRecent(url)
        } catch {
            message = "\(document.displayName) could not be saved: \(error.localizedDescription)"
        }
    }

    /// Saves everything that has a location and is dirty. Reports the ones it could not.
    public func saveAll() {
        var failures: [String] = []
        for document in documents where document.isDirty {
            guard document.url != nil else { continue }
            do { try document.save() } catch { failures.append(document.displayName) }
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
    public func openProject(_ url: URL, reader: GlassEditorDirectoryReader = GlassEditorLocalDirectoryReader()) -> GlassEditorProject? {
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
        root.loadChildrenIfNeeded(using: reader)
        projectRoots[project.id] = root
        projectReach[project.id] = .thisMachine
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

    /// Opens or closes a folder, reading it the first time it opens.
    public func setExpanded(_ expanded: Bool, for id: UUID,
                            reader: GlassEditorDirectoryReader = GlassEditorLocalDirectoryReader()) {
        guard let node = node(id), node.isDirectory else { return }
        if expanded {
            expandedNodes.insert(id)
            node.loadChildrenIfNeeded(using: reader)
        } else {
            expandedNodes.remove(id)
        }
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
    public func refreshProject(_ id: GlassEditorProject.ID,
                               reader: GlassEditorDirectoryReader = GlassEditorLocalDirectoryReader()) {
        guard let root = projectRoots[id] else { return }
        root.invalidate()
        root.loadChildrenIfNeeded(using: reader)
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
