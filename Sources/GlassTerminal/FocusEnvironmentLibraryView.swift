//
//  FocusEnvironmentLibraryView.swift
//  Glass Power Tools — GlassTerminal
//
//  Settings ▸ Terminal ▸ Focus Mode on Vision Pro: the environment library as pictures, the one
//  every window uses marked, and the person's own added from Files, dropped on it, or put in
//  iCloud Drive ▸ Glass Power Tools ▸ Environments from any device (`FocusEnvironments.swift`).
//

import SwiftUI
import UniformTypeIdentifiers
import ImageIO

#if os(visionOS)
import QuickLookThumbnailing

/// The library, to choose from and add to. `chosen` is the environment it marks.
struct FocusEnvironmentLibrarySection: View {
    @Binding var chosen: String
    @Binding var opensImmersed: Bool
    /// How loud a room's own sounds are, 0 to 1.
    @Binding var soundLevel: Double
    @Environment(\.openWindow) private var openWindow
    private let library = FocusEnvironmentLibrary.shared
    @State private var pictures = FocusEnvironmentPictures.shared
    @State private var importing = false
    @State private var adding = false
    @State private var problems: [FocusEnvironmentImportProblem] = []
    @State private var deleting: FocusEnvironment?

    static let addableTypes: [UTType] = [.usdz, .realityFile, .image]

    var body: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 16) {
                ForEach(library.environments) { environment in
                    card(environment)
                }
            }
            .padding(.vertical, 6)
            .onDrop(of: Self.addableTypes, isTargeted: nil) { providers in
                Task { await add(dropped: providers) }
                return true
            }
            Button {
                importing = true
            } label: {
                Label(adding ? "Adding…" : "Add Environment…", systemImage: "plus")
            }
            .disabled(adding)
            .accessibilityIdentifier("focus-environment-add")
            if let room = library.environment(withID: chosen), case .room = room.kind {
                Button {
                    tryOut(room)
                } label: {
                    Label("Try Out and Fit “\(room.name)”…", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityIdentifier("focus-environment-try-out")
            }
            Toggle("Open Immersed", isOn: $opensImmersed)
                .accessibilityIdentifier("focus-environment-opens-immersed")
            LabeledContent("Room Sound") {
                Slider(value: $soundLevel, in: 0...1) {
                    Text("Room Sound")
                } minimumValueLabel: {
                    Image(systemName: "speaker.slash")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3")
                }
                .frame(maxWidth: 320)
                .accessibilityIdentifier("focus-environment-sound")
            }
        } header: {
            Text("Focus Mode")
        } footer: {
            Text(footer)
        }
        .onAppear { library.start() }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.addableTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            Task { await add(urls) }
        }
        .alert(problems.count == 1 ? "This Couldn't Be Added" : "These Couldn't Be Added",
               isPresented: Binding(get: { !problems.isEmpty }, set: { if !$0 { problems = [] } })) {
            Button("OK") { problems = [] }
        } message: {
            Text(problems.map(\.message).joined(separator: "\n\n"))
        }
        .confirmationDialog(deleting.map { "Delete “\($0.name)”?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let deleting {
                    if chosen == deleting.id { chosen = FocusEnvironment.defaultID }
                    library.remove(deleting)
                }
                deleting = nil
            }
        } message: {
            Text(library.storage == .iCloud
                 ? "It goes from iCloud Drive, and from every device that shares it."
                 : "It goes from this Vision Pro.")
        }
    }

    private var footer: String {
        let what = "What surrounds you in Focus Mode, the moon in a terminal's bar. Add a 3D room (USDZ or Reality) or a 360° photo, a picture twice as wide as it is tall."
        let window = "A window can have its own in This Window, or from the moon's pinch-and-hold menu. Open Immersed starts Focus Mode all the way around you instead of partway; the Digital Crown still brings your room back. Room Sound is how loud a room's own sounds are, from a folder named like the room beside it (Loft.sounds beside Loft.usdz)."
        switch library.storage {
        case .iCloud:
            return "\(what) Yours are in iCloud Drive ▸ Glass Power Tools ▸ Environments, so a file put there from your Mac or iPhone appears here too. \(window)"
        case .device, .finding:
            return "\(what) iCloud Drive isn't available, so the ones you add stay on this Vision Pro. \(window)"
        }
    }

    private func card(_ environment: FocusEnvironment) -> some View {
        let isChosen = chosen == environment.id
        return Button {
            chosen = environment.id
            if !environment.isDownloaded { library.download(environment) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                picture(environment)
                    .aspectRatio(2, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isChosen ? Color.accentColor : Color.white.opacity(0.12), lineWidth: isChosen ? 3 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if !environment.isDownloaded {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.caption)
                                .padding(6)
                                .accessibilityHidden(true)
                        }
                    }
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(environment.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(kindTitle(environment))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if isChosen {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(8)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .contextMenu {
            if case .room = environment.kind {
                Button("Try Out and Fit…", systemImage: "arrow.up.left.and.arrow.down.right") { tryOut(environment) }
            }
            if environment.isOwn {
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = environment }
            }
        }
        .accessibilityLabel("\(environment.name), \(kindTitle(environment))")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityIdentifier("focus-environment-\(environment.id)")
        .task(id: environment) { await pictures.make(for: environment) }
    }

    @ViewBuilder
    private func picture(_ environment: FocusEnvironment) -> some View {
        if let image = pictures.image(for: environment) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(.black.opacity(0.35))
                Image(systemName: symbol(environment))
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func kindTitle(_ environment: FocusEnvironment) -> String {
        switch environment.kind {
        case .builtIn(.dimmed): "The room, dimmed"
        case .builtIn: "Built in"
        case .photo: environment.isDownloaded ? "360° photo" : "360° photo, in iCloud"
        case .room: environment.isDownloaded ? "3D room" : "3D room, in iCloud"
        }
    }

    private func symbol(_ environment: FocusEnvironment) -> String {
        switch environment.kind {
        case .builtIn: "moon"
        case .photo: "pano"
        case .room: "cube.transparent"
        }
    }

    /// Opens a 3D environment around the person with a window to fit it (`FocusEnvironmentFitView`).
    private func tryOut(_ environment: FocusEnvironment) {
        if !environment.isDownloaded { library.download(environment) }
        openWindow(id: FocusEnvironmentFitView.windowID, value: environment.id)
    }

    private func add(_ urls: [URL]) async {
        adding = true
        let refused = await library.add(urls)
        adding = false
        problems = refused
    }

    /// Files dropped from Files or another app: each copied out of the drop before it ends.
    private func add(dropped providers: [NSItemProvider]) async {
        var urls: [URL] = []
        let holding = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: holding, withIntermediateDirectories: true)
        for provider in providers {
            guard let type = Self.addableTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else { continue }
            let copied: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                    guard let url else { return continuation.resume(returning: nil) }
                    let name = provider.suggestedName.map { "\($0).\(url.pathExtension)" } ?? url.lastPathComponent
                    let destination = holding.appendingPathComponent(
                        (name as NSString).pathExtension.isEmpty ? url.lastPathComponent : name)
                    continuation.resume(returning: (try? FileManager.default.copyItem(at: url, to: destination)) != nil ? destination : nil)
                }
            }
            if let copied { urls.append(copied) }
        }
        if !urls.isEmpty { await add(urls) }
        try? FileManager.default.removeItem(at: holding)
    }
}

