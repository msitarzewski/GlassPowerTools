//
//  GlassEditorTextOverrides.swift
//  Glass Power Tools — GlassEditor
//
//  How big the text is, whether it wraps, and whether the line numbers show — asked at three
//  levels, **file over project over global**.
//
//  The app's answer lives in `GlassEditorPreferences` and is true of every document. A project can
//  disagree: one machine's logs want wrapping off and one repository wants 11pt. A single file can
//  disagree with its own project, which is the case nobody can anticipate — a 40,000-line
//  generated file in an otherwise ordinary folder.
//
//  Each level stores only what it *changes*. An unset field is not "the same as the level above",
//  it is a deliberate absence: change the global default and everything that never disagreed
//  follows it. That is the whole reason for the optionals.
//

import Foundation
import GlassEditorCore

/// What one level says about the text, where nil means "whatever the level above says".
public struct GlassEditorTextOverrides: Codable, Hashable, Sendable {
    public var fontSize: Double?
    public var showsLineNumbers: Bool?
    public var wrapsLines: Bool?

    public init(fontSize: Double? = nil, showsLineNumbers: Bool? = nil, wrapsLines: Bool? = nil) {
        self.fontSize = fontSize
        self.showsLineNumbers = showsLineNumbers
        self.wrapsLines = wrapsLines
    }

    /// The bounds a size may take, matching `GlassEditorPreferences.fontSizeRange` — here as well
    /// because this type is not main-actor bound and the cascade has to be callable from anywhere.
    public static let fontSizeRange: ClosedRange<Double> = 8...32

    /// Nothing overridden — this level defers entirely. Stored as nil rather than as an empty
    /// value so a record that has never disagreed carries no field at all.
    public var isEmpty: Bool {
        fontSize == nil && showsLineNumbers == nil && wrapsLines == nil
    }

    /// This level's opinion over a configuration that already carries the levels above it.
    public func applied(to configuration: GlassEditorConfiguration) -> GlassEditorConfiguration {
        var result = configuration
        // Clamped here as well as in the control: an override travels between devices and a
        // build could widen or narrow the range under it.
        if let fontSize { result.fontSize = min(max(fontSize, Self.fontSizeRange.lowerBound),
                                                Self.fontSizeRange.upperBound) }
        if let showsLineNumbers { result.showsLineNumbers = showsLineNumbers }
        if let wrapsLines { result.wrapsLines = wrapsLines }
        return result
    }

    /// The whole cascade in one call: the app's configuration, then the project's disagreements,
    /// then the file's. Pure, so the order is a tested fact rather than a comment.
    public static func resolve(global: GlassEditorConfiguration,
                               project: GlassEditorTextOverrides?,
                               file: GlassEditorTextOverrides?) -> GlassEditorConfiguration {
        let withProject = project?.applied(to: global) ?? global
        return file?.applied(to: withProject) ?? withProject
    }

    /// What the level above this one decided, so a settings row can say what "Default" means
    /// rather than leaving the reader to guess.
    public static func inherited(global: GlassEditorConfiguration,
                                 project: GlassEditorTextOverrides?,
                                 forFile: Bool) -> GlassEditorConfiguration {
        forFile ? resolve(global: global, project: project, file: nil) : global
    }
}
