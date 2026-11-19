import AppKit
import Metal
import QuartzCore
import CoreVideo

/// Metal 渲染：CVPixelBuffer -> MTLTexture -> GPU 采样绘制
/// 与官方一致走零拷贝纹理 + 点采样（整数缩放时可关闭插值）
final class MetalVideoView: NSView {
    struct Vertex {
        var pos: SIMD2<Float>
        var uv: SIMD2<Float>
    }

    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var samplerPoint: MTLSamplerState?
    private var samplerLinear: MTLSamplerState?
    private var textureCache: CVMetalTextureCache?
    private let metalLayer = CAMetalLayer()
    private var lastTexture: MTLTexture?
    private var imageSize = CGSize.zero

    var pointSampling = true {
        didSet { }
    }
    var isHDR = false {
        didSet { applyColorSpace() }
    }

    override init(frame frameRect: NSRect) {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        super.init(frame: frameRect)
        wantsLayer = true
        wantsLayer = true
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        layer = metalLayer
        buildPipeline()
        if let device {
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        applyColorSpace()
    }

    private func applyColorSpace() {
        if isHDR {
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_2020)
        } else {
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
    }

    private func buildPipeline() {
        guard let device else { return }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct Vertex { float2 pos; float2 uv; };
        struct VOut { float4 position [[position]]; float2 uv; };
        vertex VOut v_main(const device Vertex *verts [[buffer(0)]], uint vid [[vertex_id]]) {
            VOut out;
            out.position = float4(verts[vid].pos, 0.0, 1.0);
            out.uv = verts[vid].uv;
            return out;
        }
        fragment float4 f_main(VOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               sampler s [[sampler(0)]]) {
            return tex.sample(s, in.uv);
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil),
              let vfn = library.makeFunction(name: "v_main"),
              let ffn = library.makeFunction(name: "f_main") else { return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try? device.makeRenderPipelineState(descriptor: desc)

        let point = MTLSamplerDescriptor()
        point.minFilter = .nearest
        point.magFilter = .nearest
        samplerPoint = device.makeSamplerState(descriptor: point)

        let linear = MTLSamplerDescriptor()
        linear.minFilter = .linear
        linear.magFilter = .linear
        samplerLinear = device.makeSamplerState(descriptor: linear)
    }

    func display(_ pixelBuffer: CVPixelBuffer) {
        guard let cache = textureCache else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer, nil,
                                                  .bgra8Unorm, width, height, 0, &cvTexture)
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return }
        lastTexture = texture
        imageSize = CGSize(width: width, height: height)
        draw()
    }

    private func draw() {
        guard let drawable = metalLayer.nextDrawable(),
              let pipeline, let queue, let texture = lastTexture else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store

        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }

        let viewSize = metalLayer.drawableSize
        var vertices = aspectFitVertices(view: viewSize, image: imageSize)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<Vertex>.stride * 4, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(pointSampling ? samplerPoint : samplerLinear, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    private func aspectFitVertices(view: CGSize, image: CGSize) -> [Vertex] {
        guard view.width > 0, view.height > 0, image.width > 0, image.height > 0 else {
            return [
                Vertex(pos: [-1, -1], uv: [0, 1]),
                Vertex(pos: [1, -1], uv: [1, 1]),
                Vertex(pos: [-1, 1], uv: [0, 0]),
                Vertex(pos: [1, 1], uv: [1, 0])
            ]
        }
        let imageAspect = Float(image.width / image.height)
        let viewAspect = Float(view.width / view.height)
        var sx: Float = 1
        var sy: Float = 1
        if imageAspect > viewAspect {
            sy = viewAspect / imageAspect
        } else {
            sx = imageAspect / viewAspect
        }
        return [
            Vertex(pos: [-sx, -sy], uv: [0, 1]),
            Vertex(pos: [sx, -sy], uv: [1, 1]),
            Vertex(pos: [-sx, sy], uv: [0, 0]),
            Vertex(pos: [sx, sy], uv: [1, 0])
        ]
    }
}