/// The library's pictures: a built-in's preview, drawn here; a photo, made small; a room's, as
/// Quick Look sees it. Made once each, while the library is shown.
@Observable
final class FocusEnvironmentPictures {
    static let shared = FocusEnvironmentPictures()
    private var images: [String: CGImage] = [:]
    @ObservationIgnored private var making: Set<String> = []

    func image(for environment: FocusEnvironment) -> CGImage? {
        images[key(environment)]
    }

    func make(for environment: FocusEnvironment) async {
        let key = key(environment)
        guard images[key] == nil, !making.contains(key), environment.isDownloaded else { return }
        making.insert(key)
        defer { making.remove(key) }
        let image: CGImage?
        switch environment.kind {
        case .builtIn(let builtIn):
            image = await Task.detached(priority: .utility) { FocusEnvironmentArt.preview(builtIn) }.value
        case .photo:
            guard let file = environment.file else { return }
            image = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                kCGImageSourceThumbnailMaxPixelSize: 720,
                                                kCGImageSourceCreateThumbnailWithTransform: true]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
        case .room:
            guard let file = environment.file else { return }
            let request = QLThumbnailGenerator.Request(fileAt: file, size: CGSize(width: 360, height: 180), scale: 2,
                                                       representationTypes: .thumbnail)
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
        }
        if let image { images[key] = image }
    }

    /// A file's picture is made again when the file changes.
    private func key(_ environment: FocusEnvironment) -> String {
        guard let file = environment.file else { return environment.id }
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSinceReferenceDate ?? 0
        return "\(environment.id)@\(modified)"
    }
}
#endif
