//
//  GlassModelView.swift
//  Glass Power Tools — GlassEditor
//
//  A 3D model, wherever a file is shown (D78 — the owner, 2026-10-16: "we need 3D model support!";
//  asked first: everywhere files open; on Vision Pro, Apple's 3D Quick Look; USDZ, USD and Reality).
//
//  - **Mac, iPhone, iPad:** RealityKit's `RealityView` with orbit controls — drag to turn the model,
//    scroll or pinch to come closer — its camera aimed at the model (`cameraTarget`), which frames it
//    whole. Without the target the view's camera started inside Apple's iMac model (measured, macOS
//    27.2). Not Quick Look's embeddable view on the Mac: it draws through an extension nothing here
//    can check, and none of the Mac's Quick Look extensions claims Reality files; RealityKit opens
//    all three.
//    The camera frames what it aims at by its height, so a model in a portrait view lost its sides
//    (measured, iPhone simulator): it aims at an unseen sphere round the model, sized for the view's
//    shape (`frame(around:viewSize:)`).
//  - **iPhone and iPad:** View in AR, Apple's AR Quick Look (`quickLookPreview`), to stand the model
//    in the room.
//  - **Vision Pro:** the model in the window (`Model3D`), and Apple's Quick Look as it first opens
//    (`PreviewApplication`), a volume to walk around; View in 3D opens it again.
//  Quick Look opens USDZ and Reality files only — a bare USD layer it calls "not supported" — so
//  those stay in the window, without the button (`GlassModelFile.quickLookOpens`).
//

import SwiftUI
import RealityKit
import OSLog
import GlassEditorCore
#if os(visionOS) || os(iOS)
import QuickLook
#endif

public struct GlassModelView: View {
    let url: URL
    /// A text USD layer can be edited as text too; nil where nothing would open it.
    var openAsText: (() -> Void)?
    /// Vision Pro: hand the model to Apple's Quick Look when the view first shows — an opened file,
    /// not a preview glanced at.
    var opensQuickLook: Bool

    @State private var loadable: URL?
    @State private var problem: String?
    @State private var showsAsText = false
    @State private var quickLookOpens = false
    #if os(iOS)
    @State private var arItem: URL?
    #endif
    #if os(visionOS)
    @State private var openedQuickLook = false
    #endif

    private static let logger = Logger(subsystem: "sh.glas", category: "model-view")

    public init(url: URL, openAsText: (() -> Void)? = nil, opensQuickLook: Bool = false) {
        self.url = url
        self.openAsText = openAsText
        self.opensQuickLook = opensQuickLook
    }

    public var body: some View {
        ZStack {
            if let problem {
                ContentUnavailableView {
                    Label("Can't Show This Model", systemImage: "cube.transparent")
                } description: {
                    Text(problem)
                }
            } else if let loadable {
                model(loadable)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Vision Pro's window keeps its bar along the bottom edge: the buttons go at the top there.
        #if os(visionOS)
        .overlay(alignment: .top) { controls }
        #else
        .overlay(alignment: .bottom) { controls }
        #endif
        .task(id: url) { await resolve() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("model-view")
        #if os(iOS)
        .quickLookPreview($arItem)
        #endif
    }

    private func resolve() async {
        problem = nil
        loadable = nil
        do {
            let resolved = try GlassModelFile.loadableURL(for: url)
            showsAsText = openAsText != nil && GlassModelFile.isText(url)
            quickLookOpens = GlassModelFile.quickLookOpens(resolved)
            loadable = resolved
            #if os(visionOS)
            if opensQuickLook, quickLookOpens, !openedQuickLook {
                openedQuickLook = true
                _ = PreviewApplication.open(urls: [resolved])
            }
            #endif
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: any Error) {
        Self.logger.error("A model couldn't be opened: \(error.localizedDescription, privacy: .public)")
        problem = "\(url.lastPathComponent) couldn't be opened as a 3D model. It may be damaged, or use something this device can't show."
    }

    @ViewBuilder
    private func model(_ file: URL) -> some View {
        #if os(visionOS)
        Model3D(url: file) { phase in
            switch phase {
            case .success(let model):
                // Fitted to the width and height: fitted to a window's depth too (`scaledToFit3D`), the
                // model came out too small to see. It stands out of the window toward the person, so
                // its nearer parts look larger: a wide margin keeps them inside the window's edges
                // (measured, visionOS 27.2 simulator).
                model.resizable().scaledToFit().padding(120)
            case .failure(let error):
                Color.clear.onAppear { fail(error) }
            case .empty:
                ProgressView()
            @unknown default:
                ProgressView()
            }
        }
        #else
        GeometryReader { proxy in
            RealityView { content in
                do {
                    let entity = try await Entity(contentsOf: file)
                    content.add(entity)
                    let frame = Self.frame(around: entity, viewSize: proxy.size)
                    content.add(frame)
                    content.cameraTarget = frame
                } catch {
                    fail(error)
                }
            }
            .realityViewCameraControls(.orbit)
        }
        #endif
    }

    #if !os(visionOS)
    /// An unseen sphere round `entity` for the camera to frame. The orbit camera puts what it aims at
    /// in about 45% of the view's height (measured on the Mac and the iPhone simulator), so a sphere
    /// half the model's bounding sphere, widened where the view is taller than it is wide, has the
    /// model fill about 90% of the side that runs out first — turned any way, as its bounding sphere
    /// doesn't change.
    static func frame(around entity: Entity, viewSize: CGSize) -> Entity {
        let bounds = entity.visualBounds(relativeTo: nil)
        let radius = max(simd_length(bounds.extents) / 2, 0.001) * 0.5
        let tall = viewSize.width > 0 ? max(1, Float(viewSize.height / viewSize.width)) : 1
        var unseen = UnlitMaterial(color: .clear)
        unseen.blending = .transparent(opacity: .init(floatLiteral: 0))
        let sphere = ModelEntity(mesh: .generateSphere(radius: radius * tall), materials: [unseen])
        sphere.position = bounds.center
        sphere.name = "model-view-frame"
        return sphere
    }
    #endif

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            #if os(iOS)
            if let loadable, quickLookOpens {
                Button("View in AR", systemImage: "arkit") { arItem = loadable }
                    .accessibilityIdentifier("model-view-ar")
            }
            #endif
            #if os(visionOS)
            if let loadable, quickLookOpens {
                Button("View in 3D", systemImage: "view.3d") { _ = PreviewApplication.open(urls: [loadable]) }
                    .accessibilityIdentifier("model-view-quick-look")
            }
            #endif
            if showsAsText, let openAsText {
                Button("Open as Text", systemImage: "doc.text", action: openAsText)
                    .accessibilityIdentifier("model-view-open-as-text")
            }
        }
        .buttonStyle(.bordered)
        .padding(12)
        #if os(visionOS)
        .padding(.top, 16)
        #endif
    }
}
