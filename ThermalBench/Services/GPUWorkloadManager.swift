// ThermalBench - GPU Workload Manager
// Bridges Metal compute shaders to Swift for sustained GPU load.
// Uses thermal_gpu_load (heavy) and thermal_gpu_light kernels.
//
// Concurrency: `_isRunning` and `_stopFlag` are guarded by `lock`. Metal resources
// are built in `prepare()` on the calling thread and passed to the worker by value,
// so they are never read and written from two threads at once.
import Metal

final class GPUWorkloadManager {
    private let device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var heavyPipeline: MTLComputePipelineState?
    private var lightPipeline: MTLComputePipelineState?
    private var inputBuffer: MTLBuffer?
    private var outputBuffer: MTLBuffer?

    /// Number of GPU threads dispatched per command buffer.
    /// The output buffer must hold one float4 per thread, and the shader
    /// indexes `output[thread_position_in_grid]` without bounds checking.
    private static let gridWidth = 1024
    /// Threads per threadgroup. Must divide `gridWidth` evenly.
    private static let threadgroupWidth = 32
    /// Shader reads `input[id % inputElementCount]`, so this bounds the input buffer.
    private static let inputElementCount = 16

    private let lock = NSLock()
    private var _isRunning = false
    private var _stopFlag = false
    private var workItem: DispatchWorkItem?

    private var isRunning: Bool {
        get { lock.withLock { _isRunning } }
        set { lock.withLock { _isRunning = newValue } }
    }
    private var stopFlag: Bool {
        get { lock.withLock { _stopFlag } }
        set { lock.withLock { _stopFlag = newValue } }
    }

    init?() {
        device = MTLCreateSystemDefaultDevice()
        if device == nil {
            print("[GPUWorkload] No Metal device found")
            return nil
        }
    }

    // MARK: - Setup (call once, idempotent)

    private func prepare() -> Bool {
        guard let device = device else { return false }

        if commandQueue != nil { return true }  // already prepared

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

        guard let newQueue = device.makeCommandQueue() else {
            print("[GPUWorkload] Failed to create command queue")
            return false
        }

        // float4 stride, not float — the shader treats both buffers as float4 arrays.
        let float4Stride = MemoryLayout<Float>.size * 4
        // One float4 per dispatched thread. Undersizing this causes the shader to
        // write past the end of the buffer for every thread beyond the allocation.
        let outputSize = Self.gridWidth * float4Stride
        let inputSize = Self.inputElementCount * float4Stride

        guard let newInput = device.makeBuffer(length: inputSize, options: .storageModeShared),
              let newOutput = device.makeBuffer(length: outputSize, options: .storageModeShared) else {
            print("[GPUWorkload] Buffer allocation failed")
            return false
        }

        let ptr = newInput.contents().assumingMemoryBound(to: Float.self)
        for i in 0 ..< (inputSize / MemoryLayout<Float>.size) {
            ptr[i] = Float(i) * 0.6180339887
        }

        // Publish only after every resource is ready, so a partial failure above
        // leaves `commandQueue == nil` and `prepare()` stays retryable.
        commandQueue = newQueue
        inputBuffer = newInput
        outputBuffer = newOutput

        return true
    }

    // MARK: - Public API (thread-safe)

    func start(intensity: GPUIntensity) {
        guard intensity != .off else { return }
        lock.lock()
        if _isRunning { lock.unlock(); return }
        _isRunning = true
        _stopFlag = false
        lock.unlock()

        guard prepare() else {
            isRunning = false
            return
        }

        let pipeline: MTLComputePipelineState?
        switch intensity {
        case .light:     pipeline = lightPipeline
        case .sustained,
             .combinedSoC: pipeline = heavyPipeline
        case .off:       isRunning = false; return
        }

        // Snapshot the Metal resources here, on the calling thread, and hand them to
        // the worker as parameters. The worker never touches `self`'s resource
        // properties, so `prepare()` and `gpuLoop` cannot access them concurrently.
        guard let pipeline, let queue = commandQueue,
              let input = inputBuffer, let output = outputBuffer else {
            isRunning = false
            print("[GPUWorkload] Missing pipeline or buffers after prepare")
            return
        }

        let item = DispatchWorkItem { [weak self] in
            self?.gpuLoop(
                pipeline: pipeline,
                queue: queue,
                input: input,
                output: output,
                intensity: intensity
            )
        }
        workItem = item
        DispatchQueue.global(qos: .userInitiated).async(execute: item)

        print("[GPUWorkload] Started (\(intensity.displayName))")
    }

    func stop() {
        lock.lock()
        guard _isRunning else { lock.unlock(); return }
        _stopFlag = true
        _isRunning = false
        let item = workItem
        workItem = nil
        lock.unlock()

        item?.cancel()
        print("[GPUWorkload] Stopped")
    }

    // MARK: - GPU Dispatch Loop

    private func gpuLoop(
        pipeline: MTLComputePipelineState,
        queue: MTLCommandQueue,
        input: MTLBuffer,
        output: MTLBuffer,
        intensity: GPUIntensity
    ) {
        while !stopFlag {
            autoreleasepool {
                guard !stopFlag,
                      let cmdBuf = queue.makeCommandBuffer(),
                      let encoder = cmdBuf.makeComputeCommandEncoder() else { return }

                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(output, offset: 0, index: 0)
                encoder.setBuffer(input, offset: 0, index: 1)

                let gridSize = MTLSize(width: Self.gridWidth, height: 1, depth: 1)
                let threadGroupSize = MTLSize(width: Self.threadgroupWidth, height: 1, depth: 1)
                encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
                encoder.endEncoding()
                cmdBuf.commit()
                cmdBuf.waitUntilCompleted()
            }

            if intensity == .light, !stopFlag {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }
}
