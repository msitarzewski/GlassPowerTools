import Foundation
import MetalKit
import ImageIO
import GlassRDPTransport

@MainActor
final class DesktopMetalRenderer: NSObject, MTKViewDelegate {
    struct Uniforms {
        var contentScale: SIMD2<Float>
        var threshold: Float
        var feather: Float
        var mode: UInt32
        var opacity: Float = 1
        var offset: SIMD2<Float> = .zero
        var keyColor: SIMD3<Float> = [1, 0, 1]
        /// Sub-rectangle of the source texture to draw, so one display can be shown out of a
        /// framebuffer covering several. The whole texture is 0,0 with extent 1,1.
        var sourceOrigin: SIMD2<Float> = .zero
        var sourceExtent: SIMD2<Float> = [1, 1]
    }
    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let cursorPipeline: any MTLRenderPipelineState
    var cursor: DesktopCursorBitmap?
    var pointer: DesktopPoint?
    /// The part of the framebuffer to present. Nil draws all of it.
    var region: DesktopRegion?
    private let slots = DispatchSemaphore(value: 3)
    private var textures: [(any MTLTexture)?] = Array(repeating: nil, count: 3)
    private var cursorTextures: [(any MTLTexture)?] = Array(repeating: nil, count: 3)
    private var slot = 0
    private var reference: (any MTLTexture)?
    private var loadedReferenceURL: URL?
    private var failedReferenceURL: URL?
    private let fallback: any MTLTexture
    private let onError: @MainActor @Sendable (String) -> Void
    var frame: GlassRDPFrame? {
        didSet { if frame == nil { textures = Array(repeating: nil, count: 3); uploaded = nil } }
    }
    /// The picture a texture holds now: which frame, and which part of it. A draw for anything else —
    /// the pointer moving, a setting — draws that texture again rather than uploading the frame.
    private struct Upload: Equatable { let sequence: UInt64; let x: Int, y: Int, width: Int, height: Int }
    private var uploaded: (key: Upload, slot: Int)?
    /// Pictures sent to the GPU, for tests.
    private(set) var uploads = 0
    var settings = PresentationSettings()

