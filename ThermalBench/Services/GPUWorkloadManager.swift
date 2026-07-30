// ThermalBench - GPU Workload Manager
// Bridges Metal compute shaders to Swift for sustained GPU load.
// Uses thermal_gpu_load (heavy) and thermal_gpu_light kernels.
// Thread-safe: all state mutations are serialised through a private queue.
import Metal

final class GPUWorkloadManager {
    private let device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var heavyPipeline: MTLComputePipelineState?
    private var lightPipeline: MTLComputePipelineState?
    private var inputBuffer: MTLBuffer?
    private var outputBuffer: MTLBuffer?

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

        commandQueue = device.makeCommandQueue()

        let bufSize = 16 * MemoryLayout<Float>.size * 4
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

        let item = DispatchWorkItem { [weak self] in
            self?.gpuLoop(pipeline: pipeline, intensity: intensity)
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

    private func gpuLoop(pipeline: MTLComputePipelineState?, intensity: GPUIntensity) {
        guard let pipeline = pipeline,
              let queue = commandQueue,
              let input = inputBuffer,
              let output = outputBuffer else { return }

        while !stopFlag {
            autoreleasepool {
                guard !stopFlag,
                      let cmdBuf = queue.makeCommandBuffer(),
                      let encoder = cmdBuf.makeComputeCommandEncoder() else { return }

                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(output, offset: 0, index: 0)
                encoder.setBuffer(input, offset: 0, index: 1)

                let gridSize = MTLSize(width: 1024, height: 1, depth: 1)
                let threadGroupSize = MTLSize(width: 32, height: 1, depth: 1)
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
