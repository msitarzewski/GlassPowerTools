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

@MainActor @Observable
public final class GlassEditorWorkspace {
    /// Open documents, in the order they were opened — the order the tab list shows.
    public private(set) var documents: [GlassEditorDocument] = []
    public var selection: GlassEditorDocument.ID?
    /// Files opened before, newest first. Survives launches.
    public private(set) var recents: [URL] = []
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

    /// Recents are bounded because an unbounded list is a slow leak that nobody notices until it
    /// is a thousand entries long — the same defect this project already found in its preferences.
    static let recentsLimit = 20
    static let recentsDefaultsKey = "com.glasspowertools.editor.recents"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recents = Self.loadRecents(from: defaults)
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
            documents.append(document)
            selection = document.id
            noteRecent(standardized)
            return document
        } catch {
            message = "\(standardized.lastPathComponent) could not be opened: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    public func newDocument(language: LanguageID = .plaintext) -> GlassEditorDocument {
        let document = GlassEditorDocument.untitled(named: untitledName(), language: language)
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
            noteRecent(url)
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
        if let existing = projects.first(where: { $0.path == standardized.path(percentEncoded: false) }) {
            return existing
        }
        let project = GlassEditorProject.local(standardized)
        projects.append(project)
        let root = GlassEditorProjectNode(name: project.displayName, path: project.path, isDirectory: true)
        root.loadChildrenIfNeeded(using: reader)
        projectRoots[project.id] = root
        projectReach[project.id] = .thisMachine
        return project
    }

    public func closeProject(_ id: GlassEditorProject.ID) {
        projects.removeAll { $0.id == id }
        projectRoots[id] = nil
        projectReach[id] = nil
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

    func noteRecent(_ url: URL) {
        let standardized = url.standardizedFileURL
        recents.removeAll { $0.standardizedFileURL == standardized }
        recents.insert(standardized, at: 0)
        if recents.count > Self.recentsLimit { recents.removeLast(recents.count - Self.recentsLimit) }
        defaults.set(recents.map(\.absoluteString), forKey: Self.recentsDefaultsKey)
    }

    public func clearRecents() {
        recents = []
        defaults.removeObject(forKey: Self.recentsDefaultsKey)
    }

    private static func loadRecents(from defaults: UserDefaults) -> [URL] {
        let stored = defaults.stringArray(forKey: recentsDefaultsKey) ?? []
        // A file that has since been deleted or moved is dropped on read rather than offered and
        // then failing — a recents list that lies is worse than a short one.
        return stored.compactMap(URL.init(string:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// "Untitled", then "Untitled 2" — never two documents with the same name in one window.
    private func untitledName() -> String {
        let taken = Set(documents.map(\.displayName))
        guard taken.contains("Untitled") else { return "Untitled" }
        var index = 2
        while taken.contains("Untitled \(index)") { index += 1 }
        return "Untitled \(index)"
    }
}
