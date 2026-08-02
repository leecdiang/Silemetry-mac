// ThermalBench - GPU Workload Manager
// Bridges Metal compute shaders to Swift for sustained GPU load.
// Uses thermal_gpu_load (heavy) and thermal_gpu_light kernels.
// Thread-safe: all state mutations are serialised through a private queue.
import Metal

final class GPUWorkloadManager {
    /// GPU threads dispatched per frame; must match the shader grid size.
    private static let elementCount = 1024

    private let device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var heavyPipeline: MTLComputePipelineState?
    private var lightPipeline: MTLComputePipelineState?
    private var inputBuffer: MTLBuffer?
    private var outputBuffer: MTLBuffer?

    private let lock = NSLock()
    private var _isRunning = false
    private var _stopFlag = false
    private var _generation = 0
    private var workItem: DispatchWorkItem?
    /// Signalled when a dispatch loop actually exits (used by stop() to wait).
    private let loopGroup = DispatchGroup()

    private var stopFlag: Bool {
        get { lock.withLock { _stopFlag } }
        set { lock.withLock { _stopFlag = newValue } }
    }
    private var generation: Int {
        lock.withLock { _generation }
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

        commandQueue = device.makeCommandQueue()

        // Must match the 1024-thread grid dispatched per frame.
        let bufSize = Self.elementCount * MemoryLayout<SIMD4<Float>>.stride
        inputBuffer = device.makeBuffer(length: bufSize, options: .storageModeShared)
        outputBuffer = device.makeBuffer(length: bufSize, options: .storageModeShared)

        if let buf = inputBuffer {
            let ptr = buf.contents().assumingMemoryBound(to: Float.self)
            for i in 0 ..< (bufSize / MemoryLayout<Float>.size) {
                ptr[i] = Float(i) * 0.6180339887
            }
        }

        return true
    }

    // MARK: - Public API (thread-safe)

    func start(intensity: GPUIntensity) {
        guard intensity != .off else { return }
        lock.lock()
        if _isRunning { lock.unlock(); return }
        // prepare() is idempotent and cheap after the first call; running it
        // under the lock serializes the whole start critical section so two
        // racing start() calls can never initialize the same command queue /
        // pipelines / buffers concurrently.
        guard prepare() else {
            _isRunning = false
            lock.unlock()
            return
        }
        _isRunning = true
        _stopFlag = false
        _generation += 1
        let gen = _generation

        let pipeline: MTLComputePipelineState?
        switch intensity {
        case .light:     pipeline = lightPipeline
        case .sustained,
             .combinedSoC: pipeline = heavyPipeline
        case .off:       _isRunning = false; lock.unlock(); return
        }

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.loopGroup.enter()
            defer { self.loopGroup.leave() }
            self.gpuLoop(pipeline: pipeline, intensity: intensity, generation: gen)
        }
        workItem = item
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async(execute: item)

        print("[GPUWorkload] Started (\(intensity.displayName)) gen=\(gen)")
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
        // Wait for the old loop to actually exit before returning, so a
        // subsequent start() cannot run two loops concurrently.
        let result = loopGroup.wait(timeout: .now() + 2.0)
        if result == .timedOut {
            print("[GPUWorkload] Warning: loop did not exit within 2s")
        }
        print("[GPUWorkload] Stopped")
    }

    // MARK: - GPU Dispatch Loop

    private func gpuLoop(pipeline: MTLComputePipelineState?, intensity: GPUIntensity, generation: Int) {
        guard let pipeline = pipeline,
              let queue = commandQueue,
              let input = inputBuffer,
              let output = outputBuffer else { return }

        while !stopFlag && generation == self.generation {
            autoreleasepool {
                guard !stopFlag, generation == self.generation,
                      let cmdBuf = queue.makeCommandBuffer(),
                      let encoder = cmdBuf.makeComputeCommandEncoder() else { return }

                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(output, offset: 0, index: 0)
                encoder.setBuffer(input, offset: 0, index: 1)

                let gridSize = MTLSize(width: Self.elementCount, height: 1, depth: 1)
                let threadGroupSize = MTLSize(width: 32, height: 1, depth: 1)
                encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
                encoder.endEncoding()
                cmdBuf.commit()
                cmdBuf.waitUntilCompleted()

                // Surface Metal errors instead of failing silently.
                if cmdBuf.status == .error {
                    let detail = cmdBuf.error.map { String(describing: $0) } ?? "unknown"
                    print("[GPUWorkload] Command buffer error: \(detail)")
                }
            }

            if intensity == .light, !stopFlag {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }
}
