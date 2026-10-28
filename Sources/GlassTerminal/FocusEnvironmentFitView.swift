//
//  FocusEnvironmentFitView.swift
//  Glass Power Tools — GlassTerminal
//
//  Try Out on Vision Pro: one of the person's 3D environments opened all the way around them, with a
//  window to fit it (the owner, 2026-10-26: "We need 'try out' room with sliders for scale ... So we
//  can 'preview' the room and set scale with slider"). What its numbers are in, its size, its floor,
//  and where to start; each change shows at once, and Done keeps it beside the file for every Vision
//  Pro (`FocusRoomFit`). Moving about works here as it does in Focus Mode (`FocusEnvironmentWalking`).
//

import SwiftUI

#if os(visionOS)
struct FocusEnvironmentFitView: View {
    let environmentID: String
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    private let stage = FocusEnvironmentStage.shared
    private let library = FocusEnvironmentLibrary.shared
    /// Whether Try Out opened the space, so closes it after; otherwise Focus Mode was open, and gets
    /// back the environment it had.
    @State private var openedSpace = false
    @State private var previousID: String?
    @State private var begun = false
    @State private var finished = false

    static let windowID = "focus-environment-fit"

    private var name: String { library.name(ofID: environmentID) }
    /// The room is open around the person and has said what it is.
    private var ready: Bool { stage.environmentID == environmentID && stage.room != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let note = stage.note {
                        Label(note, systemImage: "info.circle")
                            .accessibilityIdentifier("focus-fit-note")
                    }
                    LabeledContent("Size", value: sizeText)
                        .accessibilityIdentifier("focus-fit-size")
                } footer: {
                    Text("It changes around you as you go. A room that's too big or too small usually has the wrong units: pick the ones its numbers are really in, then adjust.")
                }
                Section("Size") {
                    Picker("Its numbers are in", selection: units) {
                        Text(fileUnitsTitle).tag(FocusRoomUnits?.none)
                        ForEach(FocusRoomUnits.allCases, id: \.self) { units in
                            Text(units.title).tag(Optional(units))
                        }
                    }
                    .accessibilityIdentifier("focus-fit-units")
                    Slider(value: size, in: 0...1) {
                        Text("Size")
                    } minimumValueLabel: {
                        Text("¼×")
                    } maximumValueLabel: {
                        Text("4×")
                    }
                    .accessibilityValue(percent)
                    .accessibilityIdentifier("focus-fit-scale")
                    LabeledContent("Adjusted", value: percent)
                }
                Section("Floor") {
                    Slider(value: floor, in: FocusRoomFit.floors, step: 0.05) {
                        Text("Floor")
                    } minimumValueLabel: {
                        Image(systemName: "arrow.down")
                    } maximumValueLabel: {
                        Image(systemName: "arrow.up")
                    }
                    .accessibilityValue(floorText)
                    .accessibilityIdentifier("focus-fit-floor")
                    LabeledContent("Raised", value: floorText)
                }
                Section {
                    Button("Start Here", systemImage: "figure.stand") {
                        if let here = stage.walking?.placeInFile() { stage.fit.start = here }
                    }
                    .accessibilityIdentifier("focus-fit-start-here")
                    if stage.fit.start != nil {
                        Button("Forget Where to Start", systemImage: "arrow.uturn.backward") { stage.fit.start = nil }
                    }
                } header: {
                    Text("Where You Start")
                } footer: {
                    Text(startFooter)
                }
                Section("Moving Around") {
                    Text("Look down at the floor where you want to go and pinch: a green target shows. Move your hand the way you want to face, then let go. Raise your hand to cancel. To turn, pinch the sky or a wall and swing your hand left or right.")
                        .font(.callout)
                }
            }
            .disabled(!ready)
            .navigationTitle("Fit “\(name)”")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { stage.fit = FocusRoomFit() }
                        .disabled(!ready || stage.fit == FocusRoomFit())
                        .accessibilityIdentifier("focus-fit-reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Task { await finish() } }
                        .accessibilityIdentifier("focus-fit-done")
                }
            }
        }
        .task { await begin() }
        .onDisappear { Task { await finish(closing: true) } }
    }

    // MARK: - Opening and closing

    private func begin() async {
        guard !begun else { return }
        begun = true
        library.start()
        previousID = stage.isOpen ? stage.environmentID : nil
        stage.tryingOut = environmentID
        stage.environmentID = environmentID
        if !stage.isOpen {
            openedSpace = await openImmersiveSpace(id: "focus-environment") == .opened
        }
    }

    /// Keeps the fit beside the file, and leaves the space as Try Out found it.
    private func finish(closing: Bool = false) async {
        guard begun, !finished else { return }
        finished = true
        if ready, let environment = library.environment(withID: environmentID) {
            await library.save(stage.fit, for: environment)
        }
        stage.tryingOut = nil
        if openedSpace {
            await dismissImmersiveSpace()
        } else if let previousID {
            stage.environmentID = previousID
        }
        if !closing { dismissWindow(id: Self.windowID, value: environmentID) }
    }

    // MARK: - Bindings

    private var units: Binding<FocusRoomUnits?> {
        Binding(get: { stage.fit.units }, set: { stage.fit.units = $0 })
    }

    private var size: Binding<Double> {
        Binding(get: { FocusRoomFit.sliderValue(forSize: stage.fit.size) },
                set: { stage.fit.size = FocusRoomFit.size(forSliderValue: $0) })
    }

    private var floor: Binding<Double> {
        Binding(get: { stage.fit.floor }, set: { stage.fit.floor = ($0 * 100).rounded() / 100 })
    }

    // MARK: - Words

    /// "As the file says (centimetres)".
    private var fileUnitsTitle: String {
        guard let room = stage.room else { return "As the file says" }
        if let named = FocusRoomUnits(metresPerUnit: room.fileMetresPerUnit) {
            return "As the file says (\(named.title.lowercased()))"
        }
        return "As the file says (\(Self.length(room.fileMetresPerUnit)) each)"
    }

    private var sizeText: String {
        guard let room = stage.room else { return stage.environmentID == environmentID ? "Opening…" : "—" }
        let fitted = room.size * stage.fit.scale(fileMetresPerUnit: room.fileMetresPerUnit)
        return "\(Self.length(fitted.x)) wide, \(Self.length(fitted.y)) tall, \(Self.length(fitted.z)) deep"
    }

    private var percent: String {
        "\(Int((stage.fit.size * 100).rounded()))%"
    }

    private var floorText: String {
        Self.floorWords(stage.fit.floor)
    }

    /// "Raised 3 cm".
    static func floorWords(_ floor: Double) -> String {
        if abs(floor) < 0.005 { return "Standing on the floor" }
        return floor > 0 ? "Raised \(length(floor))" : "Lowered \(length(-floor))"
    }

    private var startFooter: String {
        if stage.fit.start != nil { return "You start where you stood when you chose Start Here, facing the same way." }
        if stage.room?.hasCamera == true { return "You start at the file's own camera. Move to where you'd rather be, face the way you'd like, and choose Start Here." }
        return "You start in the middle of a room, or before something smaller. Move to where you'd rather be, face the way you'd like, and choose Start Here."
    }

    /// Metres in words: "3.2 m", "45 cm", "4 mm".
    static func length(_ metres: Double) -> String {
        guard metres.isFinite else { return "—" }
        let size = abs(metres)
        if size >= 1 { return String(format: "%.1f m", metres) }
        if size >= 0.01 { return "\(Int((metres * 100).rounded())) cm" }
        return "\(Int((metres * 1000).rounded())) mm"
    }
}
#endif