    init(device: any MTLDevice, pixelFormat: MTLPixelFormat, onError: @escaping @MainActor @Sendable (String) -> Void) throws {
        self.device = device
        self.onError = onError
        guard let queue = device.makeCommandQueue() else { throw RendererError.unavailable }
        self.queue = queue
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "desktopVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "desktopFragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        cursorPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        textureDescriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { throw RendererError.unavailable }
        var black: UInt32 = 0xff000000
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 4)
        fallback = texture
        super.init()
    }

    func setWallpaper(_ url: URL?) {
        guard let url else {
            reference = nil
            loadedReferenceURL = nil
            failedReferenceURL = nil
            return
        }
        guard url != loadedReferenceURL, url != failedReferenceURL else { return }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: DesktopWallpaperBounds.maximumBytes + 1) ?? Data()
            guard data.count <= DesktopWallpaperBounds.maximumBytes,
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                throw RendererError.wallpaperTooLarge
            }
            try DesktopWallpaperBounds.validate(properties)
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                throw RendererError.invalidWallpaper
            }
            let candidate = try MTKTextureLoader(device: device).newTexture(cgImage: image, options: [.SRGB: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue])
            reference = candidate
            loadedReferenceURL = url
            failedReferenceURL = nil
        } catch {
            failedReferenceURL = url
            onError(error.localizedDescription)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        #if os(macOS)
        view.needsDisplay = true
        #else
        view.setNeedsDisplay()
        #endif
    }

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }
        guard slots.wait(timeout: .now()) == .success else { return }
        var committed = false
        defer { if !committed { slots.signal() } }
        do {
            guard let drawable = view.currentDrawable, let descriptor = view.currentRenderPassDescriptor else { return }
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            descriptor.colorAttachments[0].loadAction = .clear
            guard let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { throw RendererError.unavailable }
            do {
                defer { encoder.endEncoding() }
                try encodeFrame(encoder, size: view.drawableSize)
            }
            command.present(drawable)
            let slots = slots
            let onError = onError
            command.addCompletedHandler { buffer in
                slots.signal()
                if let error = buffer.error { Task { @MainActor in onError(error.localizedDescription) } }
            }
            command.commit()
            committed = true
            slot = (slot + 1) % textures.count
        } catch { onError(error.localizedDescription) }
    }

    private func encodeFrame(_ encoder: any MTLRenderCommandEncoder, size: CGSize) throws {
            if let frame {
            guard frame.width <= DesktopSize.maximumPixels / frame.height else { throw RendererError.frameTooLarge }
            let visible = region ?? .whole(width: frame.width, height: frame.height)
            // Only the window's part of the picture goes to the GPU, and only when it is a new
            // picture. Every draw used to upload the whole framebuffer, on the main thread: a Mac's
            // two displays at their own pixels are 65 MB, uploaded by each display's window, and
            // again for every move of the pointer — the lag the owner felt on a Vision Pro
            // (2026-10-11). Remove Wallpaper samples the wallpaper at the whole picture's
            // coordinates, so it keeps the whole picture.
            let crops = settings.mode != .removeWallpaper && visible.normalized(inWidth: frame.width, height: frame.height) != nil
            let key = crops ? Upload(sequence: frame.sequence, x: visible.origin.x, y: visible.origin.y,
                                     width: visible.size.width, height: visible.size.height)
                            : Upload(sequence: frame.sequence, x: 0, y: 0, width: frame.width, height: frame.height)
            let texture: any MTLTexture
            if let uploaded, uploaded.key == key, let shown = textures[uploaded.slot] {
                texture = shown
            } else {
                // Never the texture last shown: draws still in flight may be reading it.
                let target = uploaded.map { ($0.slot + 1) % textures.count } ?? 0
                if textures[target]?.width != key.width || textures[target]?.height != key.height {
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                        width: key.width, height: key.height, mipmapped: false)
                    descriptor.usage = .shaderRead
                    descriptor.storageMode = .shared
                    textures[target] = device.makeTexture(descriptor: descriptor)
                }
                guard let fresh = textures[target] else { throw RendererError.unavailable }
                frame.pixels.withUnsafeBytes { bytes in
                    if let address = bytes.baseAddress {
                        fresh.replace(region: MTLRegionMake2D(0, 0, key.width, key.height), mipmapLevel: 0,
                                      withBytes: address + key.y * frame.bytesPerRow + key.x * 4, bytesPerRow: frame.bytesPerRow)
                    }
                }
                uploaded = (key, target)
                uploads += 1
                texture = fresh
            }
            let width = Float(size.width), height = Float(size.height)
            let source = crops ? (originX: 0.0, originY: 0.0, extentX: 1.0, extentY: 1.0)
                : visible.normalized(inWidth: frame.width, height: frame.height) ?? (originX: 0, originY: 0, extentX: 1, extentY: 1)
            let sourceWidth = Float(source.extentX) * Float(texture.width)
            let sourceHeight = Float(source.extentY) * Float(texture.height)
            let scale = min(width / sourceWidth, height / sourceHeight)
            let mode: UInt32
            switch settings.mode {
            case .original: mode = 0
            case .removeBlack: mode = 1
            case .removeWallpaper: mode = reference == nil ? 0 : 2
            case .removeColor: mode = 4
            }
            var uniforms = Uniforms(contentScale: SIMD2(sourceWidth * scale / width, sourceHeight * scale / height),
                                    threshold: settings.threshold.isFinite ? min(1, max(0, settings.threshold)) : 0.04,
                                    feather: settings.feather.isFinite ? min(1, max(0.0001, settings.feather)) : 0.02,
                                    mode: mode, opacity: Float(settings.opacity),
                                    keyColor: settings.keyColor,
                                    sourceOrigin: SIMD2(Float(source.originX), Float(source.originY)),
                                    sourceExtent: SIMD2(Float(source.extentX), Float(source.extentY)))
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentTexture(reference ?? fallback, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
    }

    /// Reuses the same upload ring and shader for RealityKit's dynamic surface.
    /// The caller obtains the destination from LowLevelTexture using this buffer.
    @discardableResult
    func drawTexture(destination: (any MTLCommandBuffer) throws -> any MTLTexture) throws -> Bool {
        guard slots.wait(timeout: .now()) == .success else { return false }
        var committed = false
        defer { if !committed { slots.signal() } }
        guard let command = queue.makeCommandBuffer() else { throw RendererError.unavailable }
        let texture = try destination(command)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = .init(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw RendererError.unavailable }
        do {
        defer { encoder.endEncoding() }
        try encodeFrame(encoder, size: CGSize(width: texture.width, height: texture.height))
        if let frame, let cursor, let pointer {
            if cursorTextures[slot]?.width != cursor.width || cursorTextures[slot]?.height != cursor.height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                    width: cursor.width, height: cursor.height, mipmapped: false)
                descriptor.usage = .shaderRead
                descriptor.storageMode = .shared
                cursorTextures[slot] = device.makeTexture(descriptor: descriptor)
            }
            guard let image = cursorTextures[slot] else { throw RendererError.unavailable }
            let pixels = try cursor.compositedPixels(over: frame, pointerX: pointer.x, pointerY: pointer.y)
            pixels.withUnsafeBytes { bytes in
                if let address = bytes.baseAddress {
                    image.replace(region: MTLRegionMake2D(0, 0, cursor.width, cursor.height), mipmapLevel: 0,
                                  withBytes: address, bytesPerRow: cursor.width * 4)
                }
            }
            let visible = region ?? .whole(width: frame.width, height: frame.height)
            let visibleWidth = Float(visible.size.width), visibleHeight = Float(visible.size.height)
            let localX = Float(pointer.x - visible.origin.x), localY = Float(pointer.y - visible.origin.y)
            var uniforms = Uniforms(contentScale: [Float(cursor.width) / visibleWidth, Float(cursor.height) / visibleHeight],
                threshold: 0, feather: 0, mode: 3,
                offset: [2 * (localX - Float(cursor.hotSpotX)) / visibleWidth - 1 + Float(cursor.width) / visibleWidth,
                         1 - 2 * (localY - Float(cursor.hotSpotY)) / visibleHeight - Float(cursor.height) / visibleHeight])
            encoder.setRenderPipelineState(cursorPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.setFragmentTexture(image, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        }
        let slots = slots, onError = onError
        command.addCompletedHandler { buffer in
            slots.signal()
            if let error = buffer.error { Task { @MainActor in onError(error.localizedDescription) } }
        }
        command.commit(); committed = true; slot = (slot + 1) % textures.count
        return true
    }

    static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Uniforms { float2 contentScale; float threshold; float feather; uint mode; float opacity; float2 offset; float3 keyColor; float2 sourceOrigin; float2 sourceExtent; };
    struct VertexOut { float4 position [[position]]; float2 uv; };
    vertex VertexOut desktopVertex(uint index [[vertex_id]], constant Uniforms &u [[buffer(0)]]) {
        const float2 points[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
        float2 p = points[index];
        float2 unit = float2((p.x + 1) * 0.5, (1 - p.y) * 0.5);
        return {float4(p * u.contentScale + u.offset, 0, 1), u.sourceOrigin + unit * u.sourceExtent};
    }
    fragment float4 desktopFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]],
                                     texture2d<float> desktop [[texture(0)]], texture2d<float> wallpaper [[texture(1)]]) {
        constexpr sampler sampleFilter(filter::linear, address::clamp_to_edge);
        float4 sample = desktop.sample(sampleFilter, in.uv);
        if (u.mode == 3) return sample;
        float3 rgb = sample.rgb;
        float alpha = 1;
        if (u.mode != 0) {
            float3 reference = u.mode == 1 ? float3(0) : (u.mode == 4 ? u.keyColor : wallpaper.sample(sampleFilter, in.uv).rgb);
            float3 difference = abs(rgb - reference);
            float distance = max(difference.r, max(difference.g, difference.b));
            alpha = smoothstep(u.threshold, u.threshold + u.feather, distance);
        }
        alpha *= u.opacity;
        return float4(rgb * alpha, alpha);
    }
    """
}

enum RendererError: Error, Equatable, LocalizedError {
    case unavailable, wallpaperTooLarge, invalidWallpaper, frameTooLarge
    var errorDescription: String? {
        switch self {
        case .unavailable: "Metal presentation is unavailable on this device."
        case .wallpaperTooLarge: "Choose a wallpaper image no larger than 8192 pixels per side and 16 million pixels."
        case .invalidWallpaper: "The selected wallpaper image could not be decoded."
        case .frameTooLarge: "The remote desktop exceeds the presentation memory limit."
        }
    }
}

enum DesktopWallpaperBounds {
    static let maximumBytes = 64 * 1024 * 1024
    static func validate(_ properties: [CFString: Any]) throws {
        guard let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, (1...8192).contains(width), (1...8192).contains(height),
              width.rounded() == width, height.rounded() == height,
              width * height <= Double(DesktopSize.maximumPixels) else { throw RendererError.wallpaperTooLarge }
    }
}
