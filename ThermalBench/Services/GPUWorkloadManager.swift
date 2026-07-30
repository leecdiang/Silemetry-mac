// ThermalBench - GPU Workload Manager
// Bridges Metal compute shaders to Swift for sustained GPU load.
// Uses thermal_gpu_load (heavy) and thermal_gpu_light kernels.
import Metal

final class GPUWorkloadManager {
    private let device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var heavyPipeline: MTLComputePipelineState?
    private var lightPipeline: MTLComputePipelineState?
    private var inputBuffer: MTLBuffer?
    private var outputBuffer: MTLBuffer?

    private var isRunning = false
    private var stopFlag = false
    private var workItem: DispatchWorkItem?

    init?() {
        device = MTLCreateSystemDefaultDevice()
        if device == nil {
            print("[GPUWorkload] No Metal device found")
            return nil
        }
    }

    // MARK: - Setup

    private func prepare() -> Bool {
        guard let device = device else { return false }

        // Load the default Metal library bundled with the app (default.metallib)
        guard let library = device.makeDefaultLibrary() else {
            print("[GPUWorkload] Failed to load default Metal library")
            return false
        }

        guard let heavyFn = library.makeFunction(name: "thermal_gpu_load"),
              let lightFn = library.makeFunction(name: "thermal_gpu_light") else {
            print("[GPUWorkload] Kernel functions not found")
            return false
        }

        do {
            heavyPipeline = try device.makeComputePipelineState(function: heavyFn)
            lightPipeline = try device.makeComputePipelineState(function: lightFn)
        } catch {
            print("[GPUWorkload] Pipeline creation failed: \(error)")
            return false
        }

        commandQueue = device.makeCommandQueue()

        // Small buffers — the kernels are ALU-bound, not memory-bound
        let bufSize = 16 * MemoryLayout<Float>.size * 4  // 16 × float4
        inputBuffer = device.makeBuffer(length: bufSize, options: .storageModeShared)
        outputBuffer = device.makeBuffer(length: bufSize, options: .storageModeShared)

        // Seed input buffer with deterministic values
        if let buf = inputBuffer {
            let ptr = buf.contents().assumingMemoryBound(to: Float.self)
            for i in 0 ..< (bufSize / MemoryLayout<Float>.size) {
                ptr[i] = Float(i) * 0.6180339887
            }
        }

        return true
    }

    // MARK: - Public API

    func start(intensity: GPUIntensity) {
        guard intensity != .off, !isRunning else { return }
        guard prepare() else { return }

        let pipeline: MTLComputePipelineState?
        switch intensity {
        case .light, .combinedSoC:
            // .combinedSoC uses sustained GPU + CPU together;
            // fall through to heavy pipeline for non-light GPU intensity
            pipeline = (intensity == .light) ? lightPipeline : heavyPipeline
        case .sustained:
            pipeline = heavyPipeline
        case .off:
            return
        }

        stopFlag = false
        isRunning = true

        let item = DispatchWorkItem { [weak self] in
            self?.gpuLoop(pipeline: pipeline, intensity: intensity)
        }
        workItem = item
        DispatchQueue.global(qos: .userInitiated).async(execute: item)

        print("[GPUWorkload] Started (\(intensity.displayName))")
    }

    func stop() {
        guard isRunning else { return }
        stopFlag = true
        workItem?.cancel()
        workItem = nil
        isRunning = false
        print("[GPUWorkload] Stopped")
    }

    // MARK: - GPU Dispatch Loop

    private func gpuLoop(pipeline: MTLComputePipelineState?, intensity: GPUIntensity) {
        guard let pipeline = pipeline,
              let queue = commandQueue,
              let input = inputBuffer,
              let output = outputBuffer else { return }

        while !stopFlag {
            autoreleasepool {
                guard let cmdBuf = queue.makeCommandBuffer(),
                      let encoder = cmdBuf.makeComputeCommandEncoder() else { return }

                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(output, offset: 0, index: 0)
                encoder.setBuffer(input, offset: 0, index: 1)

                // Dispatch a moderate grid; kernels are ALU-heavy so even
                // modest thread counts will saturate the GPU.
                let gridSize = MTLSize(width: 1024, height: 1, depth: 1)
                let threadGroupSize = MTLSize(width: 32, height: 1, depth: 1)
                encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
                encoder.endEncoding()
                cmdBuf.commit()
                cmdBuf.waitUntilCompleted()
            }

            // Light mode: give the GPU breathing room
            if intensity == .light {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }
}
