//
//  FocusEnvironmentNudgeView.swift
//  Glass Power Tools — GlassTerminal
//
//  Fine Position on Vision Pro (the owner, 2026-10-28: "How can we allow micro adjustments? Right
//  now it's almost impossible to get the right position as it relates to the desk surface"; of four
//  ways offered, he chose this and sliding by hand). A small window from the moon's pinch-and-hold
//  menu, placed by the system beside the person: steps of 2 cm the way they face, turns of 1°, the
//  room a centimetre up or down, each held to keep going. Keep This Spot makes where they stand the
//  room's start on every Vision Pro (`FocusRoomFit`); the room's height is kept as it changes.
//

import SwiftUI

#if os(visionOS)
struct FocusEnvironmentNudgeView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    private let stage = FocusEnvironmentStage.shared
    private let library = FocusEnvironmentLibrary.shared
    /// The fit's next save: at once for a spot, a moment after the last press for the height, so a
    /// held button writes once.
    @State private var saving: Task<Void, Never>?

    static let windowID = "focus-environment-nudge"

    /// A room is open around the person.
    private var ready: Bool { stage.isOpen && stage.room != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if !ready {
                    Label("Open Focus Mode in one of your 3D rooms, then fine-tune where you stand here.",
                          systemImage: "info.circle")
                        .font(.callout)
                }
                Group {
                    pad
                    Text(fromStart)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("From where you start: \(fromStart)")
                        .accessibilityIdentifier("focus-nudge-from-start")
                    Divider()
                    HStack {
                        held("Lower the Room", "arrow.down", id: "lower") { raiseRoom(by: -FocusRoomFit.floorStep) }
                        Spacer()
                        VStack(spacing: 2) {
                            Text("Room Height")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(FocusEnvironmentFitView.floorWords(stage.fit.floor))
                                .accessibilityIdentifier("focus-nudge-height")
                        }
                        Spacer()
                        held("Raise the Room", "arrow.up", id: "raise") { raiseRoom(by: FocusRoomFit.floorStep) }
                    }
                    Divider()
                    Button("Keep This Spot", systemImage: "figure.stand", action: keep)
                        .accessibilityIdentifier("focus-nudge-keep")
                }
                .disabled(!ready)
                Text("Steps of 2 cm the way you face and turns of 1°; the room 1 cm at a time, to line its desk up with yours. Hold a button to keep going. Keep This Spot starts you here, facing this way, each time “\(library.name(ofID: stage.environmentID))” opens, on every Vision Pro.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(width: 400)
            .navigationTitle("Fine Position")
        }
        .onChange(of: stage.isOpen) { _, open in
            if !open { dismissWindow(id: Self.windowID) }
        }
    }

    /// Forward, back, left and right round the person, and a turn in each top corner.
    private var pad: some View {
        Grid(horizontalSpacing: 20, verticalSpacing: 14) {
            GridRow {
                held("Turn Left", "arrow.counterclockwise", id: "turn-left") { stage.walking?.nudge(turn: FocusLocomotion.nudgeTurn) }
                held("Step Forward", "chevron.up", id: "forward") { stage.walking?.nudge(forward: FocusLocomotion.nudgeStep) }
                held("Turn Right", "arrow.clockwise", id: "turn-right") { stage.walking?.nudge(turn: -FocusLocomotion.nudgeTurn) }
            }
            GridRow {
                held("Step Left", "chevron.left", id: "left") { stage.walking?.nudge(right: -FocusLocomotion.nudgeStep) }
                Image(systemName: "figure.stand")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                held("Step Right", "chevron.right", id: "right") { stage.walking?.nudge(right: FocusLocomotion.nudgeStep) }
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                held("Step Back", "chevron.down", id: "back") { stage.walking?.nudge(forward: -FocusLocomotion.nudgeStep) }
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
    }

    /// A round button that acts again and again while it is held.
    private func held(_ title: String, _ symbol: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .buttonRepeatBehavior(.enabled)
        .accessibilityIdentifier("focus-nudge-\(id)")
    }

    // MARK: - Actions

    private func raiseRoom(by metres: Double) {
        stage.fit = stage.fit.raised(by: metres)
        save(after: .seconds(1))
    }

    private func keep() {
        guard let here = stage.walking?.placeInFile() else { return }
        stage.fit.start = here
        save(after: .zero)
    }

    /// Keeps the fit beside the room's file, for every Vision Pro.
    private func save(after delay: Duration) {
        saving?.cancel()
        let id = stage.environmentID, fit = stage.fit
        saving = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let environment = library.environment(withID: id) else { return }
            await library.save(fit, for: environment)
        }
    }

    // MARK: - Words

    /// Read again each time the person moves.
    private var fromStart: String {
        _ = stage.moves
        guard let offset = stage.walking?.fromStart(stage.fit) else { return "—" }
        return Self.words(offset)
    }

    /// "4 cm ahead, 2 cm left, turned 1° right"; "Where you start".
    static func words(_ offset: FocusOffset) -> String {
        var parts: [String] = []
        if (offset.ahead * 100).rounded() != 0 {
            parts.append("\(FocusEnvironmentFitView.length(abs(offset.ahead))) \(offset.ahead > 0 ? "ahead" : "back")")
        }
        if (offset.right * 100).rounded() != 0 {
            parts.append("\(FocusEnvironmentFitView.length(abs(offset.right))) \(offset.right > 0 ? "right" : "left")")
        }
        let degrees = Int((offset.turn * 180 / .pi).rounded())
        if degrees != 0 { parts.append("turned \(abs(degrees))° \(degrees > 0 ? "left" : "right")") }
        return parts.isEmpty ? "Where you start" : parts.joined(separator: ", ")
    }
}
#endif
