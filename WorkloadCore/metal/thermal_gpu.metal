// ThermalBench - GPU workload (Metal compute shader)
// License: MIT
#include <metal_stdlib>
using namespace metal;

// Configurable intensity: number of inner loop iterations
constant uint KERNEL_INTENSITY = 1024;

kernel void thermal_gpu_load(
    device float4 *output [[buffer(0)]],
    device const float4 *input [[buffer(1)]],
    uint id [[thread_position_in_grid]])
{
    float4 a = input[id % 16];
    float4 b = float4(id * 0.618f, id * 1.618f, id * 2.718f, id * 3.141f);
    float4 c = float4(0.0f);

    // FMA-heavy inner loop (ALU-bound, minimal memory access)
    for (uint i = 0; i < KERNEL_INTENSITY; i++) {
        c = fma(fma(fma(c, a, b), b, c), a, fma(a, b, c));
        c = fma(sin(c), cos(c), c);
        a = fma(a, float4(1.0001f), float4(0.0001f));
        b += float4(c.x * 0.001f, c.y * 0.002f, c.z * 0.003f, c.w * 0.004f);
    }

    output[id] = c;
}

// Lighter kernel for GPU-only load
kernel void thermal_gpu_light(
    device float4 *output [[buffer(0)]],
    device const float4 *input [[buffer(1)]],
    uint id [[thread_position_in_grid]])
{
    float4 a = input[id % 16];
    float4 b = float4(id) * 0.5f;
    float4 c = a;

    for (uint i = 0; i < 256; i++) {
        c = fma(c, a, b);
        a = fma(a, float4(1.001f), c * 0.001f);
    }

    output[id] = c;
}
