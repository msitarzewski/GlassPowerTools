//
//  SQLiteFileImporter.swift
//  Glass Power Tools — GlassDatabase
//
//  Importing a SQLite database into the app's managed storage, and validating that a saved path
//  still points inside it.
//
//  Extracted verbatim from `ConnectionFormView.swift` on 2026-09-12, where it sat above a form
//  that the merged product never presents: the shell's setup sheet replaced it and the view had
//  no call sites left. This was the only live thing in that file, and it belongs beside its three
//  callers — `DatabaseServiceDraft`, `DatabaseSessionManager` and `ConnectionManager` — rather
//  than at the top of a deleted one. No behaviour changed; the type is still internal to this
//  module, so no call site changed either.
//

import Foundation
import GlassDBKit

enum SQLiteFileImporter {
    enum ImportError: LocalizedError {
        case sourceIsNotAFile
        case managedCopyMissing
        case outsideManagedDirectory

        var errorDescription: String? {
            switch self {
            case .sourceIsNotAFile:
                return "The selected SQLite item is not a readable file."
            case .managedCopyMissing:
                return "The imported SQLite database is missing. Import it again."
            case .outsideManagedDirectory:
                return "The SQLite database is outside this app’s managed storage. Import it again."
            }
        }
    }

    static func managedDirectory(
        fileManager: FileManager = .default,
        create: Bool
    ) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let directory = applicationSupport
            .appendingPathComponent("glassdb", isDirectory: true)
            .appendingPathComponent("SQLite Databases", isDirectory: true)
        if create {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func importFile(
        at sourceURL: URL,
        fileManager: FileManager = .default,
        destinationID: UUID = UUID()
    ) throws -> URL {
        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw ImportError.sourceIsNotAFile }

        let directory = try managedDirectory(fileManager: fileManager, create: true)
        let fileExtension = sourceURL.pathExtension.isEmpty ? "sqlite" : sourceURL.pathExtension
        let importedURL = directory
            .appendingPathComponent(destinationID.uuidString)
            .appendingPathExtension(fileExtension)
        do {
            try SQLiteEngine.createManagedSnapshot(
                from: sourceURL,
                at: importedURL,
                fileManager: fileManager
            )
            return try validatedURL(forPath: importedURL.path, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: importedURL)
            throw error
        }
    }

    static func validatedURL(
        forPath path: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let candidate = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: candidate.path) else {
            throw ImportError.managedCopyMissing
        }
        let root = try managedDirectory(fileManager: fileManager, create: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count > rootComponents.count,
              candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents) else {
            throw ImportError.outsideManagedDirectory
        }
        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw ImportError.sourceIsNotAFile }
        return candidate
    }
}
