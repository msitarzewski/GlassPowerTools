//
//  Logger.swift
//  glassdb
//
//  Structured logging via os.Logger
//

import os

extension Logger {
    static let app = Logger(subsystem: "app.glassdb", category: "app")
    static let database = Logger(subsystem: "app.glassdb", category: "database")
    static let keychain = Logger(subsystem: "app.glassdb", category: "keychain")
    static let settings = Logger(subsystem: "app.glassdb", category: "settings")
    static let connections = Logger(subsystem: "app.glassdb", category: "connections")
    static let query = Logger(subsystem: "app.glassdb", category: "query")
    static let ai = Logger(subsystem: "app.glassdb", category: "ai")
}
