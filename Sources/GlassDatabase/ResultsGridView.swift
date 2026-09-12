//
//  ResultsGridView.swift
//  glassdb
//
//  Detachable results grid window — pin query results in spatial space
//

import SwiftUI
import GlassDBKit

struct ResultsGridView: View {
    let resultSetID: UUID

    @Environment(DatabaseSessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @State private var showExporter = false
    @State private var exportFormat: GridExportFormat = .csv
    @State private var exportErrorMessage: String?

    private var locatedResult: (sessionID: UUID, result: QueryResult)? {
        for (sessionID, session) in sessionManager.sessions {
            if let r = session.queryHistory.first(where: { $0.id == resultSetID }) {
                return (sessionID, r)
            }
        }
        return nil
    }

    private var result: QueryResult? { locatedResult?.result }

    var body: some View {
        Group {
            if let locatedResult {
                VStack(alignment: .leading, spacing: 0) {
                    resultHeader(locatedResult.result)
                    Divider()
                    DetachedResultsSurface(
                        sessionID: locatedResult.sessionID,
                        result: locatedResult.result
                    )
                }
            } else {
                ContentUnavailableView(
                    "Result Not Found",
                    systemImage: "tablecells",
                    description: Text("This result set is no longer available.")
                )
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: result.map {
                GridExportDocument(
                    result: $0,
                    format: exportFormat,
                    database: inferredDatabase(from: $0),
                    table: inferredTable(from: $0)
                )
            },
            contentType: exportFormat.contentType,
            defaultFilename: "result_\(resultSetID.uuidString.prefix(8)).\(exportFormat.rawValue)"
        ) { outcome in
            if case .failure(let error) = outcome {
                exportErrorMessage = error.localizedDescription
            }
        }
        .alert("Export Failed", isPresented: .init(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(exportErrorMessage ?? "The result could not be exported.")
        }
    }

    @ViewBuilder
    private func resultHeader(_ result: QueryResult) -> some View {
        #if os(macOS)
        ViewThatFits(in: .horizontal) {
            HStack {
                resultSummary(result)
                Spacer()
                resultActions(result)
            }
            VStack(alignment: .leading, spacing: 12) {
                resultSummary(result)
                resultActions(result)
            }
        }
        .padding(16)
        .accessibilityElement(children: .contain)
        #else
        HStack {
            resultSummary(result)
            Spacer()
            resultActions(result)
        }
        .padding(16)
        .accessibilityElement(children: .contain)
        #endif
    }

    private func resultSummary(_ result: QueryResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.query)
                .font(.system(size: settingsManager.dataGridFontSize, design: .monospaced))
                .lineLimit(2)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label("\(result.rowCount) rows", systemImage: "tablecells")
                if result.isTruncated, let limit = result.appliedRowLimit {
                    Label("More available; limited to \(limit)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Label("\(result.columnCount) columns", systemImage: "rectangle.split.3x1")
                Label(String(format: "%.3fs", result.executionTime), systemImage: "clock")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func resultActions(_ result: QueryResult) -> some View {
        HStack(spacing: 8) {
            Button {
                guard !result.rows.isEmpty, !result.columns.isEmpty else { return }
                PlatformClipboard.copy(GridExportFormatter.tsv(
                    result: result,
                    rowRange: 0...(result.rows.count - 1),
                    columnRange: 0...(result.columns.count - 1)
                ))
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(result.rows.isEmpty || result.columns.isEmpty)
            .help("Copy every displayed row as tab-separated values")

            Menu {
                ForEach(GridExportFormat.allCases) { format in
                    Button(format.displayName) {
                        exportFormat = format
                        showExporter = true
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export this result to a file")
        }
    }

    private func inferredDatabase(from result: QueryResult) -> String {
        result.columns.compactMap(\.sourceSchema).first ?? "export"
    }

    private func inferredTable(from result: QueryResult) -> String {
        result.columns.compactMap(\.sourceTable).first ?? "result_set"
    }
}

private struct DetachedResultsSurface: View {
    let sessionID: UUID
    @State private var document: QueryDocumentTab

    init(sessionID: UUID, result: QueryResult) {
        self.sessionID = sessionID
        _document = State(initialValue: QueryDocumentTab(
            text: result.query,
            isSaved: true,
            result: result
        ))
    }

    var body: some View {
        DataTabView(
            sessionID: sessionID,
            document: $document,
            isWorkspaceActive: true,
            completionIdentifiers: [],
            displaysEditor: false
        )
    }
}
